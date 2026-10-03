import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/atlas_suggestions.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_field_ledger.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_atlas_repository.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';

class AiAtlasRepositoryImpl implements AiAtlasRepository {
  const AiAtlasRepositoryImpl({
    required AppDatabase database,
    required LibraryRepository library,
    required OrganizeRepository organize,
    required AiRunRepository runs,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _library = library,
       _organize = organize,
       _runs = runs,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final LibraryRepository _library;
  final OrganizeRepository _organize;
  final AiRunRepository _runs;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  static final _map = NoteKind.map.name;
  static final _blocks = RenditionKind.blocks.name;

  @override
  Future<Either<Failure, AtlasTopicTree>> topicTree() =>
      _guard('topicTree', () async {
        final temaId = await temaDefinitionId(_db);
        final rows = await (_db.select(
          _db.propertyValues,
        )..where((v) => v.definitionId.equals(temaId))).get();
        return AtlasTopicTree(
          definitionId: temaId,
          topics: [
            for (final row in rows)
              AtlasTopic(
                id: row.id,
                label: row.value,
                parentId: row.parentId,
                createdAt: row.createdAt,
              ),
          ],
        );
      });

  @override
  Future<Either<Failure, bool>> hasPlacementRecord(String valueId) => _guard(
    'hasPlacementRecord',
    () async => (await topicParentSuggestionsAbout(_db, valueId)).isNotEmpty,
  );

  @override
  Future<Either<Failure, bool>> applyTopicPlacement({
    required String itemId,
    required String runId,
    required String valueId,
    required String parentId,
  }) => _guard(
    'applyTopicPlacement',
    () => _db.transaction(() async {
      // Se mira adentro de la transacción: el modelo tardó, y la persona pudo
      // ubicar el tema, o colgarle uno, mientras tanto.
      final hasChildren =
          await (_db.select(_db.propertyValues)
                ..where((v) => v.parentId.equals(valueId))
                ..limit(1))
              .getSingleOrNull() !=
          null;
      if (hasChildren) return false;
      // `placeTopicValue` se niega —sin escribir nada— si el tema ya tiene
      // padre o si el lugar no es posible.
      final placed = await placeTopicValue(
        _db,
        valueId: valueId,
        parentId: parentId,
      );
      if (placed.isLeft()) return false;
      await _insertPlacement(
        itemId: itemId,
        valueId: valueId,
        parentId: parentId,
        status: SuggestionStatus.accepted,
        aiRunId: runId,
      );
      return true;
    }),
  );

  @override
  Future<Either<Failure, Unit>> proposeTopicPlacement({
    required String itemId,
    required String valueId,
    required String parentId,
  }) => _guard('proposeTopicPlacement', () async {
    await _insertPlacement(
      itemId: itemId,
      valueId: valueId,
      parentId: parentId,
      status: SuggestionStatus.pending,
    );
    return unit;
  });

  Future<void> _insertPlacement({
    required String itemId,
    required String valueId,
    required String parentId,
    required SuggestionStatus status,
    String? aiRunId,
  }) async {
    final rows = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.isIn([valueId, parentId]))).get();
    final byId = {for (final row in rows) row.id: row};
    final value = byId[valueId]!;
    await _db
        .into(_db.suggestions)
        .insert(
          SuggestionsCompanion.insert(
            id: _ids.next(),
            kind: SuggestionKind.topicParent,
            targetItemId: itemId,
            payloadJson: encodeTopicParentPayload(
              definitionId: value.definitionId,
              valueId: valueId,
              valueName: value.value,
              parentId: parentId,
              parentName: byId[parentId]!.value,
              aiRunId: aiRunId,
            ),
            status: Value(status),
            createdAt: _clock(),
          ),
        );
  }

  @override
  Future<Either<Failure, bool>> undoTopicPlacement(String suggestionId) async {
    try {
      return await _db.transaction(
        () => undoAiTopicPlacement(_db, suggestionId),
      );
      // Ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'undoTopicPlacement'));
    }
  }

