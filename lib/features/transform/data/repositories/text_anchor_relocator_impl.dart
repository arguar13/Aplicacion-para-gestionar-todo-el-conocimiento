import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/util/text_anchor_locator.dart';
import 'package:sinapsis/features/transform/domain/repositories/text_anchor_relocator.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// [TextAnchorRelocator] sobre la base (F22).
///
/// Escribe directo en `highlights`, `flashcards`, `flashcard_options`,
/// `relations`, `study_marks`, `dated_events`, el ancla de `processed_parts`
/// (F41) y el lugar de `text_notes` (F45, mejora 19): no hay otra forma de
/// mover una posición, y es un ajuste del mismo dato —dónde está ese
/// fragmento—, no una edición del usuario.
class TextAnchorRelocatorImpl implements TextAnchorRelocator {
  const TextAnchorRelocatorImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<LostHighlight>> relocate({
    required String itemId,
    required String renditionId,
    required String from,
    required String to,
  }) async {
    // Un solo buscador para todo lo que se reubica: el texto nuevo sin cortes
    // de renglón se arma una vez, no una por cada cosa (F41).
    final locator = ExcerptLocator(to);
    ({int start, int end})? find(String excerpt, int oldStart) =>
        locator.locate(
          excerpt,
          near: from.isEmpty ? 0 : oldStart * to.length ~/ from.length,
        );

    // El fragmento que marcaba una posición del texto viejo, si la posición
    // todavía tiene sentido en él.
    String? excerptAt(int? start, int? end) =>
        start == null || end == null || start < 0 || end > from.length
        ? null
        : from.substring(start, end);

    final lost = <LostHighlight>[];
    final highlights = await (_db.select(
      _db.highlights,
    )..where((h) => h.renditionId.equals(renditionId))).get();
    for (final highlight in highlights) {
      final range = find(highlight.excerpt, highlight.startOffset);
      if (range == null) {
        lost.add((excerpt: highlight.excerpt, note: highlight.note));
        await (_db.delete(
          _db.highlights,
        )..where((h) => h.id.equals(highlight.id))).go();
        continue;
      }
      await (_db.update(
        _db.highlights,
      )..where((h) => h.id.equals(highlight.id))).write(
        HighlightsCompanion(
          startOffset: Value(range.start),
          endOffset: Value(range.end),
        ),
      );
    }

    await _relocateStudy(renditionId, from: from, to: to, find: find);
    await _relocateDatedEvents(renditionId, find: find);
    await _relocateTextNotes(itemId, renditionId, find: find);
    await _relocateProcessedParts(
      renditionId,
      excerptAt: excerptAt,
      find: find,
    );
    // Un procesado sin sección «Texto» se estudia sobre el texto de su fuente
    // (F41, decisión I): si ese texto cambió, lo estudiado se vuelve a
    // analizar desde el principio —lo hecho queda, con sus anclas ya
    // reubicadas—.
    await _db.customUpdate(
      'UPDATE processed_documents '
      'SET study_analyzed_until = 0, study_completed_at = NULL '
      'WHERE source_item_id = ? AND NOT EXISTS ( '
      'SELECT 1 FROM processed_parts p '
      'WHERE p.document_id = processed_documents.item_id '
      "AND p.section = 'text')",
      variables: [Variable.withString(itemId)],
      updates: {_db.processedDocuments},
    );

    final cards =
        await (_db.select(_db.flashcards)..where(
              (c) => c.itemId.equals(itemId) & c.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final card in cards) {
      final range = _relocated(
        excerptAt(card.sourceCharStart, card.sourceCharEnd),
        card.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.flashcards,
      )..where((c) => c.id.equals(card.id))).write(
        FlashcardsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
          sourceChunkId: Value(await _chunkAt(itemId, range?.start)),
        ),
      );
    }

