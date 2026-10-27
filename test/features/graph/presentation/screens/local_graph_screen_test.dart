import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<String> idOf(String title) async {
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.firstWhere((i) => i.title == title).id;
  }

  Future<void> pumpLocalGraph(WidgetTester tester, String itemId) async {
    harness.goTo(RoutePaths.graphLocal(itemId));
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
  }

  testWidgets('sin ningún vínculo, explica que todavía no hay nada que ver', (
    tester,
  ) async {
    await harness.capture('una nota sin vínculos');
    final id = await idOf('una nota sin vínculos');

    await pumpLocalGraph(tester, id);

    expect(find.text(es.graphEmpty), findsOneWidget);
  });

  testWidgets(
    'con un vínculo directo, la semilla y el vecino aparecen como nodos '
    'tocables',
    (tester) async {
      await harness.capture('La semilla');
      await harness.capture('El vecino directo');
      final seedId = await idOf('La semilla');
      final neighborId = await idOf('El vecino directo');

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: seedId,
            toItemId: neighborId,
            kind: RelationKind.relatedTo,
          );

      await pumpLocalGraph(tester, seedId);

      expect(find.text(es.graphEmpty), findsNothing);
      expect(find.text('La semilla'), findsOneWidget);
      expect(find.text('El vecino directo'), findsOneWidget);
    },
  );

  testWidgets('tocar un vecino normal navega a su detalle', (tester) async {
    await harness.capture('La semilla');
    await harness.capture('El vecino directo');
    final seedId = await idOf('La semilla');
    final neighborId = await idOf('El vecino directo');

    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: seedId,
          toItemId: neighborId,
          kind: RelationKind.relatedTo,
        );

    await pumpLocalGraph(tester, seedId);
    await tester.tap(find.text('El vecino directo'));
    await tester.pumpAndSettle();

    expect(find.text(es.detailRelationsTitle), findsOneWidget);
  });

  testWidgets(
    'un vecino marcado como nota mapa entra al grafo local centrado en él, '
    'en vez de a su detalle',
    (tester) async {
      await harness.capture('La semilla');
      await harness.capture('El vecino mapa');
      final seedId = await idOf('La semilla');
      final neighborId = await idOf('El vecino mapa');

      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: seedId,
            toItemId: neighborId,
            kind: RelationKind.relatedTo,
          );
      await harness.container
          .read(inboxRepositoryProvider)
          .setNoteKind(itemId: neighborId, kind: NoteKind.map);

      await pumpLocalGraph(tester, seedId);
      await tester.tap(find.text('El vecino mapa'));
      await tester.pumpAndSettle();

      expect(find.text(es.localGraphTitle('El vecino mapa')), findsOneWidget);
      expect(find.text(es.detailRelationsTitle), findsNothing);
    },
  );

  testWidgets(
    'cambiar el selector de grado a 2 muestra recién ahí un vecino a dos '
    'saltos',
    (tester) async {
      await harness.capture('La semilla');
      await harness.capture('El vecino directo');
      await harness.capture('El vecino lejano');
      final seedId = await idOf('La semilla');
      final directId = await idOf('El vecino directo');
      final farId = await idOf('El vecino lejano');

      final organize = harness.container.read(organizeRepositoryProvider);
      await organize.createRelation(
        fromItemId: seedId,
        toItemId: directId,
        kind: RelationKind.relatedTo,
      );
      await organize.createRelation(
        fromItemId: directId,
        toItemId: farId,
        kind: RelationKind.relatedTo,
      );

      await pumpLocalGraph(tester, seedId);

      expect(find.text('El vecino lejano'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();

      expect(find.text('El vecino lejano'), findsOneWidget);
    },
  );

  testWidgets(
    'un grafo grande entra entero: se puede alejar más allá del piso de '
    'siempre, y al abrir ya se ve todo (F40)',
    (tester) async {
      await harness.capture('La semilla');
      final seedId = await idOf('La semilla');
      final organize = harness.container.read(organizeRepositoryProvider);
      for (var i = 0; i < 60; i++) {
        await harness.capture('Vecino $i');
        await organize.createRelation(
          fromItemId: seedId,
          toItemId: await idOf('Vecino $i'),
          kind: RelationKind.relatedTo,
        );
      }

      await pumpLocalGraph(tester, seedId);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, lessThan(0.1));
      final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
      expect(scale, greaterThanOrEqualTo(viewer.minScale));

      final visible = tester.getRect(find.byType(InteractiveViewer));
      for (final title in [
        'La semilla',
        for (var i = 0; i < 60; i++) 'Vecino $i',
      ]) {
        final center = tester.getCenter(find.text(title));
        expect(visible.inflate(1).contains(center), isTrue, reason: title);
      }

      // El botón «−» también llega hasta ese piso, y no más allá.
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
      }
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        closeTo(viewer.minScale, 1e-9),
      );
    },
  );
}