  @override
  Future<Either<Failure, List<TopicMaterial>>> topicMaterial(
    Set<String> branchValueIds,
  ) => _guard('topicMaterial', () async {
    if (branchValueIds.isEmpty) return const <TopicMaterial>[];
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.title, i.updated_at, n.note_kind,
                 ipv.property_value_id AS value_id
            FROM item_property_values ipv
            JOIN item i ON i.id = ipv.item_id
            LEFT JOIN note n ON n.item_id = i.id
           WHERE ipv.property_value_id IN (${_marks(branchValueIds.length)})
             AND ${activeItemSql('i')}
             AND (n.note_kind IS NULL OR n.note_kind <> '$_map')''',
          variables: [for (final id in branchValueIds) Variable.withString(id)],
          readsFrom: {
            _db.itemPropertyValues,
            _db.knowledgeEntries,
            _db.knowledgeNotes,
          },
        )
        .get();

    final valuesByItem = <String, Set<String>>{};
    final first = <String, QueryRow>{};
    for (final row in rows) {
      final id = row.read<String>('id');
      (valuesByItem[id] ??= {}).add(row.read<String>('value_id'));
      first.putIfAbsent(id, () => row);
    }
    return [
      for (final MapEntry(key: id, value: row) in first.entries)
        TopicMaterial(
          itemId: id,
          title: row.read<String>('title'),
          updatedAt: row.read<DateTime>('updated_at'),
          valueIds: valuesByItem[id]!,
          noteKind: switch (row.readNullable<String>('note_kind')) {
            null => null,
            final kind => NoteKind.values.byName(kind),
          },
        ),
    ];
  });

  @override
  Future<Either<Failure, Map<String, String>>> excerptsOf(
    List<String> itemIds, {
    required int chars,
  }) => _guard('excerptsOf', () async {
    if (itemIds.isEmpty) return const <String, String>{};
    // La forma principal de cada uno, con texto. De una fuente, solo el
    // comienzo —puede ser un libro—; de una nota en bloques, entera: el JSON
    // cortado a mitad no se puede leer, y una nota es lo que alguien escribió.
    final rows = await _db
        .customSelect(
          '''
          SELECT r.item_id, r.kind,
                 CASE WHEN r.kind = '$_blocks' THEN r.content
                      ELSE substr(r.content, 1, ?) END AS head
            FROM renditions r
           WHERE r.item_id IN (${_marks(itemIds.length)})
             AND r.is_primary = 1 AND r.content IS NOT NULL''',
          variables: [
            Variable.withInt(chars * 3),
            for (final id in itemIds) Variable.withString(id),
          ],
          readsFrom: {_db.renditions},
        )
        .get();
    return {
      for (final row in rows)
        if (_plainText(row.read<String>('kind'), row.read<String>('head'))
            case final text when text.isNotEmpty)
          row.read<String>('item_id'): _cutWords(text, chars),
    };
  });

  @override
  Future<Either<Failure, List<TopicMapNote>>> mapNotesOf(String valueId) =>
      _guard('mapNotesOf', () => _mapNotes(valueId));

  Future<List<TopicMapNote>> _mapNotes(String valueId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.title, n.generated_by_model, n.derived_edited,
                 (SELECT r.undone_at FROM ai_runs r
                   WHERE r.item_id = i.id
                   ORDER BY r.started_at DESC, r.id DESC LIMIT 1) AS last_undone,
                 (SELECT rd.content FROM renditions rd
                   WHERE rd.item_id = i.id AND rd.kind = '$_blocks'
                   ORDER BY rd.is_primary DESC LIMIT 1) AS blocks
            FROM item_property_values ipv
            JOIN item i ON i.id = ipv.item_id
            JOIN note n ON n.item_id = i.id
           WHERE ipv.property_value_id = ?
             AND n.note_kind = '$_map'
             AND ${activeItemSql('i')}
           ORDER BY i.created_at, i.id''',
          variables: [Variable.withString(valueId)],
          readsFrom: {
            _db.itemPropertyValues,
            _db.knowledgeEntries,
            _db.knowledgeNotes,
            _db.aiRuns,
            _db.renditions,
          },
        )
        .get();
    return [
      for (final row in rows)
        TopicMapNote(
          itemId: row.read<String>('id'),
          title: row.read<String>('title'),
          byAi: row.readNullable<String>('generated_by_model') != null,
          edited: row.read<bool>('derived_edited'),
          aiLetGo: row.readNullable<DateTime>('last_undone') != null,
          blocksContent: row.readNullable<String>('blocks'),
        ),
    ];
  }

