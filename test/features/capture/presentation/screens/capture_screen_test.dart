import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Monta la captura dentro del router real.
  ///
  /// No suelta en un MaterialApp: la pantalla vuelve atrás al guardar, y
  /// `context.pop()` sin router arriba falla con "No GoRouter found in
  /// context". Probarla fuera de su router dejaría justamente sin cubrir el
  /// final del flujo.
  Future<void> pumpCapture(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.capture);
    await tester.pumpAndSettle();
  }

  Finder mainField() => find.byType(TextField).first;

  Future<List<String>> savedTitles() async {
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.map((i) => i.title).toList();
  }

  group('reconocimiento en vivo', () {
    testWidgets('con el campo vacío no promete nada', (tester) async {
      await pumpCapture(tester);

      expect(find.textContaining('Se va a guardar'), findsNothing);
    });

    testWidgets('un texto suelto se va a guardar como nota', (tester) async {
      await pumpCapture(tester);

      await tester.enterText(mainField(), 'una idea que se me ocurrió');
      await tester.pumpAndSettle();

      expect(
        find.text(es.captureWillSaveAs(es.sourceKindNote)),
        findsOneWidget,
      );
    });

    testWidgets('un enlace se va a guardar como página web', (tester) async {
      await pumpCapture(tester);

      await tester.enterText(mainField(), 'https://ejemplo.org/un-articulo');
      await tester.pumpAndSettle();

      expect(
        find.text(es.captureWillSaveAs(es.sourceKindWebPage)),
        findsOneWidget,
      );
    });

    testWidgets('un enlace de YouTube se reconoce como tal, no como página '
        'web cualquiera', (tester) async {
      await pumpCapture(tester);

      await tester.enterText(
        mainField(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(es.captureWillSaveAs(es.sourceKindYoutube)),
        findsOneWidget,
      );
    });

    testWidgets('lo que se anuncia es lo que la app va a hacer de verdad: '
        'sale del mismo registro de adaptadores', (tester) async {
      // Si la pantalla tuviera su propia copia de las reglas, las dos
      // versiones terminarían discrepando y la promesa dejaría de cumplirse.
      await pumpCapture(tester);

      await tester.enterText(mainField(), 'https://youtu.be/dQw4w9WgXcQ');
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      expect(items.single.source.kind, SourceKind.youtube);
    });
  });

  group('guardar', () {
    testWidgets('una nota queda guardada con su contenido', (tester) async {
      await pumpCapture(tester);

      await tester.enterText(
        mainField(),
        'La estructura de las revoluciones\n\nhabla de paradigmas',
      );
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(await savedTitles(), ['La estructura de las revoluciones']);
    });

    testWidgets('un título escrito a mano gana sobre el deducido', (
      tester,
    ) async {
      await pumpCapture(tester);

      await tester.enterText(mainField(), 'https://ejemplo.org/algo');
      await tester.enterText(
        find.byType(TextFormField).first,
        'Mi propio título',
      );
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(await savedTitles(), ['Mi propio título']);
    });

    testWidgets('con el campo vacío avisa en vez de guardar algo en blanco', (
      tester,
    ) async {
      await pumpCapture(tester);

      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.text(es.captureEmptyError), findsOneWidget);
      expect(await savedTitles(), isEmpty);
    });

    testWidgets('al guardar vuelve a la biblioteca, con el elemento ya '
        'puesto', (tester) async {
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(mainField(), 'Algo recién capturado');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(CaptureScreen), findsNothing);
      // No hace falta recargar nada: la lista escucha los cambios de la base.
      expect(find.text('Algo recién capturado'), findsOneWidget);
    });
  });

  group('llegar por enlace directo', () {
    testWidgets('guardar lleva a la biblioteca en vez de reventar', (
      tester,
    ) async {
      // En web se puede abrir /capture escribiendo la dirección, sin pasar
      // por la biblioteca. Ahí no hay pila que desapilar, y un `pop` a secas
      // falla con "There is nothing to pop" justo después de haber guardado
      // bien — el peor momento posible para un error.
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      harness.goTo(RoutePaths.capture);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsOneWidget);

      await tester.enterText(mainField(), 'capturado desde un enlace directo');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(await savedTitles(), ['capturado desde un enlace directo']);
    });
  });
}