    final options =
        await (_db.select(_db.flashcardOptions)..where(
              (o) =>
                  o.sourceItemId.equals(itemId) & o.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final option in options) {
      final range = _relocated(
        excerptAt(option.sourceCharStart, option.sourceCharEnd),
        option.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.flashcardOptions,
      )..where((o) => o.id.equals(option.id))).write(
        FlashcardOptionsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
          sourceChunkId: Value(await _chunkAt(itemId, range?.start)),
        ),
      );
    }

    final extracts =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.toItemId.equals(itemId) &
                  r.kind.equalsValue(RelationKind.extractedFrom) &
                  r.sourceCharStart.isNotNull(),
            ))
            .get();
    for (final extract in extracts) {
      final range = _relocated(
        excerptAt(extract.sourceCharStart, extract.sourceCharEnd),
        extract.sourceCharStart!,
        find,
      );
      await (_db.update(
        _db.relations,
      )..where((r) => r.id.equals(extract.id))).write(
        RelationsCompanion(
          sourceCharStart: Value(range?.start),
          sourceCharEnd: Value(range?.end),
        ),
      );
    }

    return lost;
  }

  /// Lo resaltado para estudiar el texto (F36): cada marca, por su fragmento;
  /// la que no se encuentra se va —es de la IA, o una palabra que ya no está—.
  /// Hasta dónde se había analizado se lleva al final de la última oración
  /// analizada, buscada igual; si no se encuentra, se vuelve a empezar, y
  /// analizar de nuevo reemplaza lo de la IA sin duplicar nada.
  Future<void> _relocateStudy(
    String renditionId, {
    required String from,
    required String to,
    required ({int start, int end})? Function(String excerpt, int oldStart)
    find,
  }) async {
    final marks = await (_db.select(
      _db.studyMarks,
    )..where((m) => m.renditionId.equals(renditionId))).get();
    for (final mark in marks) {
      final range = find(mark.excerpt, mark.startOffset);
      if (range == null) {
        await (_db.delete(
          _db.studyMarks,
        )..where((m) => m.id.equals(mark.id))).go();
        continue;
      }
      await (_db.update(
        _db.studyMarks,
      )..where((m) => m.id.equals(mark.id))).write(
        StudyMarksCompanion(
          startOffset: Value(range.start),
          endOffset: Value(range.end),
        ),
      );
    }

    final analysis = await (_db.select(
      _db.studyAnalyses,
    )..where((a) => a.renditionId.equals(renditionId))).getSingleOrNull();
    if (analysis == null) return;
    final until = analysis.analyzedUntil.clamp(0, from.length);
    final tail = from.substring(
      (until - _studyTailChars).clamp(0, until),
      until,
    );
    final found = tail.trim().isEmpty ? null : find(tail, until - tail.length);
    await (_db.update(
      _db.studyAnalyses,
    )..where((a) => a.renditionId.equals(renditionId))).write(
      StudyAnalysesCompanion(
        analyzedUntil: Value(found?.end ?? 0),
        // Terminado sigue terminado solo si en el texto nuevo tampoco queda
        // nada después: si se agregó texto al final, falta analizarlo.
        completedAt: Value(
          found != null &&
                  analysis.completedAt != null &&
                  to.substring(found.end).trim().isEmpty
              ? analysis.completedAt
              : null,
        ),
      ),
    );
  }

  /// Los hechos fechados que citan el texto (F40): cada cita, por su
  /// fragmento. A diferencia de un subrayado, el hecho que ya no se encuentra
  /// NO se va: la fecha y el título siguen siendo un dato aunque el texto
  /// haya cambiado. Se queda sin posición —y se muestra sin «Abrir en el
  /// documento»—, con su fragmento y la forma de la que salió.
  Future<void> _relocateDatedEvents(
    String renditionId, {
    required ({int start, int end})? Function(String excerpt, int oldStart)
    find,
  }) async {
    final events =
        await (_db.select(_db.datedEvents)..where(
              (e) =>
                  e.renditionId.equals(renditionId) & e.startOffset.isNotNull(),
            ))
            .get();
    for (final event in events) {
      final range = _relocated(event.excerpt, event.startOffset!, find);
      await (_db.update(
        _db.datedEvents,
      )..where((e) => e.id.equals(event.id))).write(
        DatedEventsCompanion(
          startOffset: Value(range?.start),
          endOffset: Value(range?.end),
        ),
      );
    }
  }

  /// Las notas en el texto que valen sobre este texto (F45, mejora 19), cada
  /// una por su pedazo citado: las del original de la fuente escritas sobre
  /// esta forma, las de la copia del original de sus documentos procesados —en
  /// las posiciones del texto de la fuente, como lo elegido— y las del texto
  /// propio de un procesado que no tiene «Texto» y se lee sobre el de su
  /// fuente (decisión I de F41).
  ///
  /// Como un hecho fechado, la que ya no se encuentra NO se va: queda sin
  /// lugar, con lo que dice y su pedazo, y vuelve a buscarse la próxima vez
  /// —la que estaba sin lugar también se busca, y si el texto nuevo la tiene,
  /// vuelve a su lugar—. Ni la fecha de la nota ni su escritura cambian:
  /// moverla no es editarla.
  Future<void> _relocateTextNotes(
    String itemId,
    String renditionId, {
    required ({int start, int end})? Function(String excerpt, int oldStart)
    find,
  }) async {
    final notes = await _db
        .customSelect(
          'SELECT * FROM text_notes n '
          "WHERE (n.target = 'source_original' AND n.rendition_id = ?1) "
          "OR (n.target = 'processed_original' AND n.item_id IN ( "
          'SELECT d.item_id FROM processed_documents d '
          'WHERE d.source_item_id = ?2)) '
          "OR (n.target = 'processed_text' AND n.item_id IN ( "
          'SELECT d.item_id FROM processed_documents d '
          'WHERE d.source_item_id = ?2 AND NOT EXISTS ( '
          'SELECT 1 FROM processed_parts p '
          "WHERE p.document_id = d.item_id AND p.section = 'text')))",
          variables: [
            Variable.withString(renditionId),
            Variable.withString(itemId),
          ],
          readsFrom: {_db.textNotes},
        )
        .asyncMap(_db.textNotes.mapFromRow)
        .get();
    for (final note in notes) {
      final range = _relocated(note.excerpt, note.startOffset ?? 0, find);
      if (range?.start == note.startOffset && range?.end == note.endOffset) {
        continue;
      }
      await (_db.update(
        _db.textNotes,
      )..where((n) => n.id.equals(note.id))).write(
        TextNotesCompanion(
          startOffset: Value(range?.start),
          endOffset: Value(range?.end),
        ),
      );
    }
  }

  /// Las partes de los documentos procesados que anclan el texto (F41): cada
  /// una, por el pasaje que su ancla marcaba en el texto viejo —su propio
  /// texto puede estar editado, y no es lo que hay que buscar—. La que ya no
  /// se encuentra NO se va: es una copia propia, con su texto. Pierde el enlace
  /// («Abrir en el original» ya no tiene dónde) y conserva sus posiciones.
  Future<void> _relocateProcessedParts(
    String renditionId, {
    required String? Function(int? start, int? end) excerptAt,
    required ({int start, int end})? Function(String excerpt, int oldStart)
    find,
  }) async {
    final parts = await (_db.select(
      _db.processedParts,
    )..where((p) => p.sourceRenditionId.equals(renditionId))).get();
    for (final part in parts) {
      final start = part.sourceStart;
      final range = start == null
          ? null
          : _relocated(excerptAt(start, part.sourceEnd), start, find);
      await (_db.update(
        _db.processedParts,
      )..where((p) => p.id.equals(part.id))).write(
        range == null
            ? const ProcessedPartsCompanion(sourceRenditionId: Value(null))
            : ProcessedPartsCompanion(
                sourceStart: Value(range.start),
                sourceEnd: Value(range.end),
              ),
      );
    }
  }

  ({int start, int end})? _relocated(
    String? excerpt,
    int oldStart,
    ({int start, int end})? Function(String excerpt, int oldStart) find,
  ) => excerpt == null || excerpt.trim().isEmpty
      ? null
      : find(excerpt, oldStart);

  /// El chunk de [itemId] que contiene la posición [offset] del texto: los
  /// chunks se rehicieron con el texto nuevo, y los de antes ya no existen.
  Future<String?> _chunkAt(String itemId, int? offset) async {
    if (offset == null) return null;
    final chunk =
        await (_db.select(_db.chunks)
              ..where(
                (c) =>
                    c.itemId.equals(itemId) &
                    c.charStart.isSmallerOrEqualValue(offset) &
                    c.charEnd.isBiggerThanValue(offset),
              )
              ..limit(1))
            .getSingleOrNull();
    return chunk?.id;
  }
}

/// Cuánto del final de lo analizado se busca en el texto nuevo para saber
/// hasta dónde llegaba (F36): lo bastante para que no aparezca dos veces.
const _studyTailChars = 80;
