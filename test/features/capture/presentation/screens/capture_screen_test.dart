import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
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

    testWidgets('lo guardado entra en la cola para que le traigan el '
        'contenido', (tester) async {
      // Guardar el enlace no es el final: lo que el usuario quiere es el
      // texto. Si la captura no encolara, el elemento quedaría esperando
      // para siempre sin que nada lo intente.
      await pumpCapture(tester);

      await tester.enterText(mainField(), 'https://ejemplo.org/un-articulo');
      await tester.tap(find.text(es.captureAction));
      await tester.pumpAndSettle();

      final saved = await savedItems();
      expect(harness.queue.enqueued, [saved.single.id]);
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
        'siempre no repite lo mismo', (tester) async {
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

      expect(tester.widget<TextField>(mainField()).controller?.text, '');
    });
  });

  group('soltar un archivo (drag-and-drop)', () {
    // `XFile` —de quien `DropItemFile` hereda— saca `.name` de la ruta y no
    // del parámetro `name:` al construirse con `.fromData()` en escritorio:
    // ver cross_file/src/types/io.dart. Un archivo de verdad soltado sí trae
    // una ruta real, así que en la app esto nunca pasa; acá hay que pasar el
    // nombre como ruta para que la ficha de prueba se comporte igual.
    DropItemFile fakeDroppedFile(String name, {Uint8List? bytes}) =>
        DropItemFile.fromData(bytes ?? Uint8List(0), path: name);

    testWidgets('deja el archivo elegido, igual que el selector', (
      tester,
    ) async {
      await pumpCapture(tester);

      await dropFiles(tester, [
        fakeDroppedFile(
          'foto.jpg',
          bytes: Uint8List.fromList('contenido'.codeUnits),
        ),
      ]);

      expect(find.text('foto.jpg'), findsOneWidget);
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
      expect(find.byType(OutlinedButton), findsOneWidget);
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
}
