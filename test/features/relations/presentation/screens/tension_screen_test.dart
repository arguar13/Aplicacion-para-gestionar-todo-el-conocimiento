import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/screens/tension_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpTension(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const TensionScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin ninguna contradicción, lo explica', (tester) async {
    await harness.capture('Un elemento sin vínculos');

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsOneWidget);
  });

  testWidgets('un vínculo relatedTo no cuenta como contradicción', (
    tester,
  ) async {
    await harness.capture('A');
    await harness.capture('B');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'A');
    final itemB = items.firstWhere((i) => i.title == 'B');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.relatedTo,
        );

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsOneWidget);
  });

  testWidgets('con una contradicción, muestra los dos elementos', (
    tester,
  ) async {
    await harness.capture('Un artículo');
    await harness.capture('Otro que lo contradice');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'Un artículo');
    final itemB = items.firstWhere((i) => i.title == 'Otro que lo contradice');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.contradicts,
        );

    await pumpTension(tester);

    expect(find.text(es.tensionEmpty), findsNothing);
    expect(find.text('Un artículo'), findsOneWidget);
    expect(find.text('Otro que lo contradice'), findsOneWidget);
  });

  testWidgets('tocar un título navega al detalle de ese elemento', (
    tester,
  ) async {
    await harness.capture('Un artículo');
    await harness.capture('Otro que lo contradice');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    final itemA = items.firstWhere((i) => i.title == 'Un artículo');
    final itemB = items.firstWhere((i) => i.title == 'Otro que lo contradice');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: itemA.id,
          toItemId: itemB.id,
          kind: RelationKind.contradicts,
        );

    harness.goTo('/graph/tension');
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Un artículo'));
    await tester.pumpAndSettle();

    expect(find.text('Un artículo'), findsWidgets);
  });

  group('revisar contradicciones (F9)', () {
    /// Dos contradicciones: "Uno" contra "Dos" y "Tres" contra "Cuatro".
    Future<void> seedTwoContradictions() async {
      for (final title in ['Uno', 'Dos', 'Tres', 'Cuatro']) {
        await harness.capture(title);
      }
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      String idOf(String title) => items.firstWhere((i) => i.title == title).id;
      final organize = harness.container.read(organizeRepositoryProvider);
      await organize.createRelation(
        fromItemId: idOf('Uno'),
        toItemId: idOf('Dos'),
        kind: RelationKind.contradicts,
      );
      await organize.createRelation(
        fromItemId: idOf('Tres'),
        toItemId: idOf('Cuatro'),
        kind: RelationKind.contradicts,
      );
    }

    Future<List<DateTime?>> reviewedAts() async => [
      for (final r
          in await harness.database.select(harness.database.relations).get())
        r.reviewedAt,
    ];

    testWidgets('arranca con lo pendiente y cuenta cuántos pares faltan', (
      tester,
    ) async {
      await seedTwoContradictions();

      await pumpTension(tester);

      expect(find.text(es.tensionPendingCount(2)), findsOneWidget);
      expect(find.byTooltip(es.tensionMarkReviewed), findsNWidgets(2));
      // Sin ninguna revisada no hay nada que filtrar.
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('marcar una como revisada la saca de la lista, baja la cuenta '
        'y avisa con "Deshacer"', (tester) async {
      await seedTwoContradictions();
      await pumpTension(tester);

      await tester.tap(find.byTooltip(es.tensionMarkReviewed).first);
      await tester.pumpAndSettle();

      expect(find.text(es.tensionPendingCount(1)), findsOneWidget);
      expect(find.byTooltip(es.tensionMarkReviewed), findsOneWidget);
      expect(find.text(es.tensionMarkedReviewed), findsOneWidget);
      expect(find.text(es.tensionUndoAction), findsOneWidget);
      expect((await reviewedAts()).where((d) => d != null), hasLength(1));
      // Ahora hay una revisada que se puede volver a ver.
      expect(find.text(es.tensionShowReviewed(1)), findsOneWidget);
    });

    testWidgets('"Deshacer" del aviso la vuelve a dejar pendiente', (
      tester,
    ) async {
      await seedTwoContradictions();
      await pumpTension(tester);
      await tester.tap(find.byTooltip(es.tensionMarkReviewed).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.tensionUndoAction));
      await tester.pumpAndSettle();

      expect(find.text(es.tensionPendingCount(2)), findsOneWidget);
      expect(await reviewedAts(), everyElement(isNull));
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('el filtro suma las revisadas al final, marcadas como tales', (
      tester,
    ) async {
      await seedTwoContradictions();
      await pumpTension(tester);
      await tester.tap(find.byTooltip(es.tensionMarkReviewed).first);
      await tester.pumpAndSettle();
      expect(find.text(es.tensionReviewedBadge), findsNothing);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      // Las dos a la vista; la pendiente primero.
      expect(find.byTooltip(es.tensionMarkReviewed), findsOneWidget);
      expect(find.byTooltip(es.tensionMarkUnreviewed), findsOneWidget);
      expect(find.text(es.tensionReviewedBadge), findsOneWidget);
      final pendingY = tester
          .getTopLeft(find.byTooltip(es.tensionMarkReviewed))
          .dy;
      final reviewedY = tester
          .getTopLeft(find.byTooltip(es.tensionMarkUnreviewed))
          .dy;
      expect(pendingY, lessThan(reviewedY));
    });

    testWidgets('quitarle la marca a una revisada la vuelve pendiente', (
      tester,
    ) async {
      await seedTwoContradictions();
      await pumpTension(tester);
      await tester.tap(find.byTooltip(es.tensionMarkReviewed).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(es.tensionMarkUnreviewed));
      await tester.pumpAndSettle();

      expect(find.text(es.tensionPendingCount(2)), findsOneWidget);
      expect(find.text(es.tensionReviewedBadge), findsNothing);
      expect(await reviewedAts(), everyElement(isNull));
    });

    testWidgets('con todas revisadas lo dice y deja verlas', (tester) async {
      await harness.capture('Un artículo');
      await harness.capture('Otro que lo contradice');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: items.first.id,
            toItemId: items.last.id,
            kind: RelationKind.contradicts,
          );
      await pumpTension(tester);

      await tester.tap(find.byTooltip(es.tensionMarkReviewed));
      await tester.pumpAndSettle();

      expect(find.text(es.tensionAllReviewed), findsOneWidget);
      expect(find.text(es.tensionPendingCount(0)), findsOneWidget);
      // No es "no hay contradicciones": las hay, y se pueden volver a ver.
      expect(find.text(es.tensionEmpty), findsNothing);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      expect(find.text(es.tensionReviewedBadge), findsOneWidget);
    });
  });
}
