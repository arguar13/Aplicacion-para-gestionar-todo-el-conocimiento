import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_rows.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Lo que antecede al id de una marca de estudio de un procesado: con él, la
/// máquina de estudiar sabe a quién pedirle que la saque.
const kProcessedStudyMarkPrefix = kProcessedStudyKeyPrefix;

/// Estudiar un documento procesado en él mismo (F41, decisión I): el
/// [StudyRepository] de las claves de procesado (`processedStudyKeyFor`).
///
/// La máquina de estudiar de siempre (F36, F39) —«Resumir», «Sintetizar», las
/// palabras clave con su respaldo local (decisión 85), «Elegir a mano»— corre
/// igual que sobre una fuente; lo que cambia es dónde queda lo estudiado: en
/// las partes del procesado, como propias —`studied` lo de la IA, `chosen` lo
/// de la persona—, con su lugar en el texto propio y, si su página es todavía
/// la de la fuente, también en la fuente. «Actualizar» desde la fuente no lo
/// pisa; «Reemplazar», sí.
///
/// Lo que se le da a la máquina como estudiado de ese texto son todas las
/// partes del resumen, la síntesis y las palabras clave que tienen lugar en él
/// —también las copiadas de la fuente, como de la persona: un análisis no las
/// reemplaza—.
class ProcessedStudyRepositoryImpl implements StudyRepository {
  ProcessedStudyRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  static const _studySections = [
    ProcessedSection.summary,
    ProcessedSection.synthesis,
    ProcessedSection.keywords,
  ];

  @override
  Stream<DocumentStudy> watch(String renditionId) => watchQuery(
    db: _db,
    tables: [_db.processedParts, _db.processedDocuments],
    read: () => read(renditionId),
    telemetry: _telemetry,
    hint: 'ProcessedStudyRepositoryImpl.watch',
  );

