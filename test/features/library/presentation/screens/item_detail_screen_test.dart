import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
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

  /// Guarda algo y devuelve su identificador.
  Future<String> captureAndGetId(String input, {String? note}) async {
    await harness.capture(input, note: note);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.first.id;
  }

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    await tester.pumpWidget(harness.wrap(ItemDetailScreen(itemId: id)));
    await tester.pumpAndSettle();
  }

  /// Deja un elemento como si traerle el contenido hubiera fallado.
  ///
  /// Pasa por el repositorio en vez de escribir la fila a mano: así el estado
  /// del que parte la prueba es uno que la app produce de verdad.
  Future<void> markFailed(String id) async {
    final repository = harness.container.read(libraryRepositoryProvider);
    final item = (await repository.findById(id)).getRight().toNullable()!;

    await repository.save(
      item.copyWith(processingState: ProcessingState.failed),
    );
  }

  group('contenido', () {
    testWidgets('muestra el texto guardado', (tester) async {
      final id = await captureAndGetId(
        'Un título\n\nY el cuerpo con la idea completa.',
      );

      await pumpDetail(tester, id);

      expect(find.textContaining('la idea completa'), findsOneWidget);
    });

    testWidgets('la nota del usuario se ve aparte del contenido', (
      tester,
    ) async {
      final id = await captureAndGetId(
        'Un artículo',
        note: 'me lo recomendó Ana',
      );

      await pumpDetail(tester, id);

      expect(find.text('me lo recomendó Ana'), findsOneWidget);
    });

    testWidgets('un elemento sin contenido todavía aclara que el enlace SÍ '
        'está guardado', (tester) async {
      // Una pantalla vacía se lee como "no se guardó nada", y el usuario
      // vuelve a capturarlo o deja de confiar en la app.
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailNoContentYet), findsOneWidget);
    });
  });

  group('procedencia', () {
    testWidgets('muestra de dónde salió y cuándo se guardó', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailProvenance), findsOneWidget);
      expect(find.text(es.sourceKindWebPage), findsOneWidget);
      expect(find.textContaining('https://ejemplo.org'), findsOneWidget);
    });

    testWidgets('una nota escrita a mano no inventa un enlace de origen', (
      tester,
    ) async {
      // El origen es la persona; mostrar un campo vacío sería peor que no
      // mostrarlo.
      final id = await captureAndGetId('una idea propia');

      await pumpDetail(tester, id);

      expect(find.text(es.detailCopyLink), findsNothing);
      expect(find.text(es.sourceKindNote), findsOneWidget);
    });

    testWidgets('el enlace se puede copiar al portapapeles', (tester) async {
      // Se copia en vez de abrirse: abrirlo exigiría un complemento nativo
      // que hoy no se puede probar acá, y un botón que a veces no hace nada
      // es peor que uno que siempre funciona.
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailCopyLink));
      await tester.pumpAndSettle();

      expect(copied, 'https://ejemplo.org/un-articulo');
      expect(find.text(es.detailLinkCopied), findsOneWidget);
    });
  });

  group('eliminar', () {
    testWidgets('pide confirmación antes de borrar algo irreversible', (
      tester,
    ) async {
      final id = await captureAndGetId('algo que se va a borrar');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text(es.detailDeleteConfirm), findsOneWidget);
    });

    testWidgets('cancelar no borra nada', (tester) async {
      final id = await captureAndGetId('algo que NO se va a borrar');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      expect(items, hasLength(1));
    });

    testWidgets('confirmar borra y vuelve a la biblioteca', (tester) async {
      final id = await captureAndGetId('algo que se va a borrar');

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.pushTo(RoutePaths.itemDetail(id));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.detailDelete).last);
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.text(es.emptyLibraryTitle), findsOneWidget);
    });
  });

  group('reintentar', () {
    testWidgets('algo que falló ofrece volver a intentarlo', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/se-cayó');
      await markFailed(id);

      await pumpDetail(tester, id);

      expect(find.text(es.detailExtractionFailed), findsOneWidget);
      expect(find.text(es.detailRetry), findsOneWidget);
    });

    testWidgets('el botón lo devuelve a la cola', (tester) async {
      // Reintentar es a pedido y no automático en cada arranque. Ese trato
      // solo se sostiene si el botón funciona: sin él, lo que falló una vez
      // quedaría muerto para siempre.
      final id = await captureAndGetId('https://ejemplo.org/se-cayó');
      await markFailed(id);

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailRetry));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, [id]);
    });

    testWidgets('algo que todavía está en camino NO ofrece reintento', (
      tester,
    ) async {
      // Un botón de reintentar sobre algo que está andando invita a
      // apretarlo, y lo único que haría es encolar de nuevo lo mismo.
      final id = await captureAndGetId('https://ejemplo.org/en-camino');

      await pumpDetail(tester, id);

      expect(find.text(es.detailRetry), findsNothing);
    });
  });
}