  @override
  Future<Either<Failure, bool>> mapNoteDeclined(String valueId) =>
      _guard('mapNoteDeclined', () async {
        final value = await (_db.select(
          _db.propertyValues,
        )..where((v) => v.id.equals(valueId))).getSingle();
        final temaId = await temaDefinitionId(_db);
        final temaName = (await (_db.select(
          _db.propertyDefinitions,
        )..where((d) => d.id.equals(temaId))).getSingle()).name;
        // Tres huellas de que la persona le sacó la nota mapa al tema. Las dos
        // primeras miran también lo que está en la papelera: borrar es la forma
        // más directa de decir que no. La segunda se lee del registro de la
        // pasada que creó la nota (`AiChangedField.mapNote`), no de su título:
        // el título sale en el idioma de la app, y la persona puede cambiarlo.
        final row = await _db
            .customSelect(
              '''
          SELECT
            EXISTS (
              SELECT 1 FROM item_property_values ipv
                JOIN note n ON n.item_id = ipv.item_id
                JOIN item i ON i.id = ipv.item_id
               WHERE ipv.property_value_id = ?1
                 AND n.note_kind = '$_map'
                 AND i.deleted_at IS NOT NULL) AS trashed,
            EXISTS (
              SELECT 1 FROM ai_field_changes c
                JOIN ai_runs r ON r.id = c.ai_run_id
               WHERE c.field = ?2 AND c.after_value = ?1
                 AND NOT EXISTS (
                   SELECT 1 FROM item_property_values ipv
                     JOIN item i ON i.id = ipv.item_id
                     JOIN note n ON n.item_id = i.id
                    WHERE ipv.item_id = r.item_id
                      AND ipv.property_value_id = ?1
                      AND n.note_kind = '$_map'
                      AND ${activeItemSql('i')})) AS let_go,
            EXISTS (
              SELECT 1 FROM ai_rejections r
                JOIN note n ON n.item_id = r.item_id
               WHERE r.kind = ?3 AND r.fingerprint = ?4
                 AND n.note_kind = '$_map'
                 AND n.generated_by_model IS NOT NULL) AS rejected''',
              variables: [
                Variable.withString(valueId),
                Variable.withString(AiChangedField.mapNote.name),
                Variable.withString(AiRejectionKind.property.name),
                Variable.withString(
                  propertyRejectionFingerprint(
                    definitionName: temaName,
                    value: value.value,
                  ),
                ),
              ],
              readsFrom: {
                _db.itemPropertyValues,
                _db.knowledgeNotes,
                _db.knowledgeEntries,
                _db.aiRejections,
                _db.aiFieldChanges,
                _db.aiRuns,
              },
            )
            .getSingle();
        return row.read<bool>('trashed') ||
            row.read<bool>('let_go') ||
            row.read<bool>('rejected');
      });