  @override
  Future<DocumentStudy> read(String renditionId) async {
    final documentId = _documentOf(renditionId);
    final document = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(documentId))).getSingleOrNull();
    if (document == null) return DocumentStudy.notStarted;
    final place = await _placeOf(documentId);
    final marks = <StudyMark>[];
    for (final part in await _studyParts(documentId)) {
      final own = place(part);
      if (own == null) continue;
      switch (part.section) {
        case ProcessedSection.summary || ProcessedSection.synthesis:
          marks.add(
            StudyMark(
              id: '$kProcessedStudyMarkPrefix${part.id}',
              kind: part.section == ProcessedSection.summary
                  ? StudyMarkKind.summary
                  : StudyMarkKind.synthesis,
              origin: part.origin == ProcessedPartOrigin.studied
                  ? ContentOrigin.ai
                  : ContentOrigin.user,
              start: own.start,
              end: own.end,
            ),
          );
        case ProcessedSection.keywords:
          for (var i = 0; i < part.spans.length; i++) {
            final span = part.spans[i];
            marks.add(
              StudyMark(
                id: '$kProcessedStudyMarkPrefix${part.id}#$i',
                kind: StudyMarkKind.keyword,
                origin: part.isStudiedHere && !span.chosen
                    ? ContentOrigin.ai
                    : ContentOrigin.user,
                start: own.start + span.start,
                end: own.start + span.end,
              ),
            );
          }
        case ProcessedSection.text ||
            ProcessedSection.notes ||
            ProcessedSection.fragments:
          break;
      }
    }
    marks.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      final byEnd = a.end.compareTo(b.end);
      return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
    });
    return DocumentStudy(
      marks: marks,
      analyzedUntil: document.studyAnalyzedUntil,
      complete: document.studyCompletedAt != null,
    );
  }

  @override
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  }) => _guard('savePart', () async {
    final documentId = _documentOf(renditionId);
    await _db.transaction(() async {
      final place = await _placeOf(documentId);
      final layout = await _layoutOf(documentId);
      bool within(ProcessedPart part) {
        final own = place(part);
        return own != null && own.start >= partStart && own.end <= partEnd;
      }

      // Lo que la IA había marcado en esta parte se rehace; lo de la persona
      // y lo copiado de la fuente queda.
      final parts = await _studyParts(documentId);
      final gone = <String>[];
      final rewritten = <ProcessedPart>[];
      for (final part in parts) {
        if (!within(part)) continue;
        if (part.section != ProcessedSection.keywords) {
          if (part.origin == ProcessedPartOrigin.studied) gone.add(part.id);
          continue;
        }
        if (!part.isStudiedHere) continue;
        final kept = [
          for (final span in part.spans)
            if (span.chosen) span,
        ];
        if (kept.isEmpty) {
          gone.add(part.id);
        } else if (kept.length != part.spans.length) {
          rewritten.add(part.copyWith(spans: kept));
        }
      }
      await _deleteParts(gone);
      for (final part in rewritten) {
        await _writeSpans(part);
      }

      final remaining = [
        for (final part in parts)
          if (!gone.contains(part.id))
            rewritten.where((r) => r.id == part.id).firstOrNull ?? part,
      ];
      final at = _clock();
      for (final (section, sentences) in [
        (ProcessedSection.summary, marks.summary),
        (ProcessedSection.synthesis, marks.synthesis),
      ]) {
        for (final sentence in sentences) {
          final taken = remaining.any(
            (part) =>
                part.section == section &&
                _same(place(part), sentence.start, sentence.end),
          );
          if (taken) continue;
          await _insert(
            documentId: documentId,
            section: section,
            origin: ProcessedPartOrigin.studied,
            content: content,
            start: sentence.start,
            end: sentence.end,
            layout: layout,
            at: at,
          );
        }
      }
      await _addKeywords(
        documentId: documentId,
        content: content,
        sentences: _sentencesAround(
          content,
          partStart,
          partEnd,
          markdown: await processedTextIsMarkdown(_db, documentId),
        ),
        words: marks.keywords,
        chosen: false,
        place: place,
        existing: remaining,
        layout: layout,
        at: at,
      );
      await _renumber(documentId);
      await (_db.update(
        _db.processedDocuments,
      )..where((d) => d.itemId.equals(documentId))).write(
        ProcessedDocumentsCompanion(
          studyAnalyzedUntil: Value(partEnd),
          studyCompletedAt: Value(completes ? at : null),
        ),
      );
      await _writer.markContentChanged(documentId);
    });
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) => _guard('addAiKeywords', () async {
    if (words.isEmpty) return right(unit);
    final documentId = _documentOf(renditionId);
    final markdown = await processedTextIsMarkdown(_db, documentId);
    // Las oraciones del texto entero, en otro hilo si es largo: las palabras
    // pueden venir de cualquier parte.
    final sentences = await runProcessedWork(_sentencesInWorker, (
      content: content,
      markdown: markdown,
    ), size: content.length);
    await _db.transaction(() async {
      await _addKeywords(
        documentId: documentId,
        content: content,
        sentences: sentences,
        words: words,
        chosen: false,
        place: await _placeOf(documentId),
        existing: await _studyParts(documentId),
        layout: await _layoutOf(documentId),
        at: _clock(),
      );
      await _renumber(documentId);
      await _writer.markContentChanged(documentId);
    });
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) => _guard('addUserMark', () async {
    if (start < 0 || end > content.length || end <= start) {
      return left(
        const Failure.validation(message: 'Lo elegido no está en el texto.'),
      );
    }
    final documentId = _documentOf(renditionId);
    await _db.transaction(() async {
      final place = await _placeOf(documentId);
      final layout = await _layoutOf(documentId);
      final parts = await _studyParts(documentId);
      final at = _clock();
      if (kind == StudyMarkKind.keyword) {
        await _addKeywords(
          documentId: documentId,
          content: content,
          sentences: _sentencesAround(
            content,
            start,
            end,
            markdown: await processedTextIsMarkdown(_db, documentId),
          ),
          words: [StudyWord(start, end, content.substring(start, end))],
          chosen: true,
          place: place,
          existing: parts,
          layout: layout,
          at: at,
        );
      } else {
        final section = kind == StudyMarkKind.summary
            ? ProcessedSection.summary
            : ProcessedSection.synthesis;
        final taken = parts.any(
          (part) => part.section == section && _same(place(part), start, end),
        );
        if (!taken) {
          await _insert(
            documentId: documentId,
            section: section,
            origin: ProcessedPartOrigin.chosen,
            content: content,
            start: start,
            end: end,
            layout: layout,
            at: at,
          );
        }
      }
      await _renumber(documentId);
      await _writer.markContentChanged(documentId);
    });
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> removeMark(String markId) =>
      _guard('removeMark', () async {
        final id = markId.startsWith(kProcessedStudyMarkPrefix)
            ? markId.substring(kProcessedStudyMarkPrefix.length)
            : markId;
        final hash = id.indexOf('#');
        final partId = hash < 0 ? id : id.substring(0, hash);
        final row = await (_db.select(
          _db.processedParts,
        )..where((p) => p.id.equals(partId))).getSingleOrNull();
        if (row == null) return right(unit);
        final part = processedPartFromRow(row);
        await _db.transaction(() async {
          final index = hash < 0 ? null : int.tryParse(id.substring(hash + 1));
          if (part.section == ProcessedSection.keywords && index != null) {
            final spans = [...part.spans];
            if (index >= 0 && index < spans.length) spans.removeAt(index);
            if (spans.isEmpty) {
              await _deleteParts([part.id]);
            } else {
              await _writeSpans(part.copyWith(spans: spans));
              // Sacarle una palabra a una copiada es cambiarla: ya no es lo de
              // la fuente.
              if (part.origin == ProcessedPartOrigin.copied) {
                await (_db.update(_db.processedParts)
                      ..where((p) => p.id.equals(part.id)))
                    .write(const ProcessedPartsCompanion(edited: Value(true)));
              }
            }
          } else {
            await _deleteParts([part.id]);
          }
          await _renumber(part.documentId);
          await _writer.markContentChanged(part.documentId);
        });
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) =>
      _guard('clearAi', () async {
        final documentId = _documentOf(renditionId);
        await _db.transaction(() async {
          final gone = <String>[];
          for (final part in await _studyParts(documentId)) {
            if (part.origin == ProcessedPartOrigin.studied &&
                part.section != ProcessedSection.keywords) {
              gone.add(part.id);
              continue;
            }
            if (part.section != ProcessedSection.keywords ||
                !part.isStudiedHere) {
              continue;
            }
            final kept = [
              for (final span in part.spans)
                if (span.chosen) span,
            ];
            if (kept.isEmpty) {
              gone.add(part.id);
            } else if (kept.length != part.spans.length) {
              await _writeSpans(part.copyWith(spans: kept));
            }
          }
          await _deleteParts(gone);
          await _renumber(documentId);
          await (_db.update(
            _db.processedDocuments,
          )..where((d) => d.itemId.equals(documentId))).write(
            const ProcessedDocumentsCompanion(
              studyAnalyzedUntil: Value(0),
              studyCompletedAt: Value(null),
            ),
          );
          await _writer.markContentChanged(documentId);
        });
        return right(unit);
      });

  // ---------------------------------------------------------------------

  String _documentOf(String key) {
    final id = processedDocumentOfStudyKey(key);
    if (id == null) {
      throw ArgumentError.value(key, 'renditionId', 'No es de un procesado.');
    }
    return id;
  }

  /// Dónde está cada parte en el texto que se estudia: con «Texto», su lugar
  /// en él; sin «Texto», su ancla en el texto de la fuente, que es el propio.
  Future<ProcessedSpan? Function(ProcessedPart)> _placeOf(
    String documentId,
  ) async {
    final layout = await _layoutOf(documentId);
    if (layout == null) return (ProcessedPart _) => null;
    if (layout.hasPages) return (ProcessedPart part) => part.textRange;
    return (ProcessedPart part) {
      final anchor = part.anchor;
      if (anchor == null || !part.isVerbatim) return null;
      return layout.ownOf(anchor);
    };
  }

  /// El texto que se estudia de [documentId]: sus páginas o, sin ellas, el
  /// texto de su fuente. `null` si no tiene ninguno.
  Future<ProcessedStudyLayout?> _layoutOf(String documentId) async {
    final pages = await pagesLayoutOf(_db, documentId);
    if (pages != null) return pages;
    final document = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(documentId))).getSingleOrNull();
    final sourceId = document?.sourceItemId;
    if (sourceId == null) return null;
    final text = await sourceTextRenditionInfo(_db, sourceId);
    return text == null ? null : ProcessedStudyLayout.source(text.id);
  }

  Future<List<ProcessedPart>> _studyParts(String documentId) async {
    final rows =
        await (_db.select(_db.processedParts)
              ..where(
                (p) =>
                    p.documentId.equals(documentId) &
                    p.section.isIn([for (final s in _studySections) s.name]),
              )
              ..orderBy([
                (p) => OrderingTerm.asc(p.position),
                (p) => OrderingTerm.asc(p.id),
              ]))
            .get();
    return [for (final row in rows) processedPartFromRow(row)];
  }

  static bool _same(ProcessedSpan? own, int start, int end) =>
      own != null && own.start == start && own.end == end;

  /// Una parte nueva del procesado con `[start, end)` de [content]: con su
  /// lugar en el texto propio si tiene páginas, y en la fuente si ese tramo es
  /// todavía el de la fuente.
  Future<String> _insert({
    required String documentId,
    required ProcessedSection section,
    required ProcessedPartOrigin origin,
    required String content,
    required int start,
    required int end,
    required ProcessedStudyLayout? layout,
    required DateTime at,
    List<ProcessedSpan> spans = const [],
  }) async {
    final source = layout?.sourceOf(start, end);
    final pages = layout?.hasPages ?? false;
    final id = _ids.next();
    await _db
        .into(_db.processedParts)
        .insert(
          ProcessedPartsCompanion.insert(
            id: id,
            documentId: documentId,
            section: section,
            // Al final; [_renumber] la lleva a su lugar.
            position: 1 << 30,
            content: content.substring(start, end),
            origin: origin,
            sourceRenditionId: Value(source?.renditionId),
            sourceStart: Value(source?.start),
            sourceEnd: Value(source?.end),
            textStart: Value(pages ? start : null),
            textEnd: Value(pages ? end : null),
            spans: Value(encodeProcessedSpans(section, spans)),
            createdAt: at,
            updatedAt: at,
          ),
        );
    return id;
  }

  /// Pone [words] en las oraciones de [sentences] que las tienen: en la parte
  /// propia de esa oración si ya tiene una —sin repetir una palabra—, o en
  /// una nueva. La oración que ya trae palabras clave copiadas de la fuente no
  /// recibe las de la IA —ya tiene las suyas—, pero sí las que elige la
  /// persona.
  Future<void> _addKeywords({
    required String documentId,
    required String content,
    required List<StudySentence> sentences,
    required List<StudyWord> words,
    required bool chosen,
    required ProcessedSpan? Function(ProcessedPart) place,
    required List<ProcessedPart> existing,
    required ProcessedStudyLayout? layout,
    required DateTime at,
  }) async {
    final bySentence = <StudySentence, List<StudyWord>>{};
    for (final word in words) {
      final sentence = sentences
          .where((s) => s.start <= word.start && word.end <= s.end)
          .firstOrNull;
      if (sentence == null) continue;
      (bySentence[sentence] ??= []).add(word);
    }
    for (final MapEntry(key: sentence, value: found) in bySentence.entries) {
      final keywordParts = [
        for (final part in existing)
          if (part.section == ProcessedSection.keywords &&
              _same(place(part), sentence.start, sentence.end))
            part,
      ];
      final own = keywordParts.where((p) => p.isStudiedHere).firstOrNull;
      final copied = keywordParts.where((p) => !p.isStudiedHere).firstOrNull;
      final target = own ?? (chosen ? copied : null);
      if (target == null && copied != null) continue;
      final spans = [...?target?.spans];
      for (final word in found) {
        final span = ProcessedSpan(
          start: word.start - sentence.start,
          end: word.end - sentence.start,
          chosen: chosen,
        );
        if (spans.any((s) => s.start == span.start && s.end == span.end)) {
          continue;
        }
        spans.add(span);
      }
      spans.sort((a, b) => a.start.compareTo(b.start));
      if (target != null) {
        if (spans.length != target.spans.length) {
          await _writeSpans(target.copyWith(spans: spans));
        }
        continue;
      }
      await _insert(
        documentId: documentId,
        section: ProcessedSection.keywords,
        origin: chosen
            ? ProcessedPartOrigin.chosen
            : ProcessedPartOrigin.studied,
        content: content,
        start: sentence.start,
        end: sentence.end,
        layout: layout,
        at: at,
        spans: spans,
      );
    }
  }

  /// Las oraciones del tramo `[start, end)` de [content] —con un margen, para
  /// que la oración que lo contiene entre entera—, con sus posiciones en el
  /// texto entero. Cuesta lo que mide el tramo, no el libro.
  static List<StudySentence> _sentencesAround(
    String content,
    int start,
    int end, {
    required bool markdown,
  }) {
    const margin = 2000;
    final from = (start - margin).clamp(0, content.length);
    final to = (end + margin).clamp(0, content.length);
    return [
      for (final sentence in splitStudySentences(
        content.substring(from, to),
        markdown: markdown,
      ))
        StudySentence(from + sentence.start, from + sentence.end),
    ];
  }

  Future<void> _writeSpans(ProcessedPart part) =>
      (_db.update(
        _db.processedParts,
      )..where((p) => p.id.equals(part.id))).write(
        ProcessedPartsCompanion(
          spans: Value(encodeProcessedSpans(part.section, part.spans)),
          updatedAt: Value(_clock()),
        ),
      );

  Future<void> _deleteParts(List<String> ids) async {
    for (var start = 0; start < ids.length; start += 400) {
      final slice = ids.skip(start).take(400).toList();
      await (_db.delete(
        _db.processedParts,
      )..where((p) => p.id.isIn(slice))).go();
    }
  }

  /// Las secciones de estudiar de [documentId] en el orden de su texto: lo que
  /// tiene lugar, por su lugar; lo demás, después, en el orden que tenía.
  Future<void> _renumber(String documentId) async {
    final place = await _placeOf(documentId);
    final parts = await _studyParts(documentId);
    await _db.batch((batch) {
      for (final section in _studySections) {
        final ordered = [
          for (final part in parts)
            if (part.section == section) part,
        ];
        int key(ProcessedPart part) => place(part)?.start ?? (1 << 40);
        final sorted = [...ordered]
          ..sort((a, b) {
            final byPlace = key(a).compareTo(key(b));
            return byPlace != 0 ? byPlace : a.position.compareTo(b.position);
          });
        for (var i = 0; i < sorted.length; i++) {
          if (sorted[i].position == i) continue;
          batch.update(
            _db.processedParts,
            ProcessedPartsCompanion(position: Value(i)),
            where: (p) => p.id.equals(sorted[i].id),
          );
        }
      }
    });
  }

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessedStudyRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

List<StudySentence> _sentencesInWorker(({String content, bool markdown}) job) =>
    splitStudySentences(job.content, markdown: job.markdown);
