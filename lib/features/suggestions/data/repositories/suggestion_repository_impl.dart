import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/duplicates/domain/usecases/merge_duplicate_items_usecase.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
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

  @override
  Stream<List<Suggestion>> watchPendingSuggestions(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions],
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
        return rows.map(_toSuggestion).toList();
      },
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingSuggestions',
    );
  }

  @override
  Stream<List<Suggestion>> watchPendingDuplicateSuggestions() {
    return watchQuery(
      db: _db,
      tables: [_db.suggestions],
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
        return rows.map(_toSuggestion).toList();
      },
      telemetry: _telemetry,
      hint: 'SuggestionRepositoryImpl.watchPendingDuplicateSuggestions',
    );
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

    final grouped = <(String, String), List<PropertySuggestion>>{};
    for (final row in rows) {
      final suggestion = _toSuggestion(row);
      if (suggestion is! PropertySuggestion) continue;
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
