import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_review/data/repositories/pending_review_repository_impl.dart';

import '../../../support/item_rows.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// El índice de «Para revisar» (F27): qué elementos tienen sugerencias
/// pendientes y cuántas hay, sin duplicados ni nada de la papelera.
void main() {
  late AppDatabase db;
  late PendingReviewRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = PendingReviewRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
    );
    for (final id in ['a', 'b', 'c']) {
      await insertItemRows(db, id: id, title: 'Elemento $id');
    }
  });

  tearDown(() => db.close());

  Future<void> suggest(
    String id, {
    required String target,
    required int minute,
    SuggestionKind kind = SuggestionKind.property,
    SuggestionStatus status = SuggestionStatus.pending,
    String? relatedId,
  }) => db
      .into(db.suggestions)
      .insert(
        SuggestionsCompanion.insert(
          id: id,
          kind: kind,
          targetItemId: target,
          payloadJson: jsonEncode({
            if (relatedId != null) 'relatedItemId': relatedId,
          }),
          status: Value(status),
          createdAt: DateTime(2026, 10, 2, 10, minute),
        ),
      );

  Future<void> trash(String itemId) =>
      (db.update(db.knowledgeEntries)..where((e) => e.id.equals(itemId))).write(
        KnowledgeEntriesCompanion(deletedAt: Value(DateTime(2026))),
      );

  test('sin nada pendiente, no hay nada que revisar', () async {
    await suggest(
      's1',
      target: 'a',
      status: SuggestionStatus.accepted,
      minute: 1,
    );

    expect(await repository.watchItemsWithPendingReview().first, isEmpty);
    expect(await repository.watchPendingReviewCount().first, 0);
  });

  test(
    'agrupa por elemento, con el de la sugerencia más nueva primero',
    () async {
      await suggest('s1', target: 'a', minute: 1);
      await suggest('s2', target: 'b', minute: 2);
      await suggest(
        's3',
        target: 'a',
        kind: SuggestionKind.metadata,
        minute: 3,
      );
      await suggest(
        's4',
        target: 'b',
        kind: SuggestionKind.relation,
        relatedId: 'c',
        minute: 4,
      );

      final items = await repository.watchItemsWithPendingReview().first;

      expect([for (final item in items) item.itemId], ['b', 'a']);
      expect(items.first.itemTitle, 'Elemento b');
      expect(items.first.suggestionIds, ['s2', 's4']);
      expect(items.last.suggestionIds, ['s1', 's3']);
      expect(items.first.latestAt, DateTime(2026, 10, 2, 10, 4));
      expect(await repository.watchPendingReviewCount().first, 4);
    },
  );

  test('deja afuera los duplicados: tienen su pantalla', () async {
    await suggest('s1', target: 'a', kind: SuggestionKind.duplicate, minute: 1);

    expect(await repository.watchItemsWithPendingReview().first, isEmpty);
    expect(await repository.watchPendingReviewCount().first, 0);
  });

  test('deja afuera lo de un elemento en la papelera y los vínculos hacia '
      'uno', () async {
    await suggest('s1', target: 'a', minute: 1);
    await suggest(
      's2',
      target: 'b',
      kind: SuggestionKind.relation,
      relatedId: 'c',
      minute: 2,
    );
    await suggest('s3', target: 'b', minute: 3);
    await trash('a');
    await trash('c');

    final items = await repository.watchItemsWithPendingReview().first;

    expect(items, hasLength(1));
    expect(items.single.suggestionIds, ['s3']);
    expect(await repository.watchPendingReviewCount().first, 1);
  });

  test('se actualiza solo cuando una sugerencia se resuelve', () async {
    await suggest('s1', target: 'a', minute: 1);
    await suggest('s2', target: 'a', minute: 2);
    final counts = repository.watchPendingReviewCount();
    final expectation = expectLater(counts, emitsInOrder([2, 1]));

    await pumpEventQueue();
    await (db.update(db.suggestions)..where((s) => s.id.equals('s1'))).write(
      const SuggestionsCompanion(status: Value(SuggestionStatus.rejected)),
    );

    await expectation;
  });
}
