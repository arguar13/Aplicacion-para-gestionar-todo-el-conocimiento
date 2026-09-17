import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpExplorer(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const ExplorerScreen()));
    await tester.pumpAndSettle();
  }

  // El FAB y —en la raíz vacía— el botón del estado vacío dicen los dos
  // "Nueva carpeta": hace falta apuntar al FAB en concreto para no toparse
  // con la ambigüedad de `find.text`.
  Finder newFolderFab() =>
      find.widgetWithText(FloatingActionButton, es.explorerNewFolder);

  testWidgets('sin ninguna carpeta ni elemento, explica que no hay nada '
      'organizado', (tester) async {
    await pumpExplorer(tester);

    expect(find.text(es.explorerEmptyRootTitle), findsOneWidget);
  });

  testWidgets('un elemento recién capturado aparece en la raíz sin carpeta', (
    tester,
  ) async {
    await harness.capture('Una nota cualquiera');

    await pumpExplorer(tester);

    expect(find.text('Una nota cualquiera'), findsOneWidget);
  });

  testWidgets('crear una carpeta la muestra en la grilla', (tester) async {
    await pumpExplorer(tester);

    await tester.tap(newFolderFab());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Filosofía');
    await tester.tap(find.text(es.commonCreate));
    await tester.pumpAndSettle();

    expect(find.text('Filosofía'), findsOneWidget);
    // Se fue el estado vacío: ya hay algo que mostrar.
    expect(find.text(es.explorerEmptyRootTitle), findsNothing);
  });

  testWidgets('entrar a una carpeta la agrega a las migas de pan, y crear una '
      'subcarpeta ahí no aparece en la raíz', (tester) async {
    await harness.container
        .read(explorerRepositoryProvider)
        .createFolder(name: 'Filosofía', parentId: null);

    await pumpExplorer(tester);
    await tester.tap(find.text('Filosofía'));
    await tester.pumpAndSettle();

    await tester.tap(newFolderFab());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ética');
    await tester.tap(find.text(es.commonCreate));
    await tester.pumpAndSettle();

    expect(find.text('Ética'), findsOneWidget);

    await tester.tap(find.text(es.explorerRootBreadcrumb));
    await tester.pumpAndSettle();

    expect(find.text('Ética'), findsNothing);
    expect(find.text('Filosofía'), findsOneWidget);
  });

  testWidgets(
    'agregar un elemento a una carpeta lo saca de la raíz y lo lleva a esa '
    'carpeta',
    (tester) async {
      await harness.capture('Una nota cualquiera');
      await pumpExplorer(tester);
      await tester.tap(newFolderFab());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Trabajo');
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Una nota cualquiera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.explorerAddToFolder));
      await tester.pumpAndSettle();
      // La misma "Trabajo" aparece tanto en la grilla (detrás) como en cada
      // fila de la hoja de elegir carpeta (encima): la fila del selector es
      // la que está dentro de un `ListTile`, la de la grilla no.
      await tester.tap(find.widgetWithText(ListTile, 'Trabajo'));
      await tester.pumpAndSettle();

      // La raíz ya no lo muestra: se fue a la carpeta.
      expect(find.text('Una nota cualquiera'), findsNothing);

      await tester.tap(find.text('Trabajo'));
      await tester.pumpAndSettle();

      expect(find.text('Una nota cualquiera'), findsOneWidget);
    },
  );

  testWidgets('eliminar una carpeta no borra el elemento: vuelve a la raíz', (
    tester,
  ) async {
    await harness.capture('Una nota cualquiera');
    await pumpExplorer(tester);
    await tester.tap(newFolderFab());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Efímera');
    await tester.tap(find.text(es.commonCreate));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Una nota cualquiera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.explorerAddToFolder));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Efímera'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.explorerDeleteFolder));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonDelete));
    await tester.pumpAndSettle();

    expect(find.text('Efímera'), findsNothing);
    expect(find.text('Una nota cualquiera'), findsOneWidget);
  });
}
