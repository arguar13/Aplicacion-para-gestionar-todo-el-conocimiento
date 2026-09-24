import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/features/blocks/presentation/providers/note_template_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
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

  /// Elige un tipo en el primer paso, tocando su tarjeta.
  ///
  /// El selector es una grilla desplazable —hacen falta ocho tarjetas y un
  /// botón más en una pantalla que no siempre entra todo—, así que hace
  /// falta desplazarla a la vista antes de tocarla: una tarjeta más abajo
  /// en la grilla puede quedar fuera del viewport en una pantalla chica,
  /// igual que le pasaría a quien usa la app de verdad.
  Future<void> selectType(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder mainField() => find.byType(TextField).first;

  /// Una imagen chica de verdad, no bytes cualquiera: la tira de páginas
  /// escaneadas las muestra con `Image.memory`, y eso necesita poder
  /// decodificarlas — un byte inventado tira "Invalid image data" en vez de
  /// ejercitar la pantalla.
  Uint8List fakePhotoBytes() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

  /// Simula soltar [files] sobre la pantalla, llamando directo al callback
  /// que le pasa a `DropTarget`: no hay forma de fabricar un evento nativo
  /// de arrastre en una prueba, así que esto es lo más cerca que se puede
  /// llegar del gesto real.
  Future<void> dropFiles(WidgetTester tester, List<DropItem> files) async {
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    // `onDragDone` está tipado como `void Function(...)`, aunque lo que hay
    // detrás sea async: no se puede esperar la llamada en sí, pero
    // `pumpAndSettle` sí espera lo que quede pendiente.
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: files,
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<KnowledgeItem>> savedItems() async =>
      (await harness.container
              .read(libraryRepositoryProvider)
              .list(const LibraryQuery()))
          .getRight()
          .toNullable()!;

  Future<List<String>> savedTitles() async =>
      (await savedItems()).map((i) => i.title).toList();

  group('selector de tipo', () {
    testWidgets('arranca mostrando los botones, sin ningún campo todavía', (
      tester,
    ) async {
      await pumpCapture(tester);

      expect(find.text(es.captureTypePrompt), findsOneWidget);
      expect(find.text(es.captureTypeVideo), findsOneWidget);
      expect(find.text(es.captureTypePost), findsOneWidget);
      expect(find.text(es.captureTypeWebPage), findsOneWidget);
      expect(find.text(es.captureTypeBook), findsOneWidget);
      expect(find.text(es.captureTypeImage), findsOneWidget);
      expect(find.text(es.captureTypeAudio), findsOneWidget);
      expect(find.text(es.captureTypePasteText), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('elegir "Video" muestra un campo de enlace con su propia '
        'ayuda', (tester) async {
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeVideo);

      expect(mainField(), findsOneWidget);
      expect(find.text(es.captureTypeVideoHint), findsOneWidget);
    });

    testWidgets(
      'el paso "Video" también ofrece elegir un video del dispositivo, '
      'sin abrir el selector solo por entrar al paso',
      (tester) async {
        await pumpCapture(tester);

        await selectType(tester, es.captureTypeVideo);

        // A diferencia de "Libro" o "Imagen", elegir "Video" no dispara el
        // selector de archivos solo: la mayoría de las veces lo que se va
        // a pegar es un enlace, así que el campo de texto sigue siendo lo
        // primero que se ve.
        expect(mainField(), findsOneWidget);
        expect(find.text(es.captureChooseVideoFileAction), findsOneWidget);
      },
    );

    testWidgets(
      'elegir un video del dispositivo en el paso "Video" lo deja elegido, '
      'igual que un enlace',
      (tester) async {
        harness = await LibraryHarness.create(
          chosenFile: CapturedFile(
            name: 'cumpleaños.mp4',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
        await pumpCapture(tester);

        await selectType(tester, es.captureTypeVideo);
        await tester.tap(find.text(es.captureChooseVideoFileAction));
        await tester.pumpAndSettle();

        expect(find.text('cumpleaños.mp4'), findsOneWidget);
      },
    );

    testWidgets('elegir "Página web" muestra el mismo tipo de campo, con su '
        'propia ayuda', (tester) async {
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeWebPage);

      expect(mainField(), findsOneWidget);
      expect(find.text(es.captureTypeWebPageHint), findsOneWidget);
    });

    testWidgets('"Cambiar tipo" vuelve al selector y limpia lo escrito', (
      tester,
    ) async {
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeVideo);
      await tester.enterText(mainField(), 'https://youtu.be/dQw4w9WgXcQ');
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.captureChangeType));
      await tester.pumpAndSettle();

      expect(find.text(es.captureTypePrompt), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Y si se vuelve a elegir el mismo tipo, no quedó nada de antes.
      await selectType(tester, es.captureTypeVideo);
      expect(tester.widget<TextField>(mainField()).controller?.text, '');
    });

    testWidgets('"Texto para pegar" muestra el cuadro grande de siempre', (
      tester,
    ) async {
      await pumpCapture(tester);

      await selectType(tester, es.captureTypePasteText);

      expect(find.text(es.captureTypePasteTextHint), findsOneWidget);
    });

    testWidgets(
      'elegir "Libro o documento" abre el selector de archivos solo',
      (tester) async {
        harness = await LibraryHarness.create(
          chosenFile: CapturedFile(
            name: 'manual.pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
        await pumpCapture(tester);

        await selectType(tester, es.captureTypeBook);

        // No hace falta tocar nada más: elegir el tipo ya disparó el
        // selector, y el archivo elegido —de mentira, puesto en el
        // harness— queda mostrado directo.
        expect(find.text('manual.pdf'), findsOneWidget);
      },
    );

    testWidgets('un archivo demasiado pesado avisa en vez de quedar elegido', (
      tester,
    ) async {
      // El selector de mentira lanza esto directo, sin devolver ningún
      // archivo: es lo que hace `SystemFileChooser` de verdad cuando el
      // tamaño que ya informa el sistema —sin haber leído nada todavía—
      // pasa el máximo. Ver `FileTooLargeException`.
      harness = await LibraryHarness.create(
        fileChooserError: const FileTooLargeException(),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeBook);

      expect(
        find.text(
          es.globalErrorFileTooLarge(
            (CapturedFile.maxBytes / (1024 * 1024)).round().toString(),
          ),
        ),
        findsOneWidget,
      );
      // Ningún archivo quedó elegido: sigue ofreciendo el botón de
      // siempre, no la tarjeta de "archivo elegido".
      expect(find.text(es.captureChooseFileAction), findsOneWidget);
    });
  });

  group('cámara', () {
    testWidgets('en una plataforma con cámara de verdad, el selector ofrece la '
        'tarjeta', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpCapture(tester);

      expect(find.text(es.captureTypeCamera), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'en escritorio, sin cámara de verdad detrás, la tarjeta no se ofrece',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        await pumpCapture(tester);

        expect(find.text(es.captureTypeCamera), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('elegir "Cámara" abre la cámara sola, sin tocar nada más', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      harness = await LibraryHarness.create(
        chosenPhoto: CapturedFile(name: 'foto.jpg', bytes: fakePhotoBytes()),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeCamera);

      expect(find.text(es.captureScanPagesCount(1)), findsOneWidget);
      expect(harness.cameraChooser.timesOpened, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'cerrar la cámara sin sacar ninguna foto ofrece volver a intentar',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await pumpCapture(tester);

        await selectType(tester, es.captureTypeCamera);

        expect(find.text(es.captureTakePhotoAction), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('sin permiso de cámara, avisa en vez de quedarse sin decir '
        'nada', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      harness = await LibraryHarness.create(
        cameraChooserError: const CameraAccessDeniedException(),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeCamera);

      expect(find.text(es.captureCameraAccessDenied), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('una sola foto sacada con la cámara se guarda como imagen', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      harness = await LibraryHarness.create(
        chosenPhoto: CapturedFile(name: 'pizarra.jpg', bytes: fakePhotoBytes()),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeCamera);
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      // El título provisional sale del nombre provisorio de una foto sola
      // —ver `capturePhotoFileName`—, no del que traiga la cámara: una vez
      // que se guardan solo los bytes en `_scannedPages`, ese nombre
      // original ya no está.
      expect(await savedTitles(), [es.capturePhotoFileName]);

      final saved = (await savedItems()).single;
      expect(saved.source.kind, SourceKind.image);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('sacar una segunda foto la suma a la lista, no la reemplaza', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      harness = await LibraryHarness.create(
        chosenPhoto: CapturedFile(name: 'pagina.jpg', bytes: fakePhotoBytes()),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeCamera);
      await tester.tap(find.byTooltip(es.captureScanAddPage));
      await tester.pumpAndSettle();

      expect(find.text(es.captureScanPagesCount(2)), findsOneWidget);
      expect(harness.cameraChooser.timesOpened, 2);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('quitar una página la saca de la lista', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      harness = await LibraryHarness.create(
        chosenPhoto: CapturedFile(name: 'pagina.jpg', bytes: fakePhotoBytes()),
      );
      await pumpCapture(tester);

      await selectType(tester, es.captureTypeCamera);
      await tester.tap(find.byTooltip(es.captureScanAddPage));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.captureScanRemovePage).first);
      await tester.pumpAndSettle();

      expect(find.text(es.captureScanPagesCount(1)), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'dos o más páginas se combinan en un solo documento al guardar',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        harness = await LibraryHarness.create(
          chosenPhoto: CapturedFile(
            name: 'pagina.jpg',
            bytes: fakePhotoBytes(),
          ),
        );
        await pumpCapture(tester);

        await selectType(tester, es.captureTypeCamera);
        await tester.tap(find.byTooltip(es.captureScanAddPage));
        await tester.pumpAndSettle();
        await tester.tap(find.text(es.captureAction));
        await tester.pumpAndSettle();

        // Un solo elemento, no dos: las dos fotos se combinaron en un único
        // documento en vez de guardarse como dos capturas sueltas.
        expect(await savedTitles(), [es.captureScanFileName]);
        final saved = (await savedItems()).single;
        expect(saved.source.kind, SourceKind.document);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('reconocimiento en vivo', () {
    testWidgets('con el campo vacío no promete nada', (tester) async {
      await pumpCapture(tester);
      await selectType(tester, es.captureTypePasteText);

      expect(find.textContaining('Se va a guardar'), findsNothing);
    });

    testWidgets('un texto suelto se va a guardar como nota', (tester) async {
      await pumpCapture(tester);
      await selectType(tester, es.captureTypePasteText);

      await tester.enterText(mainField(), 'una idea que se me ocurrió');
      await tester.pumpAndSettle();

      expect(
        find.text(es.captureWillSaveAs(es.sourceKindNote)),
        findsOneWidget,
      );
    });

    testWidgets('un enlace se va a guardar como página web', (tester) async {
      await pumpCapture(tester);
      await selectType(tester, es.captureTypeWebPage);

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
      await selectType(tester, es.captureTypeVideo);

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
      await selectType(tester, es.captureTypeVideo);

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
      await selectType(tester, es.captureTypePasteText);

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
      await selectType(tester, es.captureTypeWebPage);

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
      await selectType(tester, es.captureTypePasteText);

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
      await selectType(tester, es.captureTypePasteText);

      await tester.enterText(mainField(), 'Algo recién capturado');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(CaptureScreen), findsNothing);
      // No hace falta recargar nada: la lista escucha los cambios de la base.
      expect(find.text('Algo recién capturado'), findsOneWidget);
    });

    testWidgets('lo guardado entra en la cola para que le traigan el '
        'contenido', (tester) async {
      // Guardar el enlace no es el final: lo que el usuario quiere es el
      // texto. Si la captura no encolara, el elemento quedaría esperando
      // para siempre sin que nada lo intente.
      await pumpCapture(tester);
      await selectType(tester, es.captureTypeWebPage);

      await tester.enterText(mainField(), 'https://ejemplo.org/un-articulo');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      final saved = await savedItems();
      expect(harness.queue.enqueued, [saved.single.id]);
    });
  });

  group('deduplicación', () {
    const existingText = 'Un texto que ya está guardado desde antes';

    /// Guarda una nota con [text] y le pone a mano el `dedupHash`/`simhash`
    /// que le correspondería —igual que calculará de verdad el generador
    /// de sugerencias (F7, C8/C9), que todavía no existe en esta ronda—,
    /// para que haya algo con qué comparar antes de guardar.
    Future<String> seedExistingNote(String text) async {
      await harness.capture(text);
      final id = (await savedItems()).single.id;

      final normalized = normalizeForDedup(text);
      await (harness.database.update(
        harness.database.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).write(
        KnowledgeNotesCompanion(
          dedupHash: Value(contentHashOf(normalized)),
          simhash: Value(simhashOf(normalized)),
        ),
      );

      return id;
    }

    testWidgets('sin ninguna coincidencia, guarda normal sin ningún '
        'diálogo', (tester) async {
      await pumpCapture(tester);
      await selectType(tester, es.captureTypePasteText);

      await tester.enterText(mainField(), 'Un texto que nadie más tiene');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.text(es.duplicateWarningTitleExact), findsNothing);
      expect(await savedTitles(), ['Un texto que nadie más tiene']);
    });

    testWidgets(
      'con una coincidencia exacta, elegir "Fusionar" deja un solo ítem '
      'con las dos renditions de texto',
      (tester) async {
        final existingId = await seedExistingNote(existingText);

        await pumpCapture(tester);
        await selectType(tester, es.captureTypePasteText);
        await tester.enterText(mainField(), existingText);
        await tester.tap(find.text(es.captureAction));
        await tester.pumpAndSettle();

        expect(find.text(es.duplicateWarningTitleExact), findsOneWidget);
        await tester.tap(find.text(es.duplicateWarningMerge));
        await tester.pumpAndSettle();

        final items = await savedItems();
        expect(items, hasLength(1));
        expect(items.single.id, existingId);
        expect(
          items.single.renditions.whereType<TextRendition>(),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'con una coincidencia, elegir "Guardar aparte" dos ítems separados, '
      'ninguno tocado',
      (tester) async {
        final existingId = await seedExistingNote(existingText);

        await pumpCapture(tester);
        await selectType(tester, es.captureTypePasteText);
        await tester.enterText(mainField(), existingText);
        await tester.tap(find.text(es.captureAction));
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.duplicateWarningKeepSeparate));
        await tester.pumpAndSettle();

        final items = await savedItems();
        expect(items, hasLength(2));
        expect(items.map((i) => i.id), contains(existingId));
        expect(
          items.every(
            (i) => i.renditions.whereType<TextRendition>().length == 1,
          ),
          isTrue,
        );
      },
    );
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
      await selectType(tester, es.captureTypePasteText);

      await tester.enterText(mainField(), 'capturado desde un enlace directo');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(await savedTitles(), ['capturado desde un enlace directo']);
    });
  });

  group('contenido compartido desde otra app', () {
    testWidgets('lo que trajo el arranque deja la captura precargada, '
        'lista para revisar', (tester) async {
      harness = await LibraryHarness.create(
        initialSharedContent: [
          const CaptureRequest.text(rawInput: 'https://ejemplo.org/algo'),
        ],
      );

      // El guard lleva directo a la captura sin que nadie navegue: ver
      // `_redirect` en app_router.dart.
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
      // Llega ya con el tipo adivinado —página web—, sin pasar por el
      // selector.
      expect(find.text('https://ejemplo.org/algo'), findsOneWidget);
    });

    testWidgets('un archivo compartido queda elegido, sin pasar por el '
        'selector', (tester) async {
      harness = await LibraryHarness.create(
        initialSharedContent: [
          CaptureRequest.file(
            file: CapturedFile(
              name: 'foto.jpg',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ],
      );

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(find.text('foto.jpg'), findsOneWidget);
    });

    testWidgets('lo que llega con la app ya abierta también lleva a la '
        'captura', (tester) async {
      harness = await LibraryHarness.create();
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      harness.sharedContent.add([
        const CaptureRequest.text(rawInput: 'llegó con la app abierta'),
      ]);
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(find.text('llegó con la app abierta'), findsOneWidget);
    });

    testWidgets('se ofrece una sola vez: entrar de nuevo por el botón de '
        'siempre vuelve a pedir el tipo', (tester) async {
      harness = await LibraryHarness.create(
        initialSharedContent: [
          const CaptureRequest.text(rawInput: 'una nota compartida'),
        ],
      );

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      // Se vacía la cola guardando lo que llegó.
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      harness.pushTo(RoutePaths.capture);
      await tester.pumpAndSettle();

      // Sin nada precargado, vuelve a arrancar en el selector de tipo.
      expect(find.text(es.captureTypePrompt), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('soltar un archivo (drag-and-drop)', () {
    // `XFile` —de quien `DropItemFile` hereda— saca `.name` de la ruta y no
    // del parámetro `name:` al construirse con `.fromData()` en escritorio:
    // ver cross_file/src/types/io.dart. Un archivo de verdad soltado sí trae
    // una ruta real, así que en la app esto nunca pasa; acá hay que pasar el
    // nombre como ruta para que la ficha de prueba se comporte igual.
    DropItemFile fakeDroppedFile(
      String name, {
      Uint8List? bytes,
      int? length,
    }) => DropItemFile.fromData(
      bytes ?? Uint8List(0),
      path: name,
      length: length,
    );

    testWidgets('deja el archivo elegido, igual que el selector, sin pasar '
        'por el selector de tipo', (tester) async {
      await pumpCapture(tester);

      await dropFiles(tester, [
        fakeDroppedFile(
          'foto.jpg',
          bytes: Uint8List.fromList('contenido'.codeUnits),
        ),
      ]);

      expect(find.text('foto.jpg'), findsOneWidget);
    });

    testWidgets('soltar un archivo demasiado pesado avisa, sin leerlo', (
      tester,
    ) async {
      await pumpCapture(tester);

      // `length:` simula el tamaño que ya informa el sistema al arrastrar
      // —el mismo que consulta `XFile.length()` sin abrir el archivo—,
      // sin tener que reservar de verdad los megas del límite en la
      // prueba.
      await dropFiles(tester, [
        fakeDroppedFile('enorme.pdf', length: CapturedFile.maxBytes + 1),
      ]);

      expect(
        find.text(
          es.globalErrorFileTooLarge(
            (CapturedFile.maxBytes / (1024 * 1024)).round().toString(),
          ),
        ),
        findsOneWidget,
      );
      // Sin ningún archivo elegido, sigue en el selector de tipo.
      expect(find.text(es.captureTypePrompt), findsOneWidget);
    });

    testWidgets('reemplaza el archivo ya elegido, no lo duplica', (
      tester,
    ) async {
      await pumpCapture(tester);

      await dropFiles(tester, [fakeDroppedFile('primero.pdf')]);
      expect(find.text('primero.pdf'), findsOneWidget);

      await dropFiles(tester, [fakeDroppedFile('segundo.pdf')]);

      expect(find.text('primero.pdf'), findsNothing);
      expect(find.text('segundo.pdf'), findsOneWidget);
    });

    testWidgets('soltar más de un archivo a la vez avisa, sin elegir '
        'ninguno', (tester) async {
      await pumpCapture(tester);

      await dropFiles(tester, [
        fakeDroppedFile('uno.jpg'),
        fakeDroppedFile('dos.jpg'),
      ]);

      expect(find.text(es.captureDropSingleFileOnly), findsOneWidget);
      // Ningún archivo quedó elegido: el selector de tipo sigue ahí, tal
      // cual antes del intento de soltar dos a la vez.
      expect(find.text(es.captureTypePrompt), findsOneWidget);
    });

    testWidgets('soltar una carpeta avisa igual que soltar varios archivos', (
      tester,
    ) async {
      await pumpCapture(tester);

      await dropFiles(tester, [DropItemDirectory('/una/carpeta', const [])]);

      expect(find.text(es.captureDropSingleFileOnly), findsOneWidget);
    });

    testWidgets('el borde solo aparece mientras algo está arrastrado '
        'encima', (tester) async {
      await pumpCapture(tester);

      Border? borderOf() =>
          (tester
                          .widget<AnimatedContainer>(
                            find.byType(AnimatedContainer),
                          )
                          .decoration!
                      as BoxDecoration)
                  .border
              as Border?;

      expect(borderOf()!.top.color, Colors.transparent);

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragEntered!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();

      expect(borderOf()!.top.color, isNot(Colors.transparent));

      dropTarget.onDragExited!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();

      expect(borderOf()!.top.color, Colors.transparent);
    });
  });

  group('elegir plantilla al crear una nota (F16)', () {
    /// Crea una plantilla y monta la captura.
    Future<void> pumpCaptureWithTemplate(
      WidgetTester tester, {
      required String name,
      List<ContentBlock> blocks = const [],
    }) async {
      await harness.container
          .read(noteTemplateRepositoryProvider)
          .create(name: name, blocks: blocks, properties: const []);
      await pumpCapture(tester);
    }

    /// El botón de plantillas, al final de una lista larga, no está montado
    /// hasta que se desplaza hasta él —`ListView` es perezoso incluso con
    /// una lista fija de hijos—: `scrollUntilVisible`, no `ensureVisible`,
    /// que exige que el elemento ya exista.
    Future<void> tapChooseTemplate(WidgetTester tester) async {
      final finder = find.text(es.blocksChooseTemplate);
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('sin ninguna plantilla guardada, el botón no aparece', (
      tester,
    ) async {
      await pumpCapture(tester);

      expect(find.text(es.blocksChooseTemplate), findsNothing);
    });

    testWidgets('elegir una plantilla precarga sus bloques en el editor', (
      tester,
    ) async {
      await pumpCaptureWithTemplate(
        tester,
        name: 'Plantilla de reunión',
        blocks: const [ContentBlock.heading(text: 'Temario')],
      );
      await tapChooseTemplate(tester);
      await tester.tap(find.text('Plantilla de reunión'));
      await tester.pumpAndSettle();

      expect(find.text('Temario'), findsOneWidget);
    });

    testWidgets('elegir «nota en blanco» abre el editor vacío', (tester) async {
      await pumpCaptureWithTemplate(tester, name: 'Plantilla');
      await tapChooseTemplate(tester);
      await tester.tap(find.text(es.blocksNewBlank));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, es.blocksTitleHint),
        findsOneWidget,
      );
    });

    testWidgets('cerrar la hoja sin elegir no abre ningún editor', (
      tester,
    ) async {
      await pumpCaptureWithTemplate(tester, name: 'Plantilla');
      await tapChooseTemplate(tester);
      // Cierra la hoja tocando afuera, sin elegir nada.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, es.blocksTitleHint), findsNothing);
    });
  });
}
