import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const LibraryScreen()));
    await tester.pumpAndSettle();
  }

  group('estados vacíos', () {
    testWidgets('una biblioteca recién estrenada explica para qué sirve la '
        'app', (tester) async {
      await pumpLibrary(tester);

      expect(find.text(es.emptyLibraryTitle), findsOneWidget);
      expect(find.text(es.emptyLibraryMessage), findsOneWidget);
    });

    testWidgets('una búsqueda sin coincidencias dice QUÉ se buscó, no un '
        '"no hay nada" genérico', (tester) async {
      await harness.capture('una nota sobre filosofía');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'zoología');
      await tester.pumpAndSettle();

      expect(find.text(es.librarySearchEmpty('zoología')), findsOneWidget);
      // Y no se confunde con la biblioteca vacía: sí hay cosas guardadas.
      expect(find.text(es.emptyLibraryTitle), findsNothing);
    });

    testWidgets('unos filtros demasiado estrechos ofrecen la salida', (
      tester,
    ) async {
      // El usuario puede no darse cuenta de que dejó un filtro puesto; sin el
      // botón, la biblioteca parece vacía sin motivo.
      await harness.capture('una nota');
      await pumpLibrary(tester);

      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryFilterEmpty), findsOneWidget);
      expect(find.text(es.libraryClearFilters), findsOneWidget);
    });

    testWidgets('limpiar los filtros devuelve la lista', (tester) async {
      await harness.capture('una nota');
      await pumpLibrary(tester);

      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryClearFilters));
      await tester.pumpAndSettle();

      expect(find.text('una nota'), findsOneWidget);
    });
  });

  group('la lista', () {
    testWidgets('muestra lo guardado con su título', (tester) async {
      await harness.capture('La estructura de las revoluciones');
      await pumpLibrary(tester);

      expect(find.text('La estructura de las revoluciones'), findsOneWidget);
    });

    testWidgets('se actualiza sola cuando entra algo nuevo, sin recargar', (
      tester,
    ) async {
      // Es lo que hace que volver de la captura muestre el elemento ya
      // puesto, y lo que va a hacer aparecer una transcripción cuando
      // termine en segundo plano.
      await pumpLibrary(tester);
      expect(find.text('Recién llegado'), findsNothing);

      await harness.capture('Recién llegado');
      await tester.pumpAndSettle();

      expect(find.text('Recién llegado'), findsOneWidget);
    });

    testWidgets('marca lo que todavía está pendiente', (tester) async {
      await harness.capture('https://ejemplo.org/un-articulo-guardado');
      await pumpLibrary(tester);

      expect(find.text(es.processingPending), findsOneWidget);
    });

    testWidgets('no marca lo que ya está completo: una insignia de "listo" '
        'en cada fila sería ruido', (tester) async {
      await harness.capture('una nota que ya está completa');
      await pumpLibrary(tester);

      expect(find.text(es.processingPending), findsNothing);
      expect(find.text(es.processingFailed), findsNothing);
    });
  });

  group('buscar y filtrar', () {
    testWidgets('la búsqueda encuentra por contenido, no solo por título', (
      tester,
    ) async {
      await harness.capture('Un título cualquiera\n\nadentro habla de enzimas');
      await harness.capture('Otra nota sin relación');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'enzimas');
      await tester.pumpAndSettle();

      expect(find.text('Un título cualquiera'), findsOneWidget);
      expect(find.text('Otra nota sin relación'), findsNothing);
    });

    testWidgets('el filtro por tipo deja solo lo que corresponde', (
      tester,
    ) async {
      await harness.capture('una nota escrita');
      await harness.capture('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      await pumpLibrary(tester);

      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();

      expect(find.text('una nota escrita'), findsNothing);
      expect(find.textContaining('dQw4w9WgXcQ'), findsOneWidget);
    });
  });

  group('navegación', () {
    testWidgets('tocar una fila abre su detalle', (tester) async {
      await harness.capture('Algo para abrir');

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Algo para abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });

    testWidgets('el botón de guardar lleva a la captura', (tester) async {
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
    });
  });

  group('retomar lo que quedó a medias', () {
    testWidgets('abrir la biblioteca pide traer lo que quedó pendiente', (
      tester,
    ) async {
      // Alguien pudo capturar cinco enlaces sin conexión y cerrar la app. Al
      // volver, eso tiene que completarse solo: si la pantalla no se lo
      // pidiera a la cola, quedaría esperando para siempre y el usuario no
      // tendría forma de saber que hay que pedirlo.
      await harness.capture('https://ejemplo.org/quedó-pendiente');

      await pumpLibrary(tester);

      expect(harness.queue.pendingSweeps, 1);
    });
  });
}
