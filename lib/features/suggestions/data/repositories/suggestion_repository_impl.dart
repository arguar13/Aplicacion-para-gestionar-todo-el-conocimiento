import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/atlas_suggestions.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/habit_event_recorder.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/reference_completion.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/duplicates/domain/usecases/merge_duplicate_items_usecase.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/entities/pending_review_item.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

class SuggestionRepositoryImpl implements SuggestionRepository {
  const SuggestionRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required OrganizeRepository organize,

    /// `null` para quien nunca llama a [accept] sobre una sugerencia de
    /// duplicado —hoy, la instancia dedicada de
    /// `duplicateSuggestionGeneratorProvider`, que solo crea y lee
    /// sugerencias, nunca las acepta—. Necesario para cortar un ciclo
    /// real de providers: la vía normal de esta clase depende de
    /// `MergeDuplicateItemsUseCase`, que depende de `LibraryRepository`,
    /// que a su vez dispara el generador de duplicados al guardar una
    /// nota (D7) — si el generador reusara la sugerencia de
    /// `SuggestionRepository` de siempre, el ciclo se cerraría.
    required MergeDuplicateItemsUseCase? merge,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _organize = organize,
       _merge = merge,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final OrganizeRepository _organize;
  final MergeDuplicateItemsUseCase? _merge;
  final IdGenerator _ids;
  final Clock _clock;

  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  HabitEventRecorder get _habits => HabitEventRecorder(
    database: _db,
    telemetry: _telemetry,
    ids: _ids,
    clock: _clock,
  );

