import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/ai_run_sql.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/atlas_suggestions.dart';
import 'package:sinapsis/core/database/correction_suggestions.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/reviewable_ai_thing.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_field_ledger.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';

class AiRunRepositoryImpl implements AiRunRepository {
  const AiRunRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  /// El tema y los datos de la referencia de cada pasada (v35).
  AiFieldLedger get _fields => AiFieldLedger(_db, ids: _ids, clock: _clock);

  @override
  Future<Either<Failure, String>> startRun(
    String itemId, {
    String? model,
    String? contentSimhash,
    AiRunScope scope = AiRunScope.organize,
  }) async {
    try {
      final id = _ids.next();
      await _db
          .into(_db.aiRuns)
          .insert(
            AiRunsCompanion.insert(
              id: id,
              itemId: itemId,
              model: Value(model),
              startedAt: _clock(),
              contentSimhash: Value(contentSimhash),
              scope: Value(scope),
            ),
          );
      return right(id);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.startRun'));
    }
  }

  @override
  Future<Either<Failure, bool>> applySpace({
    required String runId,
    required String itemId,
    required String spaceId,
  }) async {
    try {
      // Mirar si ya tiene tema y ponérselo, en la misma transacción: la
      // persona pudo elegirle uno mientras el modelo pensaba.
      return right(
        await _db.transaction(
          () => _fields.applySpace(
            runId: runId,
            itemId: itemId,
            spaceId: spaceId,
          ),
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.applySpace'));
    }
  }

  @override
  Future<Either<Failure, int>> completeReference({
    required String runId,
    required String itemId,
    required ExtractedMetadata extracted,
  }) async {
    try {
      return right(
        await _db.transaction(
          () => _fields.completeReference(
            runId: runId,
            itemId: itemId,
            extracted: extracted,
          ),
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'AiRunRepositoryImpl.completeReference'),
      );
    }
  }

  @override
  Future<Either<Failure, AiRunTally>> finishRun(String runId) async {
    try {
      return await _db.transaction(() async {
        final placements = (await aiTopicPlacementCounts(_db, [runId]))[runId];
        final corrections = (await aiCorrectionCounts(_db, [runId]))[runId];
        final tally =
            await _remainingOf(runId) +
            ((await _fields.remaining([runId]))[runId] ?? const AiRunTally()) +
            AiRunTally(
              topicPlacements: placements?.remaining ?? 0,
              corrections: corrections?.remaining ?? 0,
            );
        final updated =
            await (_db.update(
              _db.aiRuns,
            )..where((r) => r.id.equals(runId))).write(
              AiRunsCompanion(
                finishedAt: Value(_clock()),
                relationsCreated: Value(tally.relations),
                flashcardsCreated: Value(tally.flashcards),
                propertiesCreated: Value(tally.properties),
              ),
            );
        if (updated == 0) return left(_missingRun);
        return right(tally);
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.finishRun'));
    }
  }

  @override
  Future<Either<Failure, List<AiRun>>> listRuns({
    String? itemId,
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0 || offset < 0) {
      return left(
        const Failure.validation(
          message:
              'La página necesita un tamaño positivo y un inicio no '
              'negativo.',
        ),
      );
    }
    try {
      // Lo que queda de cada pasada se cuenta en la misma consulta, por el
      // índice de `ai_run_id` de cada tabla: una página de pasadas cuesta lo
      // que esa página, no lo que la bóveda.
      final rows = await _db
          .customSelect(
            '''
            SELECT r.id, r.item_id, r.model, r.started_at, r.finished_at,
                   r.undone_at, r.relations_created, r.flashcards_created,
                   r.properties_created, i.title AS item_title,
                   ${_remainingSql('relations', 'r.id')} AS relations_left,
                   ${_remainingSql('flashcards', 'r.id')} AS flashcards_left,
                   ${_propertiesRemainingSql('r.id')} AS properties_left
              FROM ai_runs r
              JOIN item i ON i.id = r.item_id
             WHERE ${activeItemSql('i')}
               ${itemId == null ? '' : 'AND r.item_id = ?'}
             ORDER BY r.started_at DESC, r.id DESC
             LIMIT ? OFFSET ?''',
            variables: [
              if (itemId != null) Variable.withString(itemId),
              Variable.withInt(limit),
              Variable.withInt(offset),
            ],
            readsFrom: {
              _db.aiRuns,
              _db.knowledgeEntries,
              _db.relations,
              _db.flashcards,
              _db.itemPropertyValues,
              _db.aiFieldChanges,
            },
          )
          .get();

      // El tema y la referencia se cuentan aparte: lo que todavía es de la IA
      // se mira contra el valor de hoy, de a una página. Los temas ubicados
      // en el árbol y las correcciones aceptadas de una revisión (F33), en su
      // registro de sugerencias.
      final runIds = [for (final row in rows) row.read<String>('id')];
      final fieldsCreated = await _fields.created(runIds);
      final fieldsLeft = await _fields.remaining(runIds);
      final placements = await aiTopicPlacementCounts(_db, runIds);
      final corrections = await aiCorrectionCounts(_db, runIds);

      return right([
        for (final row in rows)
          AiRun(
            id: row.read<String>('id'),
            itemId: row.read<String>('item_id'),
            itemTitle: row.read<String>('item_title'),
            model: row.readNullable<String>('model'),
            startedAt: row.read<DateTime>('started_at'),
            finishedAt: row.readNullable<DateTime>('finished_at'),
            undoneAt: row.readNullable<DateTime>('undone_at'),
            created:
                AiRunTally(
                  relations: row.read<int>('relations_created'),
                  flashcards: row.read<int>('flashcards_created'),
                  properties: row.read<int>('properties_created'),
                ) +
                (fieldsCreated[row.read<String>('id')] ?? const AiRunTally()) +
                AiRunTally(
                  topicPlacements:
                      placements[row.read<String>('id')]?.created ?? 0,
                  corrections:
                      corrections[row.read<String>('id')]?.created ?? 0,
                ),
            remaining:
                AiRunTally(
                  relations: row.read<int>('relations_left'),
                  flashcards: row.read<int>('flashcards_left'),
                  properties: row.read<int>('properties_left'),
                ) +
                (fieldsLeft[row.read<String>('id')] ?? const AiRunTally()) +
                AiRunTally(
                  topicPlacements:
                      placements[row.read<String>('id')]?.remaining ?? 0,
                  corrections:
                      corrections[row.read<String>('id')]?.remaining ?? 0,
                ),
          ),
      ]);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.listRuns'));
    }
  }

  @override
  Future<Either<Failure, AiRunTally>> undoRun(String runId) async {
    try {
      return await _db.transaction(() async {
        final run = await (_db.select(
          _db.aiRuns,
        )..where((r) => r.id.equals(runId))).getSingleOrNull();
        if (run == null) return left(_missingRun);
        return right(await _undo(run));
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.undoRun'));
    }
  }

  @override
  Future<Either<Failure, AiRunTally>> undoItem(String itemId) async {
    try {
      return await _db.transaction(() async {
        final runs = await (_db.select(
          _db.aiRuns,
        )..where((r) => r.itemId.equals(itemId) & r.undoneAt.isNull())).get();
        var total = const AiRunTally();
        for (final run in runs) {
          total += await _undo(run);
        }
        return right(total);
      });
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'AiRunRepositoryImpl.undoItem'));
    }
  }

  @override
  Future<Either<Failure, Set<String>>> undoneItemsAmong(
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet();
    if (ids.isEmpty) return right(const {});
    try {
      // La última pasada de cada uno, por el índice de `item_id`: unas pocas
      // filas por elemento, nunca la tabla entera.
      final rows = await _db
          .customSelect(
            '''
            SELECT r.item_id
              FROM ai_runs r
             WHERE r.item_id IN (${List.filled(ids.length, '?').join(', ')})
               AND r.undone_at IS NOT NULL
               AND ${organizeRunSql('r')}
               AND NOT EXISTS (
                 SELECT 1 FROM ai_runs later
                  WHERE later.item_id = r.item_id
                    AND later.started_at > r.started_at
                    AND ${organizeRunSql('later')})''',
            variables: [for (final id in ids) Variable.withString(id)],
            readsFrom: {_db.aiRuns, _db.aiFieldChanges},
          )
          .get();
      return right({for (final row in rows) row.read<String>('item_id')});
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'AiRunRepositoryImpl.undoneItemsAmong'),
      );
    }
  }

  /// Las tarjetas que la revisión mira (F33): de pregunta y respuesta, de la
  /// IA, de una pasada en pie y en un elemento fuera de la papelera. `f` es la
  /// tarjeta, `r` su pasada e `i` su elemento.
  static final _reviewableCardsSql =
      '''
      FROM flashcards f
      JOIN ai_runs r ON r.id = f.ai_run_id
      JOIN item i ON i.id = f.item_id
     WHERE f.origin = '${ContentOrigin.ai.name}'
       AND f.kind = '${FlashcardKind.freeRecall.name}'
       AND r.undone_at IS NULL
       AND ${activeItemSql('i')}''';

  /// Lo que la revisión mira (F33), una fila por cosa: el elemento, el modelo
  /// de la pasada que la hizo y si es una tarjeta. Las mismas reglas que
  /// `reviewableAiThings` —lo que se le da al revisor—, en SQL para contar
  /// toda la biblioteca de una vez:
  ///
  /// - las tarjetas de [_reviewableCardsSql];
  /// - los vínculos de la IA que no son estructura;
  /// - las etiquetas y propiedades de la IA, menos las de una nota mapa;
  /// - el tema y los datos de texto de la referencia que siguen con lo que
  ///   puso la pasada;
  /// - la introducción de una nota mapa que sigue siendo de la IA.
  ///
  /// Siempre de pasadas en pie, sobre elementos fuera de la papelera.
  static final _reviewableThingsCte =
      '''
      WITH things(item_id, model, is_card) AS (
        SELECT f.item_id, r.model, 1
          $_reviewableCardsSql
        UNION ALL
        SELECT r.item_id, r.model, 0
          FROM relations x
          JOIN ai_runs r ON r.id = x.ai_run_id
          JOIN item i ON i.id = r.item_id
         WHERE x.origin = '${ContentOrigin.ai.name}'
           AND x.kind NOT IN (${_structuralKindsSql()})
           AND r.undone_at IS NULL
           AND ${activeItemSql('i')}
        UNION ALL
        SELECT r.item_id, r.model, 0
          FROM item_property_values p
          JOIN ai_runs r ON r.id = p.ai_run_id
          JOIN item i ON i.id = p.item_id
         WHERE p.origin = '${ItemPropertyOrigin.ai.name}'
           AND r.item_id = p.item_id
           AND r.undone_at IS NULL
           AND ${activeItemSql('i')}
           AND NOT EXISTS (
             SELECT 1 FROM ai_field_changes m
              WHERE m.ai_run_id = r.id
                AND m.field = '${AiChangedField.mapNote.name}')
        UNION ALL
        SELECT r.item_id, r.model, 0
          FROM ai_field_changes c
          JOIN ai_runs r ON r.id = c.ai_run_id
          JOIN item i ON i.id = r.item_id
          LEFT JOIN source_reference sr ON sr.item_id = r.item_id
         WHERE r.undone_at IS NULL
           AND ${activeItemSql('i')}
           AND (${_stillFilledSql()})
        UNION ALL
        SELECT i.id, r.model, 0
          FROM note n
          JOIN item i ON i.id = n.item_id
          JOIN ai_runs r ON r.id = (
                 SELECT o.id FROM ai_runs o
                  WHERE o.item_id = i.id AND ${organizeRunSql('o')}
                  ORDER BY o.started_at DESC, o.id DESC
                  LIMIT 1)
         WHERE n.note_kind = '${NoteKind.map.name}'
           AND n.generated_by_model IS NOT NULL
           AND n.derived_edited = 0
           AND r.undone_at IS NULL
           AND ${activeItemSql('i')}
           AND json_extract((
                 SELECT rd.content FROM renditions rd
                  WHERE rd.item_id = i.id
                    AND rd.kind = '${RenditionKind.blocks.name}'
                  ORDER BY rd.is_primary DESC
                  LIMIT 1), '\$[0].type') = 'paragraph'
           AND json_extract((
                 SELECT rd.content FROM renditions rd
                  WHERE rd.item_id = i.id
                    AND rd.kind = '${RenditionKind.blocks.name}'
                  ORDER BY rd.is_primary DESC
                  LIMIT 1), '\$[1].type') = 'heading'
      )''';

  /// Los tipos de vínculo que son estructura, para un `NOT IN`.
  static String _structuralKindsSql() => [
    for (final kind in RelationKind.values)
      if (kind.isStructural) "'${kind.name}'",
  ].join(', ');

  /// Si el registro `c` de `ai_field_changes` sigue con lo que puso su
  /// pasada: el elemento `i` sigue en el tema que le puso (F37: puede tener
  /// otros), o el dato de texto de la referencia `sr` sigue igual.
  static String _stillFilledSql() => [
    """
(c.field = '${AiChangedField.space.name}' AND EXISTS (
   SELECT 1 FROM item_spaces s
    WHERE s.item_id = i.id AND s.space_id = c.after_value))""",
    for (final MapEntry(key: field, value: column) in _referenceColumns.entries)
      "(c.field = '${field.name}' AND sr.$column = c.after_value)",
  ].join('\n OR ');

  /// La columna de `source_reference` de cada dato de texto de la referencia
  /// (`AiChangedField.isReferenceText`).
  static const _referenceColumns = {
    AiChangedField.containerTitle: 'container_title',
    AiChangedField.publisher: 'publisher',
    AiChangedField.publisherPlace: 'publisher_place',
    AiChangedField.edition: 'edition',
    AiChangedField.volume: 'volume',
    AiChangedField.issue: 'issue',
    AiChangedField.pages: 'pages',
    AiChangedField.isbn: 'isbn',
    AiChangedField.issn: 'issn',
    AiChangedField.doi: 'doi',
  };

  /// Lo que un revisor todavía no revisó, sobre la fila `t` de
  /// [_reviewableThingsCte]: ni lo que hizo él mismo, ni los elementos con
  /// una pasada de revisión suya terminada y en pie. Lleva el nombre del
  /// revisor dos veces.
  static final _notReviewedBySql =
      '''
       AND (t.model IS NULL OR t.model <> ?)
       AND NOT EXISTS (
         SELECT 1 FROM ai_runs v
          WHERE v.item_id = t.item_id
            AND v.scope = '${AiRunScope.review.name}'
            AND v.model = ?
            AND v.finished_at IS NOT NULL
            AND v.undone_at IS NULL)''';

  /// Lo que leen [aiWorkByModel] y [reviewCandidates].
  Set<ResultSetImplementation<dynamic, dynamic>> get _reviewTables => {
    _db.itemSpaces,
    _db.flashcards,
    _db.relations,
    _db.itemPropertyValues,
    _db.aiFieldChanges,
    _db.sourceReferences,
    _db.knowledgeNotes,
    _db.renditions,
    _db.aiRuns,
    _db.knowledgeEntries,
  };

  @override
  Future<Either<Failure, List<ReviewableAiThing>>> reviewableThings(
    String itemId,
  ) async {
    try {
      return right(await reviewableAiThings(_db, itemId));
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'AiRunRepositoryImpl.reviewableThings'),
      );
    }
  }

