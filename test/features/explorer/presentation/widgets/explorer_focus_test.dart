import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

import '../../../../support/library_harness.dart';

/// El Explorador llega filtrado por un valor cuando se lo abre con `?value=`
/// (F13): lo que hace el Atlas desde una rama o un vacío.
void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pump(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(location);
    await tester.pumpAndSettle();
  }

  Set<String> filteredValues() =>
      harness.container.read(explorerQueryNotifierProvider).propertyValueIds;

  testWidgets('con un valor, el Explorador lo mira y sus subtemas', (
    tester,
  ) async {
    await pump(tester, RoutePaths.explorerFor('roma'));

    expect(find.byType(ExplorerScreen), findsOneWidget);
    expect(filteredValues(), {'roma'});
  });

  testWidgets('sin valor, no toca lo que el Explorador estaba filtrando', (
    tester,
  ) async {
    await pump(tester, RoutePaths.explorer);

    expect(find.byType(ExplorerScreen), findsOneWidget);
    expect(filteredValues(), isEmpty);
  });

  testWidgets('llegar con otro valor cambia lo que mira el Explorador que '
      'seguía abierto', (tester) async {
    await pump(tester, RoutePaths.explorerFor('roma'));
    expect(filteredValues(), {'roma'});

    harness.goTo(RoutePaths.explorerFor('grecia'));
    await tester.pumpAndSettle();

    expect(filteredValues(), {'grecia'});
  });

  testWidgets('llegar con un valor deja SOLO ese filtro: lo que había se '
      'quita', (tester) async {
    await pump(tester, RoutePaths.explorer);
    harness.container
        .read(explorerQueryNotifierProvider.notifier)
        .togglePropertyValueId('otro');
    await tester.pumpAndSettle();
    expect(filteredValues(), {'otro'});

    harness.goTo(RoutePaths.explorerFor('roma'));
    await tester.pumpAndSettle();

    expect(filteredValues(), {'roma'});
  });

  testWidgets('el id viaja bien codificado en la dirección', (tester) async {
    await pump(tester, RoutePaths.explorerFor('a b&c'));

    expect(filteredValues(), {'a b&c'});
  });

  group('con un tema (F28)', () {
    Future<String> space(String name) async =>
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!
            .id;

    testWidgets('el Explorador se para en ese tema, y nada más', (
      tester,
    ) async {
      final historia = await space('Historia');
      await pump(tester, RoutePaths.explorer);
      harness.container
          .read(explorerQueryNotifierProvider.notifier)
          .togglePropertyValueId('otro');
      await tester.pumpAndSettle();

      harness.goTo(RoutePaths.explorerForSpace(historia));
      await tester.pumpAndSettle();

      final query = harness.container.read(explorerQueryNotifierProvider);
      expect(query.spaceId, historia);
      expect(query.propertyValueIds, isEmpty);
    });

    testWidgets('llegar con otro tema cambia el que se mira', (tester) async {
      final historia = await space('Historia');
      final arte = await space('Arte');
      await pump(tester, RoutePaths.explorerForSpace(historia));

      harness.goTo(RoutePaths.explorerForSpace(arte));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(explorerQueryNotifierProvider).spaceId,
        arte,
      );
    });
  });
}