  @override
  Stream<List<Suggestion>> watchPendingSuggestions(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: () async {
        final rows =
            await (_db.select(_db.suggestions)
                  ..where(
                    (s) =>
                        s.targetItemId.equals(itemId) &
                        s.status.equalsValue(SuggestionStatus.pending),
                  )
                  ..orderBy([(s) => OrderingTerm(expression: s.createdAt)]))
                .get();
        return _aboutLiveItems(rows.map(_toSuggestion));
      },
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingSuggestions',
    );
  }

  @override
  Future<Either<Failure, List<Suggestion>>> suggestionsFor(
    String itemId,
  ) async {
    try {
      final rows =
          await (_db.select(_db.suggestions)
                ..where((s) => s.targetItemId.equals(itemId))
                ..orderBy([(s) => OrderingTerm(expression: s.createdAt)]))
              .get();
      return right(rows.map(_toSuggestion).toList());
      // `Object` y no `Exception`: ver `_unexpected`.
    } on Object catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.suggestionsFor'),
      );
    }
  }

  @override
  Stream<List<Suggestion>> watchPendingDuplicateSuggestions() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: () async {
        final rows =
            await (_db.select(_db.suggestions)
                  ..where(
                    (s) =>
                        s.kind.equalsValue(SuggestionKind.duplicate) &
                        s.status.equalsValue(SuggestionStatus.pending),
                  )
                  ..orderBy([(s) => OrderingTerm(expression: s.createdAt)]))
                .get();
        return _aboutLiveItems(rows.map(_toSuggestion));
      },
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingDuplicateSuggestions',
    );
  }

  /// Lo que se revisa en «Para revisar» (F27). Ni los duplicados —tienen su
  /// pantalla— ni las tarjetas, que nunca pasan por la cola de sugerencias.
  /// Del Atlas, el lugar de un tema en el árbol y la madurez de una nota.
  static const _reviewable = [
    SuggestionKind.relation,
    SuggestionKind.property,
    SuggestionKind.metadata,
    SuggestionKind.topicParent,
    SuggestionKind.maturity,
  ];

  /// Lo que cuenta como «para revisar», igual para la lista y para el número:
  /// pendiente, de un tipo que se revisa, de un elemento vivo y —si es un
  /// vínculo— hacia otro que tampoco está en la papelera. El otro extremo
  /// vive dentro del JSON; el conjunto de la papelera es chico y se arma una
  /// vez por consulta, como en `kChunkOutsideTrashSql`.
  ///
  /// En SQL y no con [_aboutLiveItems], como el resto de las lecturas: acá se
  /// mira la bóveda entera, y decodificar cada carga útil para descartarla
  /// después sería traer todo para mostrar un número.
  static final _reviewWhere =
      '''
      s.status = ?
      AND s.kind IN (${_reviewable.map((_) => '?').join(', ')})
      AND $kActiveItemSql
      AND (s.kind <> ? OR json_extract(s.payload_json, '\$.relatedItemId')
           NOT IN (SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL))''';

  static final List<Variable<Object>> _reviewVariables = [
    Variable.withString(SuggestionStatus.pending.name),
    for (final kind in _reviewable) Variable.withString(kind.name),
    Variable.withString(SuggestionKind.relation.name),
  ];

  @override
  Stream<List<PendingReviewItem>> watchItemsWithPendingReview() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: _readItemsWithPendingReview,
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchItemsWithPendingReview',
    );
  }

  @override
  Stream<int> watchPendingReviewCount() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions, _db.knowledgeEntries],
      read: () async {
        final row = await _db
            .customSelect(
              '''
              SELECT COUNT(*) AS pending
                FROM suggestions s
                JOIN item ON item.id = s.target_item_id
               WHERE $_reviewWhere''',
              variables: _reviewVariables,
              readsFrom: {_db.suggestions, _db.knowledgeEntries},
            )
            .getSingle();
        return row.read<int>('pending');
      },
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingReviewCount',
    );
  }

  Future<List<PendingReviewItem>> _readItemsWithPendingReview() async {
    // Solo los ids y el elemento: la carga útil entera se decodifica en
    // `watchPendingSuggestions`, y solo para lo que está en pantalla.
    final rows = await _db
        .customSelect(
          '''
          SELECT s.id, s.target_item_id, s.created_at,
                 item.title AS item_title
            FROM suggestions s
            JOIN item ON item.id = s.target_item_id
           WHERE $_reviewWhere
           ORDER BY s.created_at, s.id''',
          variables: _reviewVariables,
          readsFrom: {_db.suggestions, _db.knowledgeEntries},
        )
        .get();

    final byItem = <String, _ReviewGroup>{};
    for (final row in rows) {
      final group = byItem.putIfAbsent(
        row.read<String>('target_item_id'),
        () => _ReviewGroup(row.read<String>('item_title')),
      );
      group.ids.add(row.read<String>('id'));
      // Las filas llegan de la más vieja a la más nueva: la última gana.
      group.latestAt = row.read<DateTime>('created_at');
    }

    // El de la sugerencia más nueva primero; a igual momento, por título, para
    // que la lista no baile entre una lectura y la siguiente.
    return [
      for (final MapEntry(key: itemId, value: group) in byItem.entries)
        PendingReviewItem(
          itemId: itemId,
          itemTitle: group.title,
          suggestionIds: List.unmodifiable(group.ids),
          latestAt: group.latestAt!,
        ),
    ]..sort((a, b) {
      final byDate = b.latestAt.compareTo(a.latestAt);
      return byDate != 0 ? byDate : a.itemTitle.compareTo(b.itemTitle);
    });
  }

  @override
  Future<Either<Failure, Suggestion>> createPropertySuggestion({
    required String targetItemId,
    required String definitionId,
    required String definitionName,
    required String value,
    required bool isNewValue,
  }) async {
    try {
      final id = _ids.next();
      final createdAt = _clock();
      final payload = jsonEncode({
        'definitionId': definitionId,
        'definitionName': definitionName,
        'value': value,
        'isNewValue': isNewValue,
      });

      await _db
          .into(_db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: id,
              kind: SuggestionKind.property,
              targetItemId: targetItemId,
              payloadJson: payload,
              createdAt: createdAt,
            ),
          );

      return right(
        Suggestion.property(
          id: id,
          targetItemId: targetItemId,
          definitionId: definitionId,
          definitionName: definitionName,
          value: value,
          isNewValue: isNewValue,
          status: SuggestionStatus.pending,
          createdAt: createdAt,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'SuggestionRepositoryImpl.createPropertySuggestion',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Suggestion>> createRelationSuggestion({
    required String targetItemId,
    required String relatedItemId,
    required String relatedItemTitle,
    required RelationKind kind,
    required String reason,
    double? confidence,
  }) async {
    try {
      final id = _ids.next();
      final createdAt = _clock();
      final payload = jsonEncode({
        'relatedItemId': relatedItemId,
        'relatedItemTitle': relatedItemTitle,
        'relationKind': kind.name,
        'reason': reason,
      });

      await _db
          .into(_db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: id,
              kind: SuggestionKind.relation,
              targetItemId: targetItemId,
              payloadJson: payload,
              confidence: Value(confidence),
              createdAt: createdAt,
            ),
          );

      return right(
        Suggestion.relation(
          id: id,
          targetItemId: targetItemId,
          relatedItemId: relatedItemId,
          relatedItemTitle: relatedItemTitle,
          kind: kind,
          reason: reason,
          status: SuggestionStatus.pending,
          createdAt: createdAt,
          confidence: confidence,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'SuggestionRepositoryImpl.createRelationSuggestion',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Suggestion>> createDuplicateSuggestion({
    required String targetItemId,
    required String duplicateItemId,
    required String duplicateItemTitle,
    required DuplicateMatchKind matchKind,
    double? confidence,
  }) async {
    try {
      final id = _ids.next();
      final createdAt = _clock();
      final payload = jsonEncode({
        'duplicateItemId': duplicateItemId,
        'duplicateItemTitle': duplicateItemTitle,
        'matchKind': matchKind.name,
      });

      await _db
          .into(_db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: id,
              kind: SuggestionKind.duplicate,
              targetItemId: targetItemId,
              payloadJson: payload,
              confidence: Value(confidence),
              createdAt: createdAt,
            ),
          );

      return right(
        Suggestion.duplicate(
          id: id,
          targetItemId: targetItemId,
          duplicateItemId: duplicateItemId,
          duplicateItemTitle: duplicateItemTitle,
          matchKind: matchKind,
          status: SuggestionStatus.pending,
          createdAt: createdAt,
          confidence: confidence,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'SuggestionRepositoryImpl.createDuplicateSuggestion',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Suggestion>> createMetadataSuggestion({
    required String targetItemId,
    required ExtractedMetadata extracted,
  }) async {
    try {
      // Una sola por fuente: la que hubiera pendiente se reemplaza, no se
      // suma. `reject` alcanza porque nadie más lee una sugerencia por su
      // estado además de `pending`.
      await (_db.update(_db.suggestions)..where(
            (s) =>
                s.targetItemId.equals(targetItemId) &
                s.kind.equalsValue(SuggestionKind.metadata) &
                s.status.equalsValue(SuggestionStatus.pending),
          ))
          .write(
            const SuggestionsCompanion(
              status: Value(SuggestionStatus.rejected),
            ),
          );

      final id = _ids.next();
      final createdAt = _clock();
      final payload = jsonEncode(_metadataPayloadOf(extracted));

      await _db
          .into(_db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: id,
              kind: SuggestionKind.metadata,
              targetItemId: targetItemId,
              payloadJson: payload,
              createdAt: createdAt,
            ),
          );

      return right(
        Suggestion.metadata(
          id: id,
          targetItemId: targetItemId,
          extracted: extracted,
          status: SuggestionStatus.pending,
          createdAt: createdAt,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'SuggestionRepositoryImpl.createMetadataSuggestion',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> accept(String id) async {
    try {
      final row = await (_db.select(
        _db.suggestions,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'La sugerencia ya no existe; puede que se haya borrado.',
          ),
        );
      }

      final applied = switch (row.kind) {
        SuggestionKind.property => await _applyProperty(row),
        SuggestionKind.relation => await _applyRelation(row),
        SuggestionKind.duplicate => await _applyDuplicate(row),
        SuggestionKind.metadata => await _applyMetadata(row),
        SuggestionKind.topicParent => await _applyTopicParent(row),
        SuggestionKind.maturity => await _applyMaturity(row),
        SuggestionKind.flashcard => throw StateError(
          'SuggestionKind.${row.kind.name} todavía no tiene generador; no '
          'debería existir ninguna fila con este kind.',
        ),
      };
      final failure = applied.getLeft().toNullable();
      if (failure != null) return left(failure);

      await (_db.update(_db.suggestions)..where((s) => s.id.equals(id))).write(
        const SuggestionsCompanion(status: Value(SuggestionStatus.accepted)),
      );
      await _habits.record(HabitEventKind.triage);

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.accept'),
      );
    }
  }

  Future<Either<Failure, Unit>> _applyProperty(SuggestionRow row) async {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    final definitionId = payload['definitionId'] as String;
    final value = payload['value'] as String;

    // Si el elemento ya la tenía —puesta a mano, o heredada de la fuente— no
    // se vuelve a asignar: hacerlo le cambiaría el origen a "sugerida
    // aceptada", y deshacer la aceptación después le quitaría una propiedad
    // que nunca fue de la sugerencia. Queda anotado para el deshacer.
    final existing = await findValueByLabelOrAlias(_db, definitionId, value);
    if (existing != null && await _hasProperty(row.targetItemId, existing.id)) {
      await (_db.update(
        _db.suggestions,
      )..where((s) => s.id.equals(row.id))).write(
        SuggestionsCompanion(
          payloadJson: Value(jsonEncode({...payload, _alreadyHadKey: true})),
        ),
      );
      return right(unit);
    }

    return _organize.assignProperty(
      itemId: row.targetItemId,
      definitionId: definitionId,
      value: value,
      origin: ItemPropertyOrigin.suggestedAccepted,
    );
  }

  Future<bool> _hasProperty(String itemId, String propertyValueId) async {
    final row =
        await (_db.select(_db.itemPropertyValues)..where(
              (p) =>
                  p.itemId.equals(itemId) &
                  p.propertyValueId.equals(propertyValueId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  @override
  Future<Either<Failure, Unit>> revertAccepted(String id) async {
    try {
      final row = await (_db.select(
        _db.suggestions,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'La sugerencia ya no existe; puede que se haya borrado.',
          ),
        );
      }
      if (row.kind != SuggestionKind.property ||
          row.status != SuggestionStatus.accepted) {
        return left(
          const Failure.validation(
            message:
                'Solo se puede deshacer una sugerencia de propiedad ya '
                'aceptada.',
          ),
        );
      }

      await _db.transaction(() async {
        await _removeWhatItPut(row);
        await (_db.update(
          _db.suggestions,
        )..where((s) => s.id.equals(id))).write(
          const SuggestionsCompanion(status: Value(SuggestionStatus.pending)),
        );
      });
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.revertAccepted'),
      );
    }
  }

  @override
  Future<Either<Failure, int>> revertAcceptedMany(List<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return right(0);

    try {
      await _db.transaction(() async {
        final rows = await (_db.select(
          _db.suggestions,
        )..where((s) => s.id.isIn(unique))).get();
        final byId = {for (final row in rows) row.id: row};
        for (final id in unique) {
          final row = byId[id];
          if (row == null ||
              row.kind != SuggestionKind.property ||
              row.status != SuggestionStatus.accepted) {
            throw const _BatchAborted(
              Failure.validation(
                message:
                    'Alguna sugerencia ya no está aceptada, ya no existe o no '
                    'es de propiedad: no se deshizo ninguna.',
              ),
            );
          }
        }

        // Todas o ninguna: lanzar es lo que deshace la transacción entera.
        for (final row in byId.values) {
          await _removeWhatItPut(row);
          await (_db.update(
            _db.suggestions,
          )..where((s) => s.id.equals(row.id))).write(
            const SuggestionsCompanion(status: Value(SuggestionStatus.pending)),
          );
        }
      });
      return right(unique.length);
    } on _BatchAborted catch (aborted) {
      return left(aborted.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'SuggestionRepositoryImpl.revertAcceptedMany',
        ),
      );
    }
  }

  /// Quita del elemento la propiedad que puso la aceptación de [row], y el
  /// valor si la aceptación lo creó y nadie más lo usa.
  Future<void> _removeWhatItPut(SuggestionRow row) async {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    if (payload[_alreadyHadKey] == true) return;

    final value = await findValueByLabelOrAlias(
      _db,
      payload['definitionId'] as String,
      payload['value'] as String,
    );
    if (value == null) return;

    final placed =
        await (_db.select(_db.itemPropertyValues)..where(
              (p) =>
                  p.itemId.equals(row.targetItemId) &
                  p.propertyValueId.equals(value.id),
            ))
            .getSingleOrNull();
    // Solo lo que puso esta aceptación: si después el usuario la reemplazó por
    // una a mano, es suya.
    if (placed == null ||
        placed.origin != ItemPropertyOrigin.suggestedAccepted) {
      return;
    }

    await (_db.delete(_db.itemPropertyValues)..where(
          (p) =>
              p.itemId.equals(row.targetItemId) &
              p.propertyValueId.equals(value.id),
        ))
        .go();

    if (payload['isNewValue'] != true) return;
    final uses = _db.itemPropertyValues.itemId.count();
    final stillUsed =
        (await (_db.selectOnly(_db.itemPropertyValues)
              ..addColumns([uses])
              ..where(_db.itemPropertyValues.propertyValueId.equals(value.id)))
            .map((r) => r.read(uses)!)
            .getSingle()) >
        0;
    if (!stillUsed) {
      await (_db.delete(
        _db.propertyValues,
      )..where((v) => v.id.equals(value.id))).go();
    }
  }

  Future<Either<Failure, Unit>> _applyRelation(SuggestionRow row) {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return _organize.createRelation(
      fromItemId: row.targetItemId,
      toItemId: payload['relatedItemId'] as String,
      kind: RelationKind.values.byName(payload['relationKind'] as String),
      note: payload['reason'] as String,
    );
  }

  /// `row.targetItemId` es el que queda —el que ya existía cuando se
  /// generó la sugerencia—, `duplicateItemId` el que se descarta.
  Future<Either<Failure, Unit>> _applyDuplicate(SuggestionRow row) {
    final merge = _merge;
    if (merge == null) {
      // No debería pasar nunca en la práctica: la única instancia sin
      // `merge` es la dedicada al generador, que nunca llama a
      // `accept()` — ver el porqué en el doc comment del parámetro.
      return Future.value(
        left(
          const Failure.unexpected(
            message: 'Esta instancia no puede fusionar duplicados.',
          ),
        ),
      );
    }

    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return merge(
      keepItemId: row.targetItemId,
      discardItemId: payload['duplicateItemId'] as String,
    );
  }

  /// Completa la referencia de `row.targetItemId` con lo que la sugerencia
  /// encontró, dato por dato: lo que la referencia YA tiene manda, y lo que
  /// trae la sugerencia solo llena lo que sigue vacío —igual que reimportar
  /// un `.bib` (D9): nunca pisa lo que el usuario tocó, ni antes ni después
  /// de generarse la sugerencia—. Las personas no se mezclan: si ya había
  /// alguna cargada, las que trae la sugerencia se descartan enteras.
  ///
  /// Es la misma regla con la que la IA completa sola (F27,
  /// `completeEmptyReference`): lo que la sugerencia no trae —la edición si
  /// no la leyó, la clave de cita, cuándo se consultó, la exactitud de la
  /// fecha— queda como estaba: armar la referencia de nuevo con
  /// `mergeExtractedMetadata`, que no conoce esos datos, los borraría.
  Future<Either<Failure, Unit>> _applyMetadata(SuggestionRow row) async {
    final extracted = _extractedMetadataOf(
      jsonDecode(row.payloadJson) as Map<String, dynamic>,
    );

    final current = await ReferenceReader(_db).read(row.targetItemId);
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(row.targetItemId))).getSingleOrNull();
    if (source == null) {
      return left(
        const Failure.unexpected(
          message: 'El elemento ya no existe, o ya no es una fuente.',
        ),
      );
    }

    final completed = completeEmptyReference(
      current: current,
      publishedAt: source.publishedAt,
      found: extracted,
    );
    if (completed.reference != current) {
      await _writer.setReference(row.targetItemId, completed.reference);
    }
    if (completed.publishedAt != source.publishedAt) {
      await _writer.setFieldFromText(
        row.targetItemId,
        EntryField.publishedAt,
        '${completed.publishedAt!.millisecondsSinceEpoch ~/ 1000}',
      );
    }
    return right(unit);
  }

  /// Pone el tema bajo el padre propuesto (F27, el Atlas), con las reglas de
  /// `placeTopicValue`: si la persona ya lo ubicó, no se mueve y se dice.
  Future<Either<Failure, Unit>> _applyTopicParent(SuggestionRow row) {
    final suggestion = topicParentSuggestionOf(row);
    return _db.transaction(
      () => placeTopicValue(
        _db,
        valueId: suggestion.valueId,
        parentId: suggestion.parentId,
      ),
    );
  }

  /// Sube la madurez de la nota a la propuesta (F27, el Atlas): es la
  /// persona la que acepta, así que va por el mismo camino que elegirla a
  /// mano —versionada para la fusión de bóvedas—.
  Future<Either<Failure, Unit>> _applyMaturity(SuggestionRow row) async {
    final suggestion = maturitySuggestionOf(row);
    if (!await _writer.setMaturity(row.targetItemId, suggestion.to)) {
      return left(
        const Failure.unexpected(
          message: 'La nota ya no existe; puede que se haya borrado.',
        ),
      );
    }
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> reject(String id) async {
    try {
      final updated =
          await (_db.update(
            _db.suggestions,
          )..where((s) => s.id.equals(id))).writeReturning(
            const SuggestionsCompanion(
              status: Value(SuggestionStatus.rejected),
            ),
          );

      if (updated.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'La sugerencia ya no existe; puede que se haya borrado.',
          ),
        );
      }
      await _habits.record(HabitEventKind.triage);

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.reject'),
      );
    }
  }

  @override
  Stream<List<PropertySuggestionGroup>> watchPendingPropertySuggestionGroups() {
    return watchQuery(
      db: _db,
      tables: [
        _db.suggestions,
        _db.knowledgeEntries,
        _db.propertyDefinitions,
        _db.propertyValues,
        _db.propertyAliases,
      ],
      read: _readPropertyGroups,
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingPropertySuggestionGroups',
    );
  }

  Future<List<PropertySuggestionGroup>> _readPropertyGroups() async {
    final rows =
        await (_db.select(_db.suggestions)
              ..where(
                (s) =>
                    s.kind.equalsValue(SuggestionKind.property) &
                    s.status.equalsValue(SuggestionStatus.pending),
              )
              ..orderBy([
                (s) => OrderingTerm(expression: s.createdAt),
                (s) => OrderingTerm(expression: s.id),
              ]))
            .get();
    if (rows.isEmpty) return const [];

    final definitionNames = {
      for (final d in await _db.select(_db.propertyDefinitions).get())
        d.id: d.name,
    };

    final trashed = await trashedItemIds(_db);
    final grouped = <(String, String), List<PropertySuggestion>>{};
    for (final row in rows) {
      final suggestion = _toSuggestion(row);
      if (suggestion is! PropertySuggestion) continue;
      // Lo que se le iba a poner a algo que está en la papelera no se ofrece.
      if (trashed.contains(suggestion.targetItemId)) continue;
      // Las que no se pueden aplicar se dejan afuera: una sola que fallara
      // haría fallar el lote entero de `acceptMany`.
      if (!definitionNames.containsKey(suggestion.definitionId)) continue;
      final normalized = normalizeVocabularyLabel(suggestion.value);
      if (normalized.isEmpty) continue;
      grouped
          .putIfAbsent((suggestion.definitionId, normalized), () => [])
          .add(suggestion);
    }

    final groups = <PropertySuggestionGroup>[];
    for (final entry in grouped.entries) {
      final (definitionId, normalized) = entry.key;
      final value = _mostWrittenValue(entry.value);
      groups.add(
        PropertySuggestionGroup(
          definitionId: definitionId,
          definitionName: definitionNames[definitionId]!,
          value: value,
          normalizedValue: normalized,
          valueExists:
              await findValueByLabelOrAlias(_db, definitionId, value) != null,
          suggestions: entry.value,
        ),
      );
    }

    // Sobre el texto sin acentos: "Época" va con las E, no después de la Z.
    return groups..sort((a, b) {
      final byCount = b.suggestions.length.compareTo(a.suggestions.length);
      if (byCount != 0) return byCount;
      final byCategory = normalizeVocabularyLabel(
        a.definitionName,
      ).compareTo(normalizeVocabularyLabel(b.definitionName));
      if (byCategory != 0) return byCategory;
      return a.normalizedValue.compareTo(b.normalizedValue);
    });
  }

  /// Las sugerencias de [all] que no tocan nada de lo que está en la papelera:
  /// ni el elemento al que apuntan ni el otro, en una relación o un duplicado.
  /// Vuelven solas si el elemento se restaura.
  Future<List<Suggestion>> _aboutLiveItems(Iterable<Suggestion> all) async {
    final trashed = await trashedItemIds(_db);
    if (trashed.isEmpty) return all.toList();
    return [
      for (final suggestion in all)
        if (!trashed.contains(suggestion.targetItemId) &&
            switch (suggestion) {
              RelationSuggestionEntry(:final relatedItemId) =>
                !trashed.contains(relatedItemId),
              DuplicateSuggestionEntry(:final duplicateItemId) =>
                !trashed.contains(duplicateItemId),
              _ => true,
            })
          suggestion,
    ];
  }

  /// El valor como lo escribió la mayoría; a igual cantidad, el primero que se
  /// propuso —las sugerencias llegan de la más vieja a la más nueva—.
  String _mostWrittenValue(List<PropertySuggestion> suggestions) {
    final counts = <String, int>{};
    for (final suggestion in suggestions) {
      counts.update(suggestion.value.trim(), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  @override
  Future<Either<Failure, int>> acceptMany(List<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return right(0);

    try {
      await _db.transaction(() async {
        final rows = await (_db.select(
          _db.suggestions,
        )..where((s) => s.id.isIn(unique))).get();
        final byId = {for (final row in rows) row.id: row};
        for (final id in unique) {
          final row = byId[id];
          if (row == null ||
              row.status != SuggestionStatus.pending ||
              row.kind != SuggestionKind.property) {
            throw const _BatchAborted(
              Failure.validation(
                message:
                    'Alguna sugerencia ya no está pendiente, ya no existe o no '
                    'es de propiedad: no se aplicó ninguna.',
              ),
            );
          }
        }

        for (final id in unique) {
          final applied = await accept(id);
          final failure = applied.getLeft().toNullable();
          // Lanzar es lo que deshace la transacción entera: las ya aplicadas
          // antes de la que falló no pueden quedar a medias.
          if (failure != null) throw _BatchAborted(failure);
        }
      });
      return right(unique.length);
    } on _BatchAborted catch (aborted) {
      return left(aborted.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.acceptMany'),
      );
    }
  }

  @override
  Future<Either<Failure, int>> rejectMany(List<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return right(0);

    try {
      final updated =
          await (_db.update(_db.suggestions)..where(
                (s) =>
                    s.id.isIn(unique) &
                    s.status.equalsValue(SuggestionStatus.pending),
              ))
              .writeReturning(
                const SuggestionsCompanion(
                  status: Value(SuggestionStatus.rejected),
                ),
              );
      // Un solo evento para todo el lote: a la racha le alcanza con saber
      // que triar pasó hoy, no cuántas sugerencias tocó.
      if (updated.isNotEmpty) await _habits.record(HabitEventKind.triage);
      return right(updated.length);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'SuggestionRepositoryImpl.rejectMany'),
      );
    }
  }

  Suggestion _toSuggestion(SuggestionRow row) {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return switch (row.kind) {
      SuggestionKind.property => Suggestion.property(
        id: row.id,
        targetItemId: row.targetItemId,
        definitionId: payload['definitionId'] as String,
        definitionName: payload['definitionName'] as String,
        value: payload['value'] as String,
        isNewValue: payload['isNewValue'] as bool,
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      ),
      SuggestionKind.relation => Suggestion.relation(
        id: row.id,
        targetItemId: row.targetItemId,
        relatedItemId: payload['relatedItemId'] as String,
        relatedItemTitle: payload['relatedItemTitle'] as String,
        kind: RelationKind.values.byName(payload['relationKind'] as String),
        reason: payload['reason'] as String,
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      ),
      SuggestionKind.duplicate => Suggestion.duplicate(
        id: row.id,
        targetItemId: row.targetItemId,
        duplicateItemId: payload['duplicateItemId'] as String,
        duplicateItemTitle: payload['duplicateItemTitle'] as String,
        matchKind: DuplicateMatchKind.values.byName(
          payload['matchKind'] as String,
        ),
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      ),
      SuggestionKind.metadata => Suggestion.metadata(
        id: row.id,
        targetItemId: row.targetItemId,
        extracted: _extractedMetadataOf(payload),
        confidence: row.confidence,
        status: row.status,
        createdAt: row.createdAt,
      ),
      SuggestionKind.topicParent => topicParentSuggestionOf(row),
      SuggestionKind.maturity => maturitySuggestionOf(row),
      SuggestionKind.flashcard => throw StateError(
        'SuggestionKind.${row.kind.name} todavía no tiene generador; no '
        'debería existir ninguna fila con este kind.',
      ),
    };
  }

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}

/// Una sugerencia del lote no se pudo aplicar: deshace la transacción del
/// lote entero.
/// La marca que deja `_applyProperty` en el payload cuando el elemento ya
/// tenía la propiedad: la aceptación no puso nada, y deshacerla tampoco quita
/// nada.
const _alreadyHadKey = 'alreadyHad';

class _BatchAborted implements Exception {
  const _BatchAborted(this.failure);

  final Failure failure;
}

/// Las sugerencias «para revisar» de un elemento mientras se agrupan.
class _ReviewGroup {
  _ReviewGroup(this.title);

  final String title;
  final ids = <String>[];
  DateTime? latestAt;
}

// ---------------------------------------------------------------------------
// El payload de una sugerencia de referencia (F15): `ExtractedMetadata` no
// sabe de JSON —es una entidad de dominio, no de persistencia—, así que el
// ida y vuelta vive acá, junto al resto de los `jsonEncode`/`jsonDecode` de
// los otros tres tipos de sugerencia.
// ---------------------------------------------------------------------------

Map<String, dynamic> _metadataPayloadOf(ExtractedMetadata extracted) => {
  'title': extracted.title,
  'publishedAt': extracted.publishedAt == null
      ? null
      : extracted.publishedAt!.millisecondsSinceEpoch ~/ 1000,
  'publicationPrecision': extracted.publicationPrecision?.name,
  'reference': _referenceDataPayloadOf(extracted.reference),
};

Map<String, dynamic> _referenceDataPayloadOf(ReferenceData reference) => {
  'type': reference.type?.name,
  'contributors': [
    for (final contributor in reference.contributors)
      {
        'role': contributor.role.name,
        'family': contributor.name.family,
        'given': contributor.name.given,
        'suffix': contributor.name.suffix,
        'isInstitution': contributor.name.isInstitution,
      },
  ],
  'containerTitle': reference.containerTitle,
  'publisher': reference.publisher,
  'publisherPlace': reference.publisherPlace,
  'edition': reference.edition,
  'volume': reference.volume,
  'issue': reference.issue,
  'pages': reference.pages,
  'isbn': reference.isbn,
  'issn': reference.issn,
  'doi': reference.doi,
};

ExtractedMetadata _extractedMetadataOf(Map<String, dynamic> payload) {
  final publishedAtSeconds = payload['publishedAt'] as int?;
  final precisionName = payload['publicationPrecision'] as String?;
  return ExtractedMetadata(
    title: payload['title'] as String?,
    publishedAt: publishedAtSeconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(publishedAtSeconds * 1000),
    publicationPrecision: precisionName == null
        ? null
        : PublicationPrecision.values.byName(precisionName),
    reference: _referenceDataOf(
      payload['reference'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

ReferenceData _referenceDataOf(Map<String, dynamic> payload) {
  final typeName = payload['type'] as String?;
  return ReferenceData(
    type: typeName == null ? null : ReferenceType.values.byName(typeName),
    contributors: [
      for (final raw in payload['contributors'] as List<dynamic>? ?? const [])
        _contributorOf(raw as Map<String, dynamic>),
    ],
    containerTitle: payload['containerTitle'] as String?,
    publisher: payload['publisher'] as String?,
    publisherPlace: payload['publisherPlace'] as String?,
    edition: payload['edition'] as String?,
    volume: payload['volume'] as String?,
    issue: payload['issue'] as String?,
    pages: payload['pages'] as String?,
    isbn: payload['isbn'] as String?,
    issn: payload['issn'] as String?,
    doi: payload['doi'] as String?,
  );
}

Contributor _contributorOf(Map<String, dynamic> payload) => Contributor(
  name: PersonName(
    family: payload['family'] as String? ?? '',
    given: payload['given'] as String? ?? '',
    suffix: payload['suffix'] as String? ?? '',
    isInstitution: payload['isInstitution'] as bool? ?? false,
  ),
  role: ContributorRole.values.byName(payload['role'] as String),
);