  @override
  Future<Either<Failure, List<AiModelWork>>> aiWorkByModel({
    String? reviewer,
  }) async {
    try {
      final rows = await _db
          .customSelect(
            '''
            $_reviewableThingsCte
            SELECT t.model, COUNT(*) AS things,
                   COUNT(DISTINCT t.item_id) AS items
              FROM things t
             WHERE 1 = 1
              ${reviewer == null ? '' : _notReviewedBySql}
             GROUP BY t.model
             ORDER BY things DESC, t.model''',
            variables: [
              if (reviewer != null) ...[
                Variable.withString(reviewer),
                Variable.withString(reviewer),
              ],
            ],
            readsFrom: _reviewTables,
          )
          .get();
      return right([
        for (final row in rows)
          AiModelWork(
            model: row.readNullable<String>('model'),
            things: row.read<int>('things'),
            items: row.read<int>('items'),
          ),
      ]);
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'AiRunRepositoryImpl.aiWorkByModel'),
      );
    }
  }

  @override
  Future<Either<Failure, List<AiReviewCandidate>>> reviewCandidates({
    required String reviewer,
    String? madeBy,
    String? itemId,
  }) async {
    try {
      final rows = await _db
          .customSelect(
            '''
            $_reviewableThingsCte
            SELECT t.item_id, SUM(t.is_card) AS cards,
                   SUM(1 - t.is_card) AS others
              FROM things t
             WHERE 1 = 1
               ${itemId != null ? 'AND t.item_id = ?' : _notReviewedBySql}
               ${madeBy == null ? '' : 'AND t.model = ?'}
             GROUP BY t.item_id
             ORDER BY COUNT(*) DESC, t.item_id''',
            variables: [
              if (itemId != null)
                Variable.withString(itemId)
              else ...[
                Variable.withString(reviewer),
                Variable.withString(reviewer),
              ],
              if (madeBy != null) Variable.withString(madeBy),
            ],
            readsFrom: _reviewTables,
          )
          .get();
      return right([
        for (final row in rows)
          AiReviewCandidate(
            itemId: row.read<String>('item_id'),
            cards: row.read<int>('cards'),
            others: row.read<int>('others'),
          ),
      ]);
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'AiRunRepositoryImpl.reviewCandidates'),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> isRelationRejected({
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
  }) {
    final key = relationRejectionKey(
      fromItemId: fromItemId,
      toItemId: toItemId,
      kind: kind,
    );
    return _isRejected(
      AiRejectionKind.relation,
      key.itemId,
      key.fingerprint,
      'AiRunRepositoryImpl.isRelationRejected',
    );
  }

  @override
  Future<Either<Failure, bool>> isPropertyRejected({
    required String itemId,
    required String definitionName,
    required String value,
  }) => _isRejected(
    AiRejectionKind.property,
    itemId,
    propertyRejectionFingerprint(definitionName: definitionName, value: value),
    'AiRunRepositoryImpl.isPropertyRejected',
  );

  @override
  Future<Either<Failure, bool>> isFlashcardRejected({
    required String itemId,
    required String question,
  }) => _isRejected(
    AiRejectionKind.flashcard,
    itemId,
    flashcardRejectionFingerprint(question),
    'AiRunRepositoryImpl.isFlashcardRejected',
  );

  Future<Either<Failure, bool>> _isRejected(
    AiRejectionKind kind,
    String itemId,
    String fingerprint,
    String hint,
  ) async {
    try {
      return right(
        await isAiRejected(
          _db,
          kind: kind,
          itemId: itemId,
          fingerprint: fingerprint,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, hint));
    }
  }

  /// Borra lo que de [run] sigue siendo de la IA, devuelve el tema y la
  /// referencia a como estaban y la marca deshecha. Corre dentro de la
  /// transacción de quien llama: o se va todo, o nada.
  ///
  /// Las opciones y los repasos de una tarjeta se van con ella en cascada. El
  /// tema y la referencia, solo la primera vez: una pasada ya deshecha no
  /// tiene nada suyo, y si hoy el elemento tiene el mismo valor es porque
  /// alguien lo volvió a poner.
  ///
  /// Una pasada que creó una nota mapa (el Atlas) la manda a la papelera con
  /// lo que le puso —su tema—, y se cuenta como una nota mapa. Si la persona
  /// la editó, la nota es suya entera: deshacer no la toca, ni le saca el
  /// tema.
  Future<AiRunTally> _undo(AiRunRow run) async {
    final mapNote = await _fields.createdMapNote(run.id);
    final fields = run.undoneAt == null
        ? await _fields.undo(run.id)
        : const AiRunTally();
    final relations =
        await (_db.delete(_db.relations)..where(
              (r) =>
                  r.aiRunId.equals(run.id) &
                  r.origin.equalsValue(ContentOrigin.ai),
            ))
            .go();
    final flashcards =
        await (_db.delete(_db.flashcards)..where(
              (f) =>
                  f.aiRunId.equals(run.id) &
                  f.origin.equalsValue(ContentOrigin.ai),
            ))
            .go();
    final properties = mapNote?.adopted ?? false
        ? 0
        : await (_db.delete(_db.itemPropertyValues)..where(
                (p) =>
                    p.aiRunId.equals(run.id) &
                    p.origin.equalsValue(ItemPropertyOrigin.ai),
              ))
              .go();
    // Los temas que la IA ubicó sola en el árbol (F27, el Atlas) vuelven a la
    // raíz. No tienen `ai_run_id` propio —el lugar de un tema es una columna
    // del vocabulario—: la pasada queda en su registro de sugerencias.
    final topicPlacements = await undoAiTopicPlacements(_db, run.id);
    // Lo que una revisión corrigió (F33) vuelve a como estaba: la corrección
    // no es una fila con `ai_run_id`, sino un cambio sobre lo que ya había.
    final corrections = await undoAiCorrections(_db, run.id, now: _clock());
    if (run.undoneAt == null) {
      await (_db.update(_db.aiRuns)..where((r) => r.id.equals(run.id))).write(
        AiRunsCompanion(undoneAt: Value(_clock())),
      );
    }
    return AiRunTally(
          relations: relations,
          flashcards: flashcards,
          // El tema de una nota mapa va con ella: ya cuenta en `fields`.
          properties: mapNote == null ? properties : 0,
          topicPlacements: topicPlacements,
          corrections: corrections,
        ) +
        fields;
  }

  /// Lo que de [runId] sigue siendo de la IA, contado ahora.
  Future<AiRunTally> _remainingOf(String runId) async {
    final row = await _db
        .customSelect(
          'SELECT ${_remainingSql('relations', '?1')} AS relations_left, '
          '${_remainingSql('flashcards', '?1')} AS flashcards_left, '
          '${_propertiesRemainingSql('?1')} AS properties_left',
          variables: [Variable.withString(runId)],
        )
        .getSingle();
    return AiRunTally(
      relations: row.read<int>('relations_left'),
      flashcards: row.read<int>('flashcards_left'),
      properties: row.read<int>('properties_left'),
    );
  }

  /// Cuántas filas de [table] siguen siendo de la IA en la pasada [run] (una
  /// expresión SQL). Las tres tablas guardan el origen de la IA como `ai`.
  static String _remainingSql(String table, String run) =>
      '(SELECT COUNT(*) FROM $table x '
      "WHERE x.ai_run_id = $run AND x.origin = 'ai')";

  /// Lo mismo para las propiedades, sin las de una pasada que creó una nota
  /// mapa: lo que le puso —su tema— es parte de la nota, que se cuenta
  /// entera como nota mapa (`AiFieldLedger`). Si la persona la editó, la
  /// nota es suya, y su tema también.
  static String _propertiesRemainingSql(String run) =>
      '(SELECT COUNT(*) FROM item_property_values x '
      "WHERE x.ai_run_id = $run AND x.origin = 'ai' "
      'AND NOT EXISTS (SELECT 1 FROM ai_field_changes c '
      'WHERE c.ai_run_id = $run '
      "AND c.field = '${AiChangedField.mapNote.name}'))";

  static const _missingRun = Failure.unexpected(
    message:
        'Esa pasada de la IA ya no existe; puede que se haya borrado su '
        'elemento.',
  );

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atrapar solo `Exception` lo
  /// dejaría escapar dejando a quien llamó esperando una respuesta que
  /// nunca llega.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
