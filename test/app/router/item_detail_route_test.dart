import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';

import '../../support/item_rows.dart';
import '../../support/library_harness.dart';

/// El detalle de un elemento se abre igual desde cualquier lado.
///
/// Vive bajo `/library/:id`, pero se dibuja en el `Navigator` de la raíz: las
/// pantallas que se abren encima del shell (el material de un tema, la
/// lectura, el mapa local…) lo empujan, y si la ruta viviera dentro del shell
/// se apilaría un segundo shell con la misma clave de página sobre el primero
/// y el detalle saldría en blanco.
void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    await insertItemRows(harness.database, id: 'a', title: 'Una fuente');
  });

  Future<void> pump(WidgetTester tester) async {
    // Ancho de escritorio: la barra de navegación es el riel del costado.
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
  }

  Future<void> push(WidgetTester tester, String location) async {
    unawaited(harness.container.read(goRouterProvider).push<void>(location));
    await tester.pumpAndSettle();
  }

  /// «Atrás». El tick de más deja correr los temporizadores con que drift
  /// cierra sus consultas al soltar la pantalla que las miraba: sin él, la
  /// prueba termina con uno pendiente.
  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// El título del elemento, en la barra de su detalle: si el detalle no
  /// cargó su elemento, la barra sale sin título.
  Finder inDetail(String title) => find.descendant(
    of: find.descendant(
      of: find.byType(ItemDetailScreen),
      matching: find.byType(AppBar),
    ),
    matching: find.text(title),
  );

  testWidgets('desde una pantalla de la raíz que está encima del shell se '
      'abre con su contenido, y «atrás» vuelve a ella y luego al shell', (
    tester,
  ) async {
    await pump(tester);
    await push(tester, RoutePaths.trash);
    expect(find.byType(NavigationRail), findsNothing);

    await push(tester, RoutePaths.itemDetail('a'));

    expect(tester.takeException(), isNull);
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(inDetail('Una fuente'), findsOneWidget);

    await back(tester);
    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(LibraryScreen), findsNothing);

    await back(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('desde el material de un tema, encima de la Biblioteca', (
    tester,
  ) async {
    await pump(tester);
    await push(tester, RoutePaths.explorer);
    expect(find.byType(ExplorerScreen), findsOneWidget);

    await tester.tap(find.text('Una fuente'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(inDetail('Una fuente'), findsOneWidget);
  });

  testWidgets('desde la Biblioteca se abre y «atrás» vuelve a la lista', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.text('Una fuente'));
    await tester.pumpAndSettle();

    expect(inDetail('Una fuente'), findsOneWidget);
    // Va a pantalla completa, igual que cuando se abre desde otra pantalla.
    expect(find.byType(NavigationRail), findsNothing);

    await back(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('abrir un elemento y volver deja la Biblioteca como estaba', (
    tester,
  ) async {
    await insertItemRows(harness.database, id: 'b', title: 'Otra cosa');
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Una');
    await tester.pumpAndSettle();
    expect(find.text('Otra cosa'), findsNothing);

    await tester.tap(find.text('Una fuente'));
    await tester.pumpAndSettle();
    await back(tester);

    // La búsqueda y su resultado siguen: la Biblioteca no se rearmó.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Una fuente'), findsOneWidget);
    expect(find.text('Otra cosa'), findsNothing);
    expect(find.widgetWithText(TextField, 'Una'), findsOneWidget);
  });

  testWidgets('por enlace directo deja a la Biblioteca debajo', (tester) async {
    await pump(tester);
    harness.goTo(RoutePaths.itemDetail('a'));
    await tester.pumpAndSettle();

    expect(inDetail('Una fuente'), findsOneWidget);

    await back(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
