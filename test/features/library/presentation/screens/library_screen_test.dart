import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/transform/presentation/screens/transcription_model_screen.dart';
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

    testWidgets('sin ninguna etiqueta puesta, no se reserva lugar para la '
        'fila que las filtra', (tester) async {
      // Mostrarla vacía sería ocupar espacio para decir "no hay nada por lo
      // que filtrar", que no es información que alguien necesite ver
      // siempre — y menos en una biblioteca recién estrenada. Se comprueba
      // el alto reservado en el `AppBar` y no solo la ausencia de chips: sin
      // etiquetas, la fila entera de por medio tampoco debería estar.
      await harness.capture('una nota sin etiquetas');
      await pumpLibrary(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom!.preferredSize.height, 168);
      expect(find.byIcon(Icons.label_outline), findsNothing);
    });

    testWidgets('con al menos una etiqueta, sí se reserva el lugar', (
      tester,
    ) async {
      await harness.capture('algo etiquetado');
      await harness.container
          .read(organizeRepositoryProvider)
          .getOrCreateTag('Cualquiera');
      await pumpLibrary(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom!.preferredSize.height, 216);
    });

    testWidgets('el filtro por etiqueta deja solo lo que corresponde', (
      tester,
    ) async {
      await harness.capture('un artículo de filosofía');
      await harness.capture('una nota sobre cocina');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final filosofico = items.firstWhere((i) => i.title.contains('filosofía'));
      final tag =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreateTag('Filosofía'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .save(filosofico.copyWith(tags: [tag]));

      await pumpLibrary(tester);
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(find.textContaining('filosofía'), findsOneWidget);
      expect(find.textContaining('cocina'), findsNothing);
    });

    testWidgets(
      'un filtro de etiqueta que no coincide con nada ofrece limpiarlo',
      (tester) async {
        await harness.capture('algo sin esa etiqueta');
        // La etiqueta existe pero nadie la tiene puesta: puede pasar
        // perfectamente —se creó para otra cosa, o se está probando el
        // filtro— y el chip para filtrar por ella igual aparece, porque sale
        // de todo el vocabulario y no de lo que hay visible en ese momento.
        await harness.container
            .read(organizeRepositoryProvider)
            .getOrCreateTag('Sin uso');

        await pumpLibrary(tester);
        await tester.tap(find.text('Sin uso'));
        await tester.pumpAndSettle();

        expect(find.text(es.libraryFilterEmpty), findsOneWidget);

        await tester.tap(find.text(es.libraryClearFilters));
        await tester.pumpAndSettle();

        expect(find.text('algo sin esa etiqueta'), findsOneWidget);
      },
    );

    testWidgets('crear un espacio y elegirlo deja solo lo que contiene', (
      tester,
    ) async {
      await harness.capture('un artículo de filosofía');
      await harness.capture('una nota sobre cocina');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final filosofico = items.firstWhere((i) => i.title.contains('filosofía'));
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Filosofía'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: filosofico.id, spaceId: space.id);

      await pumpLibrary(tester);
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(find.textContaining('filosofía'), findsOneWidget);
      expect(find.textContaining('cocina'), findsNothing);

      // Tocarlo de nuevo vuelve a "todos" — un espacio es una carpeta en la
      // que se entra y se sale, no un filtro que se combina con otros.
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cocina'), findsOneWidget);
    });

    testWidgets('el chip para crear un espacio nuevo siempre está', (
      tester,
    ) async {
      await harness.capture('una nota sin espacio');
      await pumpLibrary(tester);

      expect(find.text(es.spacesNewAction), findsOneWidget);
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

    testWidgets(
      'el botón de transcripción, desde ajustes, lleva a esa pantalla',
      (tester) async {
        // El acceso a la pantalla de transcripción se mudó de un ícono en
        // el AppBar de la biblioteca a la pantalla de Ajustes — ver la
        // decisión 22 en docs/arquitectura.md.
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text(es.libraryTranscriptionModelTooltip));
        await tester.pumpAndSettle();

        expect(find.byType(TranscriptionModelScreen), findsOneWidget);
      },
    );
  });

  group('selección múltiple', () {
    testWidgets('el ícono de seleccionar activa el modo, sin elegir nada '
        'todavía', (tester) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      expect(find.text(es.librarySelectedCount(0)), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('mantener presionada una fila entra al modo y la elige', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();

      expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
    });

    testWidgets(
      'en modo selección, tocar una fila alterna la casilla en vez de '
      'navegar',
      (tester) async {
        await harness.capture('Uno');
        await pumpLibrary(tester);

        await tester.tap(find.byIcon(Icons.checklist));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Uno'));
        await tester.pumpAndSettle();

        expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
        expect(find.byType(LibraryScreen), findsOneWidget);

        await tester.tap(find.text('Uno'));
        await tester.pumpAndSettle();

        expect(find.text(es.librarySelectedCount(0)), findsOneWidget);
      },
    );

    testWidgets('cancelar la selección vuelve a la barra normal', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryTitle), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);
    });

    testWidgets('sin nada elegido, exportar está deshabilitado', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.upload_file_outlined),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('exporta lo elegido para NotebookLM y confirma', (
      tester,
    ) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      harness.notebookLmDirectoryChooser.path = '/mi/carpeta';
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.upload_file_outlined));
      await tester.pumpAndSettle();

      // Los dos elegidos, más el índice.
      expect(harness.notebookLmDirectoryWriter.written, hasLength(3));
      expect(
        find.text(es.libraryExportPackageSaved(3, '/mi/carpeta')),
        findsOneWidget,
      );
      // Terminado el paquete, no queda nada seleccionado.
      expect(find.byIcon(Icons.checklist), findsOneWidget);
    });

    testWidgets(
      'cancelar el selector de carpeta no saca del modo de selección',
      (tester) async {
        await harness.capture('Uno');
        harness.notebookLmDirectoryChooser.path = null;
        await pumpLibrary(tester);

        await tester.longPress(find.text('Uno'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.upload_file_outlined));
        await tester.pumpAndSettle();

        expect(harness.notebookLmDirectoryWriter.written, isEmpty);
        expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
      },
    );
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