  @override
  Future<Either<Failure, String?>> createMapNote({
    required String valueId,
    required String title,
    required List<ContentBlock> blocks,
    required String model,
  }) => _guard(
    'createMapNote',
    () => _db.transaction(() async {
      if ((await _mapNotes(valueId)).isNotEmpty) return null;
      final value = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(valueId))).getSingle();

      final now = _clock();
      final noteId = _ids.next();
      final note = KnowledgeItem(
        id: noteId,
        title: title,
        source: Source(
          id: _ids.next(),
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: _ids.next(),
            itemId: noteId,
            kind: RenditionKind.blocks,
            content: encodeContentBlocks(blocks),
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );
      _orAbort(await _library.save(note));
      await _writer.setNoteKind(noteId, NoteKind.map);
      await _writer.markGenerated(noteId, model: model, at: now);

      // Su propia pasada: queda en «Lo que hizo la IA» como algo que la IA
      // hizo, con el modelo; deshacerla la manda a la papelera —si nadie la
      // editó— y la IA la suelta. Y es lo que le dice a la cola que esta nota
      // ya está organizada: un índice no se vincula ni se vuelve tarjetas.
      final runId = _orAbort(await _runs.startRun(noteId, model: model));
      _orAbort(
        await _organize.assignProperty(
          itemId: noteId,
          definitionId: value.definitionId,
          value: value.value,
          origin: ItemPropertyOrigin.ai,
          aiRunId: runId,
        ),
      );
      // Que la pasada creó la nota entera, y de qué tema es índice: antes de
      // cerrarla, para que lo cuente.
      await AiFieldLedger(
        _db,
        ids: _ids,
        clock: _clock,
      ).recordMapNote(runId: runId, valueId: valueId);
      _orAbort(await _runs.finishRun(runId));
      return noteId;
    }),
  );

  @override
  Future<Either<Failure, bool>> updateMapNote({
    required String noteId,
    required String? expectedContent,
    required List<ContentBlock> blocks,
  }) => _guard(
    'updateMapNote',
    () => _db.transaction(() async {
      // Lo que se leyó antes de pedirle al modelo la introducción tiene que
      // seguir igual: si la persona la abrió y la cambió mientras tanto, ya
      // es suya.
      final current = await _mapNotesById(noteId);
      if (current == null ||
          !current.keptByAi ||
          current.blocksContent != expectedContent) {
        return false;
      }
      final item = _orAbort(await _library.findById(noteId));
      if (item == null) return false;

      final now = _clock();
      final previous = item.renditions.whereType<TextRendition>().where(
        (r) => r.kind == RenditionKind.blocks,
      );
      final content = encodeContentBlocks(blocks);
      _orAbort(
        await _library.save(
          item.copyWith(
            updatedAt: now,
            renditions: [
              ...item.renditions.where(
                (r) => r.renditionKind != RenditionKind.blocks,
              ),
              Rendition.text(
                id: previous.isEmpty ? _ids.next() : previous.first.id,
                itemId: noteId,
                kind: RenditionKind.blocks,
                content: content,
                isPrimary: true,
                createdAt: previous.isEmpty ? now : previous.first.createdAt,
              ),
            ],
          ),
        ),
      );
      return true;
    }),
  );

  /// La nota mapa [noteId] como la ve la IA, sea del tema que sea.
  Future<TopicMapNote?> _mapNotesById(String noteId) async {
    final row = await _db
        .customSelect(
          '''
          SELECT i.title, n.generated_by_model, n.derived_edited,
                 (SELECT r.undone_at FROM ai_runs r
                   WHERE r.item_id = i.id
                   ORDER BY r.started_at DESC, r.id DESC LIMIT 1) AS last_undone,
                 (SELECT rd.content FROM renditions rd
                   WHERE rd.item_id = i.id AND rd.kind = '$_blocks'
                   ORDER BY rd.is_primary DESC LIMIT 1) AS blocks
            FROM note n
            JOIN item i ON i.id = n.item_id
           WHERE n.item_id = ? AND n.note_kind = '$_map'
             AND ${activeItemSql('i')}''',
          variables: [Variable.withString(noteId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return TopicMapNote(
      itemId: noteId,
      title: row.read<String>('title'),
      byAi: row.readNullable<String>('generated_by_model') != null,
      edited: row.read<bool>('derived_edited'),
      aiLetGo: row.readNullable<DateTime>('last_undone') != null,
      blocksContent: row.readNullable<String>('blocks'),
    );
  }

  @override
  Future<Either<Failure, NoteGrowth?>> noteGrowth(String itemId) =>
      _guard('noteGrowth', () async {
        final row = await _db
            .customSelect(
              '''
              SELECT n.note_kind, n.maturity, i.created_at,
                     (SELECT COUNT(*) FROM (
                        SELECT r.to_item_id AS other FROM relations r
                         WHERE r.from_item_id = ?1
                        UNION
                        SELECT r.from_item_id FROM relations r
                         WHERE r.to_item_id = ?1) x
                        JOIN item o ON o.id = x.other
                        LEFT JOIN note onote ON onote.item_id = o.id
                       WHERE ${activeItemSql('o')}
                         AND o.id <> ?1
                         AND (onote.note_kind IS NULL
                              OR onote.note_kind <> '$_map')) AS connections
                FROM note n
                JOIN item i ON i.id = n.item_id
               WHERE n.item_id = ?1 AND ${activeItemSql('i')}''',
              variables: [Variable.withString(itemId)],
              readsFrom: {
                _db.knowledgeNotes,
                _db.knowledgeEntries,
                _db.relations,
              },
            )
            .getSingleOrNull();
        if (row == null) return null;
        return NoteGrowth(
          noteKind: NoteKind.values.byName(row.read<String>('note_kind')),
          maturity: NoteMaturity.values.byName(row.read<String>('maturity')),
          createdAt: row.read<DateTime>('created_at'),
          connections: row.read<int>('connections'),
        );
      });

  @override
  Future<Either<Failure, Unit>> proposeMaturity({
    required String itemId,
    required NoteMaturity from,
    required NoteMaturity to,
  }) => _guard('proposeMaturity', () async {
    await _db
        .into(_db.suggestions)
        .insert(
          SuggestionsCompanion.insert(
            id: _ids.next(),
            kind: SuggestionKind.maturity,
            targetItemId: itemId,
            payloadJson: encodeMaturityPayload(from: from, to: to),
            createdAt: _clock(),
          ),
        );
    return unit;
  });

  /// [body] con sus fallos convertidos: lo que abortó una transacción con un
  /// fallo conocido se devuelve tal cual; lo inesperado se registra.
  Future<Either<Failure, T>> _guard<T>(
    String hint,
    Future<T> Function() body,
  ) async {
    try {
      return right(await body());
    } on _Abort catch (abort) {
      return left(abort.failure);
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, hint));
    }
  }

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y dejarlo escapar dejaría a la
  /// cola esperando una respuesta que no llega.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: 'AiAtlasRepositoryImpl.$hint');
    return Failure.unexpected(message: e.toString());
  }

  static String _marks(int count) => List.filled(count, '?').join(', ');
}

/// El valor de [result], o corta la transacción con su fallo: lo que ya se
/// escribió se deshace entero.
T _orAbort<T>(Either<Failure, T> result) =>
    result.match((failure) => throw _Abort(failure), (value) => value);

class _Abort implements Exception {
  const _Abort(this.failure);

  final Failure failure;
}

final _tags = RegExp('<[^>]*>');
final _spaces = RegExp(r'\s+');

/// El texto legible de una forma: los bloques de una nota se leen como
/// bloques, el HTML sin etiquetas, el resto tal cual.
String _plainText(String kind, String content) {
  final text = switch (kind) {
    'blocks' =>
      (tryDecodeContentBlocks(content) ?? const <ContentBlock>[])
          .map((block) => block.text)
          .join(' '),
    'html' => content.replaceAll(_tags, ' '),
    _ => content,
  };
  return text.replaceAll(_spaces, ' ').trim();
}

/// [text] hasta [max] caracteres, cortado en una palabra entera.
String _cutWords(String text, int max) {
  if (text.length <= max) return text;
  final head = text.substring(0, max);
  final space = head.lastIndexOf(' ');
  return '${head.substring(0, space > max ~/ 2 ? space : max).trim()}…';
}
