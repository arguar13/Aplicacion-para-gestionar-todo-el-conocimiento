import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

class SuggestionRepositoryImpl implements SuggestionRepository {
  const SuggestionRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required OrganizeRepository organize,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _organize = organize,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final OrganizeRepository _organize;
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
        Suggestion(
          id: id,
          kind: SuggestionKind.property,
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

      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final applied = await _organize.assignProperty(
        itemId: row.targetItemId,
        definitionId: payload['definitionId'] as String,
        value: payload['value'] as String,
        origin: ItemPropertyOrigin.suggestedAccepted,
      );
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
    return Suggestion(
      id: row.id,
      kind: row.kind,
      targetItemId: row.targetItemId,
      definitionId: payload['definitionId'] as String,
      definitionName: payload['definitionName'] as String,
      value: payload['value'] as String,
      isNewValue: payload['isNewValue'] as bool,
      confidence: row.confidence,
      status: row.status,
      createdAt: row.createdAt,
    );
  }

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
