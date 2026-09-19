import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/duplicates/domain/usecases/merge_duplicate_items_usecase.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

class SuggestionRepositoryImpl implements SuggestionRepository {
  const SuggestionRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required OrganizeRepository organize,
    required MergeDuplicateItemsUseCase merge,
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
  final MergeDuplicateItemsUseCase _merge;
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

  Future<Either<Failure, Unit>> _applyProperty(SuggestionRow row) {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return _organize.assignProperty(
      itemId: row.targetItemId,
      definitionId: payload['definitionId'] as String,
      value: payload['value'] as String,
      origin: ItemPropertyOrigin.suggestedAccepted,
    );
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
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return _merge(
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
