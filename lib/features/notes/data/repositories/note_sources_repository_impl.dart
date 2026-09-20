import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';
import 'package:sinapsis/features/notes/domain/repositories/note_sources_repository.dart';

class NoteSourcesRepositoryImpl implements NoteSourcesRepository {
  const NoteSourcesRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Stream<List<CitedSource>> watchCitedSources(String noteId) {
    return watchQuery(
      db: _db,
      tables: [
        _db.relations,
        _db.knowledgeEntries,
        _db.knowledgeSources,
        _db.knowledgeNotes,
        _db.chunks,
      ],
      read: () => _read(noteId),
      telemetry: _telemetry,
      hint: 'NoteSourcesRepositoryImpl.watchCitedSources',
    );
  }

  Future<List<CitedSource>> _read(String noteId) async {
    // Lo que sale de la nota, salvo contradicciones y extracciones: una nota
    // viva no se extrae de nada, y contradecir no es citar.
    final outgoing =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.fromItemId.equals(noteId) &
                  r.kind.isNotIn([
                    RelationKind.contradicts.name,
                    RelationKind.extractedFrom.name,
                  ]),
            ))
            .get();
    if (outgoing.isEmpty) return const [];

    final targetIds = outgoing.map((r) => r.toItemId).toSet();
    final kindOf = await _entryKinds(targetIds);
    final atomicIds = await _atomicIds(
      targetIds.where((id) => kindOf[id] == ItemKind.note),
    );

    // Directo: `cites` hacia una fuente.
    final directIds = {
      for (final r in outgoing)
        if (r.kind == RelationKind.cites &&
            kindOf[r.toItemId] == ItemKind.source)
          r.toItemId,
    };

    // A través de las atómicas: de qué fuente salió cada una, y de dónde.
    final extractions = atomicIds.isEmpty
        ? const <RelationRow>[]
        : await (_db.select(_db.relations)..where(
                (r) =>
                    r.fromItemId.isIn(atomicIds) &
                    r.kind.equalsValue(RelationKind.extractedFrom),
              ))
              .get();

    final sourceIds = {...directIds, for (final e in extractions) e.toItemId};
    if (sourceIds.isEmpty) return const [];

    final titles = await _titles({
      ...sourceIds,
      for (final e in extractions) e.fromItemId,
    });
    final sourceKinds = await _sourceKinds(sourceIds);

    final fragmentsBySource = <String, List<CitedFragment>>{};
    for (final extraction in extractions) {
      final start = extraction.sourceCharStart;
      final position = start == null
          ? null
          : await _chunkAt(extraction.toItemId, start);
      (fragmentsBySource[extraction.toItemId] ??= []).add(
        CitedFragment(
          noteId: extraction.fromItemId,
          noteTitle: titles[extraction.fromItemId] ?? '',
          start: start,
          end: extraction.sourceCharEnd,
          startMs: position?.startMs,
          pageNumber: position?.pageNumber,
        ),
      );
    }

    final cited = [
      // Una fuente que ya no existe —se está borrando, y el vínculo todavía no
      // se fue— no se cita: sin ella no hay título ni tipo que mostrar.
      for (final sourceId in sourceIds.where(sourceKinds.containsKey))
        CitedSource(
          sourceId: sourceId,
          title: titles[sourceId] ?? '',
          sourceKind: sourceKinds[sourceId]!,
          isDirect: directIds.contains(sourceId),
          fragments: _ordered(fragmentsBySource[sourceId] ?? const []),
        ),
    ];
    // Sin distinguir mayúsculas ni acentos: "Árbol" va con la A, no después de
    // la Z.
    return cited..sort(
      (a, b) => normalizeVocabularyLabel(
        a.title,
      ).compareTo(normalizeVocabularyLabel(b.title)),
    );
  }

  /// Los fragmentos de una fuente en el orden en que están en el texto; los que
  /// no tienen posición, al final y por título.
  List<CitedFragment> _ordered(List<CitedFragment> fragments) {
    return [...fragments]..sort((a, b) {
      final aStart = a.start;
      final bStart = b.start;
      if (aStart != null && bStart != null) return aStart.compareTo(bStart);
      if (aStart != null) return -1;
      if (bStart != null) return 1;
      return a.noteTitle.compareTo(b.noteTitle);
    });
  }

  Future<Map<String, ItemKind>> _entryKinds(Set<String> ids) async {
    final rows = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row.kind};
  }

  /// De los ids que son notas, los que son atómicas.
  Future<Set<String>> _atomicIds(Iterable<String> noteIds) async {
    final ids = noteIds.toSet();
    if (ids.isEmpty) return const {};
    final rows =
        await (_db.select(_db.knowledgeNotes)..where(
              (n) =>
                  n.itemId.isIn(ids) & n.noteKind.equalsValue(NoteKind.atomic),
            ))
            .get();
    return {for (final row in rows) row.itemId};
  }

  Future<Map<String, String>> _titles(Set<String> ids) async {
    final rows = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row.title};
  }

  Future<Map<String, SourceKind>> _sourceKinds(Set<String> itemIds) async {
    final rows = await (_db.select(_db.knowledgeEntries).join([
      // Una nota no tiene fila de fuente: es una nota manual.
      leftOuterJoin(
        _db.knowledgeSources,
        _db.knowledgeSources.itemId.equalsExp(_db.knowledgeEntries.id),
      ),
    ])..where(_db.knowledgeEntries.id.isIn(itemIds))).get();
    return {
      for (final row in rows)
        row.readTable(_db.knowledgeEntries).id:
            row.readTableOrNull(_db.knowledgeSources)?.sourceType ??
            SourceKind.manualNote,
    };
  }

  /// El primer trozo de la fuente que cubre la posición [offset] —con el
  /// instante o la página en que empieza, si los tiene—. Los trozos se
  /// numeran sobre el texto de la fuente, así que esto es lo que dice "en el
  /// minuto 12" para un fragmento extraído de una transcripción.
  Future<ChunkRow?> _chunkAt(String sourceId, int offset) {
    return (_db.select(_db.chunks)
          ..where(
            (c) =>
                c.itemId.equals(sourceId) &
                c.charStart.isSmallerOrEqualValue(offset) &
                c.charEnd.isBiggerThanValue(offset),
          )
          ..orderBy([(c) => OrderingTerm(expression: c.seq)])
          ..limit(1))
        .getSingleOrNull();
  }
}
