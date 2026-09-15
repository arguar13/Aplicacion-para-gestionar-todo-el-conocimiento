import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/pdf_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/open_document_viewer.dart';

import '../../../../support/sample_files.dart';

/// Un `FileStore` que resuelve directo a un archivo real del disco, sin
/// pasar por el almacén de verdad de la app: lo único que necesita
/// `openDocumentViewer` de él es `resolve()`.
class _RealFileStore implements FileStore {
  _RealFileStore(this.path);

  final String path;

  @override
  Future<String> resolve(String relativePath) async => path;

  @override
  Future<void> delete(String relativePath) => throw UnimplementedError();
  @override
  Future<bool> exists(String relativePath) => throw UnimplementedError();
  @override
  Future<Uint8List?> read(String relativePath) => throw UnimplementedError();
  @override
  Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String id,
  }) => throw UnimplementedError();
}

/// Dónde está la librería nativa de PDFium.
///
/// `pdfrx` —el visor completo, a diferencia de `pdfrx_engine`— necesita el
/// mismo binario que `pdf_parser_test.dart`: sin `Pdfrx.pdfiumModulePath`
/// puesto, intentarlo en un `flutter test` sin motor gráfico no falla
/// rápido, sino que se queda esperando para siempre a un módulo nativo que
/// nunca aparece. Mismo motivo, mismo mecanismo de salto.
///
/// Sin ella, la prueba que la necesita se salta en vez de quedar en verde
/// sin haber probado nada. `export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"`
/// la trae.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('viewer_test');
    if (_pdfiumPath != null) Pdfrx.pdfiumModulePath = _pdfiumPath;

    // `pdfrx` pide un directorio de caché a `path_provider` al abrir un
    // documento, y ese plugin no tiene implementación nativa bajo
    // `flutter test`: sin este mock del canal, falla con
    // `MissingPluginException` en vez de mostrar el visor.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDir.path,
            'getApplicationSupportDirectory' => tempDir.path,
            'getApplicationDocumentsDirectory' => tempDir.path,
            _ => null,
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    // Mejor esfuerzo: `pdfrx` abre el PDF en un isolate aparte y esa
    // prueba no espera a que la pantalla se desmonte, así que el archivo
    // puede seguir abierto ahí un instante después de que termina el
    // cuerpo de la prueba. No es una limpieza que valga la pena bloquear
    // la prueba por ella.
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Ignorado a propósito, ver comentario arriba.
      }
    }
  });

  KnowledgeItem buildItem({
    required SourceKind kind,
    String? originalFilePath,
    List<Rendition> renditions = const [],
  }) {
    return KnowledgeItem(
      id: 'item-1',
      title: 'Un elemento',
      source: Source(
        id: 'source-1',
        kind: kind,
        capturedAt: DateTime(2026, 9, 14),
        originalFilePath: originalFilePath,
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 9, 14),
      updatedAt: DateTime(2026, 9, 14),
      renditions: renditions,
    );
  }

  Future<bool> pumpAndOpen(
    WidgetTester tester,
    KnowledgeItem item,
    String filePath,
  ) async {
    late bool result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileStoreProvider.overrideWithValue(_RealFileStore(filePath)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () async {
                  result = await openDocumentViewer(context, ref, item);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    // `runAsync`, no solo `pump()`: `openDocumentViewer` hace E/S de
    // archivo real (`_sniffFormat` abre y lee el archivo) y `pdfrx` abre el
    // documento en un isolate aparte —ambas cosas dependen de que el
    // sistema operativo entregue resultados de verdad, no del reloj
    // simulado que `pump()` avanza—. Si el `tap()` que dispara esa cadena
    // de `await`s queda afuera de `runAsync()`, el primer `await` sobre E/S
    // real nunca se resuelve y la prueba se cuelga hasta el timeout, sin
    // que ningún número de `pump()` adicionales cambie nada. Por eso todo
    // el intercambio —tocar el botón y los pulsos que siguen— va adentro
    // del mismo `runAsync`.
    await tester.runAsync(() async {
      await tester.tap(find.text('abrir'));
      // Pulsos sueltos y no `pumpAndSettle()`: las pantallas de destino
      // traen sus propias animaciones que no terminan de "asentarse" nunca
      // en un `flutter test` sin motor gráfico real —el cursor de un
      // `SelectableText`, el render progresivo de `pdfrx`—, y lo único que
      // hace falta comprobar acá es qué pantalla se abrió, no que termine
      // de dibujarse del todo.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    return result;
  }

  group('fuentes sin archivo que mostrar', () {
    for (final kind in [
      SourceKind.youtube,
      SourceKind.webPage,
      SourceKind.socialPost,
      SourceKind.manualNote,
    ]) {
      testWidgets('$kind no abre ningún visor', (tester) async {
        final item = buildItem(kind: kind);
        final handled = await pumpAndOpen(tester, item, '/no/existe');

        expect(handled, isFalse);
      });
    }

    testWidgets('sin ruta de archivo original, tampoco', (tester) async {
      final item = buildItem(kind: SourceKind.document);
      final handled = await pumpAndOpen(tester, item, '/no/existe');

      expect(handled, isFalse);
    });
  });

  group('documentos', () {
    testWidgets('un PDF abre el visor de páginas', (tester) async {
      final file = File('${tempDir.path}/archivo.pdf');
      // `runAsync`: la E/S de archivo real no avanza bajo el reloj
      // simulado de `testWidgets`, así se llame fuera de cualquier `pump()`.
      await tester.runAsync(
        () => file.writeAsBytes(buildPdf(pageTexts: ['Hola mundo'])),
      );

      final item = buildItem(
        kind: SourceKind.document,
        originalFilePath: 'originales/item-1/archivo.pdf',
      );
      final handled = await pumpAndOpen(tester, item, file.path);

      expect(handled, isTrue);
      expect(find.byType(PdfViewerScreen), findsOneWidget);
    }, skip: _pdfiumPath == null);

    testWidgets('un DOCX con texto ya extraído abre el lector de lectura', (
      tester,
    ) async {
      final file = File('${tempDir.path}/archivo.docx');
      await tester.runAsync(() => file.writeAsBytes(buildDocx()));

      final item = buildItem(
        kind: SourceKind.document,
        originalFilePath: 'originales/item-1/archivo.docx',
        renditions: [
          Rendition.text(
            id: 'rend-1',
            itemId: 'item-1',
            kind: RenditionKind.markdown,
            content: 'El contenido ya extraído del documento.',
            isPrimary: true,
            createdAt: DateTime(2026),
          ),
        ],
      );
      final handled = await pumpAndOpen(tester, item, file.path);

      expect(handled, isTrue);
      expect(find.byType(DocumentReaderScreen), findsOneWidget);
      expect(
        find.text('El contenido ya extraído del documento.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'un documento sin ninguna forma de texto no abre nada: no hay qué '
      'mostrar todavía',
      (tester) async {
        final file = File('${tempDir.path}/archivo.docx');
        await tester.runAsync(() => file.writeAsBytes(buildDocx()));

        final item = buildItem(
          kind: SourceKind.document,
          originalFilePath: 'originales/item-1/archivo.docx',
        );
        final handled = await pumpAndOpen(tester, item, file.path);

        expect(handled, isFalse);
      },
    );
  });
}
