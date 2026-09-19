import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/features/duplicates/presentation/screens/possible_duplicates_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const PossibleDuplicatesScreen()));
    await tester.pumpAndSettle();
  }

  Future<String> seedItem(String title) async {
    await harness.capture(title);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.firstWhere((i) => i.title == title).id;
  }

  Future<void> seedSuggestion({
    required String keepId,
    required String discardId,
    required String discardTitle,
  }) async {
    await harness.container
        .read(suggestionRepositoryProvider)
        .createDuplicateSuggestion(
          targetItemId: keepId,
          duplicateItemId: discardId,
          duplicateItemTitle: discardTitle,
          matchKind: DuplicateMatchKind.exact,
        );
  }

  testWidgets('sin sugerencias pendientes, estado vacío', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.duplicatesEmpty), findsOneWidget);
  });

  testWidgets('con una sugerencia pendiente, muestra los dos títulos', (
    tester,
  ) async {
    final keepId = await seedItem('El que queda');
    final discardId = await seedItem('El posible duplicado');
    await seedSuggestion(
      keepId: keepId,
      discardId: discardId,
      discardTitle: 'El posible duplicado',
    );

    await pumpScreen(tester);

    expect(find.text(es.duplicatesEmpty), findsNothing);
    expect(find.text('El que queda'), findsOneWidget);
    expect(find.text('El posible duplicado'), findsOneWidget);
  });

  testWidgets('descartar la saca de la lista sin fusionar nada', (
    tester,
  ) async {
    final keepId = await seedItem('El que queda');
    final discardId = await seedItem('El posible duplicado');
    await seedSuggestion(
      keepId: keepId,
      discardId: discardId,
      discardTitle: 'El posible duplicado',
    );
    await pumpScreen(tester);

    await tester.tap(find.text(es.duplicatesDiscardAction));
    await tester.pumpAndSettle();

    expect(find.text(es.duplicatesEmpty), findsOneWidget);
    expect(find.text(es.duplicatesDiscarded), findsOneWidget);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    expect(items, hasLength(2));
  });

  testWidgets('fusionar pide confirmación antes de aplicar nada', (
    tester,
  ) async {
    final keepId = await seedItem('El que queda');
    final discardId = await seedItem('El posible duplicado');
    await seedSuggestion(
      keepId: keepId,
      discardId: discardId,
      discardTitle: 'El posible duplicado',
    );
    await pumpScreen(tester);

    await tester.tap(find.text(es.duplicatesMergeAction));
    await tester.pumpAndSettle();

    expect(find.text(es.duplicatesMergeConfirmTitle), findsOneWidget);
    // Nada se aplicó todavía: los dos elementos siguen existiendo.
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    expect(items, hasLength(2));
  });

  testWidgets('confirmar la fusión deja un solo elemento y saca la fila', (
    tester,
  ) async {
    final keepId = await seedItem('El que queda');
    final discardId = await seedItem('El posible duplicado');
    await seedSuggestion(
      keepId: keepId,
      discardId: discardId,
      discardTitle: 'El posible duplicado',
    );
    await pumpScreen(tester);

    await tester.tap(find.text(es.duplicatesMergeAction));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(es.duplicatesMergeAction),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(es.duplicatesEmpty), findsOneWidget);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    expect(items.map((i) => i.id), [keepId]);
  });

  testWidgets('cancelar la confirmación no fusiona ni saca la fila', (
    tester,
  ) async {
    final keepId = await seedItem('El que queda');
    final discardId = await seedItem('El posible duplicado');
    await seedSuggestion(
      keepId: keepId,
      discardId: discardId,
      discardTitle: 'El posible duplicado',
    );
    await pumpScreen(tester);

    await tester.tap(find.text(es.duplicatesMergeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(find.text('El posible duplicado'), findsOneWidget);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    expect(items, hasLength(2));
  });
}
