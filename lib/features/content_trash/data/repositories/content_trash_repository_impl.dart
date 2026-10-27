import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/file_references.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/domain/repositories/content_trash_repository.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_original_trash.dart';

/// [ContentTrashRepository] sobre la base (`content_trash`, v38) y el
/// almacén de archivos.
///
/// Soltar y recuperar son una transacción cada uno: o el elemento queda con
/// su mitad en la papelera, o queda como estaba. El disco se toca solo al
/// vencer —y después de la base—, nunca antes de los 30 días: un archivo
/// soltado sigue donde estaba.
class ContentTrashRepositoryImpl implements ContentTrashRepository {
  ContentTrashRepositoryImpl({
    required AppDatabase database,
    required FileStore files,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _files = files,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final FileStore _files;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  /// Quien escribe la fuente: ver [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  $TrashedContentsTable get _trash => _db.trashedContents;

  @override
  Future<Either<Failure, List<TrashedContent>>> keepOnlyText(String itemId) =>
      _guard('keepOnlyText', () async {
        final halves = await _halvesOf(itemId);
        if (halves == null) return left(_cannotSplit(itemId));
        final (:path, texts: _) = halves;

        // Afuera de la transacción: medir el archivo es leer el disco.
        final size = await _files.sizeOf(path);
        final row = TrashedContentsCompanion.insert(
          id: _ids.next(),
          itemId: itemId,
          kind: TrashedContentKind.file,
          relativePath: Value(path),
          sizeBytes: Value(size),
          trashedAt: _clock(),
        );
        await _db.transaction(() async {
          await _db.into(_trash).insert(row);
          // Por el escritor: es un campo con linaje (`originalBlobPath`), y una
          // fusión tiene que saber que acá se soltó.
          await _writer.setFieldFromText(
            itemId,
            EntryField.originalBlobPath,
            null,
          );
        });
        return right([_toEntity(await _rowById(row.id.value))]);
      });

  @override
  Future<Either<Failure, List<TrashedContent>>> keepOnlyFile(
    String itemId,
  ) => _guard('keepOnlyFile', () async {
    final halves = await _halvesOf(itemId);
    if (halves == null) return left(_cannotSplit(itemId));

    final ids = <String>[];
    await _db.transaction(() async {
      final now = _clock();
      for (final text in halves.texts) {
        final highlights = await (_db.select(
          _db.highlights,
        )..where((h) => h.renditionId.equals(text.id))).get();
        final studyMarks = await (_db.select(
          _db.studyMarks,
        )..where((m) => m.renditionId.equals(text.id))).get();
        final studyAnalysis = await (_db.select(
          _db.studyAnalyses,
        )..where((a) => a.renditionId.equals(text.id))).getSingleOrNull();
        final datedEvents = await (_db.select(
          _db.datedEvents,
        )..where((e) => e.renditionId.equals(text.id))).get();
        final processedParts =
            await (_db.selectOnly(_db.processedParts)
                  ..addColumns([_db.processedParts.id])
                  ..where(_db.processedParts.sourceRenditionId.equals(text.id)))
                .map((row) => row.read(_db.processedParts.id)!)
                .get();
        final id = _ids.next();
        await _db
            .into(_trash)
            .insert(
              TrashedContentsCompanion.insert(
                id: id,
                itemId: itemId,
                kind: TrashedContentKind.text,
                renditionId: Value(text.id),
                renditionKind: Value(text.kind),
                content: Value(text.content),
                isPrimary: Value(text.isPrimary),
                renditionCreatedAt: Value(text.createdAt),
                wordTimings: Value(text.wordTimings),
                highlights: Value(encodeTrashedHighlights(highlights)),
                studyMarks: Value(
                  encodeTrashedStudy(studyMarks, studyAnalysis),
                ),
                datedEvents: Value(encodeTrashedDatedEvents(datedEvents)),
                processedParts: Value(
                  encodeTrashedProcessedParts(processedParts),
                ),
                trashedAt: now,
              ),
            );
        ids.add(id);
        // Los subrayados, lo resaltado para estudiar y los hechos fechados que
        // la citan se van con la forma, en cascada: ya están copiados. Las
        // partes de lo procesado que la anclaban se quedan —son una copia
        // propia, con su texto y sus posiciones—: solo pierden el enlace.
        await (_db.delete(
          _db.renditions,
        )..where((r) => r.id.equals(text.id))).go();
      }
      // Los chunks describen un texto que ya no está: la búsqueda no puede
      // encontrar el elemento por él ni citar un pasaje que no se ve. Sus
      // vectores se van con ellos; recuperar el texto los rehace.
      await (_db.delete(
        _db.chunks,
      )..where((c) => c.itemId.equals(itemId))).go();
      await _writer.setOnlyFile(itemId, onlyFile: true);
    });
    return right([for (final id in ids) _toEntity(await _rowById(id))]);
  });

  @override
  Future<Either<Failure, ContentRestoreOutcome>> restore(String trashedId) =>
      _guard('restore', () async {
        final row = await (_db.select(
          _trash,
        )..where((t) => t.id.equals(trashedId))).getSingleOrNull();
        if (row == null) return right(ContentRestoreOutcome.gone);
        return right(switch (row.kind) {
          TrashedContentKind.file => await _restoreFile(row),
          TrashedContentKind.text => await _restoreText(row),
        });
      });

  Future<ContentRestoreOutcome> _restoreFile(TrashedContentRow row) async {
    final path = row.relativePath!;
    if (row.processedOriginal != null) return _restoreProcessedOriginal(row);
    final source = await _sourceOf(row.itemId);
    final current = source?.originalBlobPath;
    if (current != null && current != path) {
      return ContentRestoreOutcome.alreadyHasFile;
    }
    if (!await _files.exists(path)) {
      // Alguien vació el almacenamiento de la app: no hay qué recuperar, y
      // dejarlo en la papelera prometería algo que no está.
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
      return ContentRestoreOutcome.fileMissing;
    }
    await _db.transaction(() async {
      if (current == null) {
        await _writer.setFieldFromText(
          row.itemId,
          EntryField.originalBlobPath,
          path,
        );
      }
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
    });
    return ContentRestoreOutcome.restored;
  }

  /// La copia del original de un documento procesado (F41, decisión H) vuelve
  /// a ser su original, si el documento no consiguió otro mientras tanto.
  Future<ContentRestoreOutcome> _restoreProcessedOriginal(
    TrashedContentRow row,
  ) async {
    if (!await _files.exists(row.relativePath!)) {
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
      return ContentRestoreOutcome.fileMissing;
    }
    final restored = await _db.transaction(
      () => restoreTrashedProcessedOriginal(_db, row),
    );
    return restored
        ? ContentRestoreOutcome.restored
        : ContentRestoreOutcome.alreadyHasFile;
  }

  Future<ContentRestoreOutcome> _restoreText(TrashedContentRow row) async {
    await _db.transaction(() async {
      final taken =
          await (_db.select(
            _db.renditions,
          )..where((r) => r.id.equals(row.renditionId!))).getSingleOrNull() !=
          null;
      // El mismo identificador, para que valgan de nuevo los subrayados y lo
      // que apuntaba a ese texto. Si otra forma lo ocupa —no debería: la
      // fusión no trae de vuelta lo soltado acá—, uno nuevo, con los
      // subrayados detrás.
      final id = taken ? _ids.next() : row.renditionId!;
      // Principal si lo era y el elemento no consiguió otro texto principal
      // mientras tanto —se volvió a extraer—: recuperar nunca le saca el
      // lugar a lo que hay.
      final hasPrimary = await _mainTextsOf(
        row.itemId,
      ).then((texts) => texts.any((t) => t.isPrimary));
      await _db
          .into(_db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: id,
              itemId: row.itemId,
              kind: row.renditionKind!,
              content: Value(row.content),
              isPrimary: row.isPrimary! && !hasPrimary,
              createdAt: row.renditionCreatedAt!,
              wordTimings: Value(row.wordTimings),
            ),
          );
      for (final highlight in decodeTrashedHighlights(row.highlights)) {
        await _db
            .into(_db.highlights)
            .insert(
              highlight.copyWith(renditionId: Value(id)),
              mode: InsertMode.insertOrIgnore,
            );
      }
      final study = decodeTrashedStudy(row.studyMarks, renditionId: id);
      for (final mark in study.marks) {
        await _db
            .into(_db.studyMarks)
            .insert(mark, mode: InsertMode.insertOrIgnore);
      }
      if (study.analysis case final analysis?) {
        await _db
            .into(_db.studyAnalyses)
            .insert(analysis, mode: InsertMode.insertOrIgnore);
      }
      for (final event in decodeTrashedDatedEvents(
        row.datedEvents,
        itemId: row.itemId,
        renditionId: id,
      )) {
        // La pasada que lo puso pudo irse mientras tanto (deshacer no la
        // borra, pero su elemento sí): el hecho vuelve igual, sin ella.
        final run = event.aiRunId.value;
        final runExists =
            run != null &&
            await (_db.select(
                  _db.aiRuns,
                )..where((r) => r.id.equals(run))).getSingleOrNull() !=
                null;
        await _db
            .into(_db.datedEvents)
            .insert(
              runExists ? event : event.copyWith(aiRunId: const Value(null)),
              mode: InsertMode.insertOrIgnore,
            );
      }
      // Las partes de lo procesado que anclaban este texto vuelven a abrirse
      // en él (F41). Solo las que siguen sin enlace: una que mientras tanto se
      // volvió a anclar en otro texto no se toca.
      final parts = decodeTrashedProcessedParts(row.processedParts);
      for (var start = 0; start < parts.length; start += 400) {
        final slice = parts.skip(start).take(400).toList();
        await (_db.update(_db.processedParts)
              ..where((p) => p.id.isIn(slice) & p.sourceRenditionId.isNull()))
            .write(ProcessedPartsCompanion(sourceRenditionId: Value(id)));
      }
      await (_db.delete(_trash)..where((t) => t.id.equals(row.id))).go();
      await _writer.setOnlyFile(row.itemId, onlyFile: false);
      await chunkAndPersistSource(
        _db,
        itemId: row.itemId,
        ids: _ids,
        reportedBy: 'f30_content_trash',
        assignPages: true,
      );
    });
    return ContentRestoreOutcome.restored;
  }

  @override
  Stream<List<TrashedContent>> watchOf(String itemId) =>
      (_db.select(_trash)
            ..where((t) => t.itemId.equals(itemId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.trashedAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch()
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<Either<Failure, int>> purgeExpired() => _guard(
    'purgeExpired',
    () async {
      final cutoff = _clock().subtract(kContentTrashRetention);
      final expired = await (_db.select(
        _trash,
      )..where((t) => t.trashedAt.isSmallerOrEqualValue(cutoff))).get();

      var purged = 0;
      for (final row in expired) {
        // La fila primero, el disco después: si el archivo se resiste, queda un
        // archivo de más —que se avisa—, nunca una papelera que promete algo
        // que ya no está.
        final deleted = await (_db.delete(
          _trash,
        )..where((t) => t.id.equals(row.id))).go();
        if (deleted == 0) continue;
        purged++;
        final path = row.relativePath;
        if (path != null && !await isFileReferenced(_db, path)) {
          await _deleteFileQuietly(path, row.itemId);
        }
      }
      return right(purged);
    },
  );

  // ---------------------------------------------------------------------

  /// El archivo y los textos de [itemId] —lo que se puede separar—, o `null`
  /// si le falta alguna de las dos mitades o ya no está vivo.
  Future<({String path, List<RenditionRow> texts})?> _halvesOf(
    String itemId,
  ) async {
    final alive = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
    if (alive == null) return null;
    final path = (await _sourceOf(itemId))?.originalBlobPath;
    if (path == null) return null;
    final texts = [
      for (final text in await _mainTextsOf(itemId))
        if (text.content!.trim().isNotEmpty) text,
    ];
    if (texts.isEmpty) return null;
    return (path: path, texts: texts);
  }

  /// Las formas de texto del elemento en sí: sin las del «Contenido» (F30) ni
  /// las de bloques —esas son de las notas—.
  Future<List<RenditionRow>> _mainTextsOf(String itemId) =>
      (_db.select(_db.renditions)..where(
            (r) =>
                r.itemId.equals(itemId) &
                r.content.isNotNull() &
                r.position.isNull() &
                r.textOf.isNull() &
                r.kind.equalsValue(RenditionKind.blocks).not(),
          ))
          .get();

  Future<KnowledgeSourceRow?> _sourceOf(String itemId) => (_db.select(
    _db.knowledgeSources,
  )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();

  Future<TrashedContentRow> _rowById(String id) =>
      (_db.select(_trash)..where((t) => t.id.equals(id))).getSingle();

  TrashedContent _toEntity(TrashedContentRow row) => TrashedContent(
    id: row.id,
    itemId: row.itemId,
    kind: row.kind,
    trashedAt: row.trashedAt,
    sizeBytes: row.sizeBytes,
    textLength: row.content?.length,
  );

  Failure _cannotSplit(String itemId) => Failure.unexpected(
    message:
        'El elemento $itemId no tiene archivo y texto a la vez: no hay una '
        'mitad que soltar sin dejarlo vacío.',
  );

  Future<void> _deleteFileQuietly(String path, String itemId) async {
    try {
      await _files.delete(path);
      // Catch-all deliberado: el disco puede fallar de muchas formas, y
      // ninguna vuelve atrás un vencimiento que en la base ya ocurrió.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint:
            'ContentTrashRepositoryImpl.purgeExpired: quedó el archivo de '
            '$itemId',
      );
    }
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
        hint: 'ContentTrashRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}

/// Los subrayados de una forma de texto, para guardarlos en la papelera con
/// ella: en la base cuelgan de la forma, y al soltarla se irían en cascada.
String encodeTrashedHighlights(List<HighlightRow> highlights) => jsonEncode([
  for (final h in highlights)
    {
      'id': h.id,
      'start': h.startOffset,
      'end': h.endOffset,
      'excerpt': h.excerpt,
      if (h.note != null) 'note': h.note,
      'createdAt': h.createdAt.millisecondsSinceEpoch,
      // Cómo se ve (F38). Lo soltado antes no lo tiene: el de siempre.
      if (h.color case final color?) 'color': color.name,
      'style': h.style.name,
    },
]);

/// Lo guardado por [encodeTrashedHighlights], listo para volver a la base
/// (con la forma que corresponda: ver `ContentTrashRepositoryImpl.restore`).
List<HighlightsCompanion> decodeTrashedHighlights(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  return [
    for (final raw in (jsonDecode(stored) as List).cast<Map<String, dynamic>>())
      HighlightsCompanion.insert(
        id: raw['id'] as String,
        renditionId: '',
        startOffset: raw['start'] as int,
        endOffset: raw['end'] as int,
        excerpt: raw['excerpt'] as String,
        note: Value(raw['note'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(raw['createdAt'] as int),
        color: Value(switch (raw['color']) {
          final String name => HighlightColor.values.byName(name),
          _ => null,
        }),
        style: Value(switch (raw['style']) {
          final String name => HighlightStyle.values.byName(name),
          _ => HighlightStyle.fill,
        }),
      ),
  ];
}

/// Lo resaltado para estudiar una forma de texto (F36) y hasta dónde se
/// analizó, para guardarlo en la papelera con ella: como los subrayados,
/// cuelga de la forma y al soltarla se iría en cascada. `null` si no había
/// nada.
String? encodeTrashedStudy(
  List<StudyMarkRow> marks,
  StudyAnalysisRow? analysis,
) {
  if (marks.isEmpty && analysis == null) return null;
  return jsonEncode({
    if (analysis != null)
      'analysis': {
        'until': analysis.analyzedUntil,
        if (analysis.completedAt case final completed?)
          'completedAt': completed.millisecondsSinceEpoch,
        'updatedAt': analysis.updatedAt.millisecondsSinceEpoch,
      },
    'marks': [
      for (final m in marks)
        {
          'id': m.id,
          'kind': m.kind.name,
          'origin': m.origin.name,
          'start': m.startOffset,
          'end': m.endOffset,
          'excerpt': m.excerpt,
          'createdAt': m.createdAt.millisecondsSinceEpoch,
        },
    ],
  });
}

/// Lo guardado por [encodeTrashedStudy], listo para volver a la base con la
/// forma [renditionId].
({List<StudyMarksCompanion> marks, StudyAnalysesCompanion? analysis})
decodeTrashedStudy(String? stored, {required String renditionId}) {
  if (stored == null || stored.isEmpty) {
    return (marks: const [], analysis: null);
  }
  final raw = jsonDecode(stored) as Map<String, dynamic>;
  final analysis = raw['analysis'] as Map<String, dynamic>?;
  DateTime at(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis! as int);
  return (
    marks: [
      for (final m in (raw['marks'] as List).cast<Map<String, dynamic>>())
        StudyMarksCompanion.insert(
          id: m['id'] as String,
          renditionId: renditionId,
          kind: StudyMarkKind.values.byName(m['kind'] as String),
          origin: ContentOrigin.values.byName(m['origin'] as String),
          startOffset: m['start'] as int,
          endOffset: m['end'] as int,
          excerpt: m['excerpt'] as String,
          createdAt: at(m['createdAt']),
        ),
    ],
    analysis: analysis == null
        ? null
        : StudyAnalysesCompanion.insert(
            renditionId: renditionId,
            analyzedUntil: analysis['until'] as int,
            completedAt: Value(
              analysis['completedAt'] == null
                  ? null
                  : at(analysis['completedAt']),
            ),
            updatedAt: at(analysis['updatedAt']),
          ),
  );
}

/// Las partes de los documentos procesados que anclaban una forma de texto
/// (F41), para devolverles el enlace al recuperarla: su id basta, porque
/// conservan su texto y sus posiciones. `null` si ninguna la anclaba.
String? encodeTrashedProcessedParts(List<String> partIds) =>
    partIds.isEmpty ? null : jsonEncode(partIds);

/// Lo guardado por [encodeTrashedProcessedParts].
List<String> decodeTrashedProcessedParts(String? stored) =>
    stored == null || stored.isEmpty
    ? const []
    : (jsonDecode(stored) as List).cast<String>();

/// Los hechos fechados que citaban una forma de texto (F40), para guardarlos
/// en la papelera con ella: en la base cuelgan de la forma, y al soltarla se
/// irían en cascada. `null` si no había ninguno.
String? encodeTrashedDatedEvents(List<DatedEventRow> events) {
  if (events.isEmpty) return null;
  return jsonEncode([
    for (final e in events)
      {
        'id': e.id,
        'title': e.title,
        'from': [e.dateFromYear, e.dateFromMonth, e.dateFromDay],
        'precision': e.datePrecision.name,
        'circa': e.dateIsCirca,
        if (e.dateEndYear != null)
          'to': [e.dateEndYear, e.dateEndMonth, e.dateEndDay],
        if (e.dateEndPrecision case final precision?)
          'toPrecision': precision.name,
        if (e.startOffset != null) 'start': e.startOffset,
        if (e.endOffset != null) 'end': e.endOffset,
        if (e.excerpt != null) 'excerpt': e.excerpt,
        'origin': e.origin.name,
        if (e.aiRunId != null) 'aiRunId': e.aiRunId,
        'createdAt': e.createdAt.millisecondsSinceEpoch,
        'updatedAt': e.updatedAt.millisecondsSinceEpoch,
      },
  ]);
}

/// Lo guardado por [encodeTrashedDatedEvents], listo para volver a la base con
/// la forma [renditionId] del elemento [itemId].
List<DatedEventsCompanion> decodeTrashedDatedEvents(
  String? stored, {
  required String itemId,
  required String renditionId,
}) {
  if (stored == null || stored.isEmpty) return const [];
  DateTime at(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis! as int);
  return [
    for (final raw in (jsonDecode(stored) as List).cast<Map<String, dynamic>>())
      () {
        final from = (raw['from'] as List).cast<int>();
        final to = (raw['to'] as List?)?.cast<int>();
        return DatedEventsCompanion.insert(
          id: raw['id'] as String,
          itemId: itemId,
          renditionId: Value(renditionId),
          title: raw['title'] as String,
          dateFromYear: from[0],
          dateFromMonth: from[1],
          dateFromDay: from[2],
          datePrecision: DatePrecision.values.byName(
            raw['precision'] as String,
          ),
          dateIsCirca: Value(raw['circa'] as bool),
          dateEndYear: Value(to?[0]),
          dateEndMonth: Value(to?[1]),
          dateEndDay: Value(to?[2]),
          dateEndPrecision: Value(switch (raw['toPrecision']) {
            final String name => DatePrecision.values.byName(name),
            _ => null,
          }),
          startOffset: Value(raw['start'] as int?),
          endOffset: Value(raw['end'] as int?),
          excerpt: Value(raw['excerpt'] as String?),
          origin: Value(ContentOrigin.values.byName(raw['origin'] as String)),
          aiRunId: Value(raw['aiRunId'] as String?),
          createdAt: at(raw['createdAt']),
          updatedAt: at(raw['updatedAt']),
        );
      }(),
  ];
}
