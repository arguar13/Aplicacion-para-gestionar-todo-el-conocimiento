import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/ai_rejection_memory.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/atlas_suggestions.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_field_ledger.dart';
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
        final tally =
            await _remainingOf(runId) +
            ((await _fields.remaining([runId]))[runId] ?? const AiRunTally());
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
                   ${_remainingSql('item_property_values', 'r.id')}
                     AS properties_left
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
            },
          )
          .get();

      // El tema y la referencia se cuentan aparte: lo que todavía es de la IA
      // se mira contra el valor de hoy, de a una página.
      final runIds = [for (final row in rows) row.read<String>('id')];
      final fieldsCreated = await _fields.created(runIds);
      final fieldsLeft = await _fields.remaining(runIds);

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
                (fieldsCreated[row.read<String>('id')] ?? const AiRunTally()),
            remaining:
                AiRunTally(
                  relations: row.read<int>('relations_left'),
                  flashcards: row.read<int>('flashcards_left'),
                  properties: row.read<int>('properties_left'),
                ) +
                (fieldsLeft[row.read<String>('id')] ?? const AiRunTally()),
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
               AND NOT EXISTS (
                 SELECT 1 FROM ai_runs later
                  WHERE later.item_id = r.item_id
                    AND later.started_at > r.started_at)''',
            variables: [for (final id in ids) Variable.withString(id)],
            readsFrom: {_db.aiRuns},
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
  Future<AiRunTally> _undo(AiRunRow run) async {
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
    final properties =
        await (_db.delete(_db.itemPropertyValues)..where(
              (p) =>
                  p.aiRunId.equals(run.id) &
                  p.origin.equalsValue(ItemPropertyOrigin.ai),
            ))
            .go();
    // Los temas que la IA ubicó sola en el árbol (F27, el Atlas) vuelven a la
    // raíz. No tienen `ai_run_id` propio —el lugar de un tema es una columna
    // del vocabulario—: la pasada queda en su registro de sugerencias.
    await undoAiTopicPlacements(_db, run.id);
    if (run.undoneAt == null) {
      await (_db.update(_db.aiRuns)..where((r) => r.id.equals(run.id))).write(
        AiRunsCompanion(undoneAt: Value(_clock())),
      );
    }
    return AiRunTally(
          relations: relations,
          flashcards: flashcards,
          properties: properties,
        ) +
        fields;
  }

  /// Lo que de [runId] sigue siendo de la IA, contado ahora.
  Future<AiRunTally> _remainingOf(String runId) async {
    final row = await _db
        .customSelect(
          'SELECT ${_remainingSql('relations', '?1')} AS relations_left, '
          '${_remainingSql('flashcards', '?1')} AS flashcards_left, '
          '${_remainingSql('item_property_values', '?1')} AS properties_left',
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
