import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/pdf_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/sample_files.dart';

/// Siempre el mismo visor, sin tocar ningún archivo.
class _FixedResolver implements FileViewerResolver {
  _FixedResolver(this.viewer);

  final ResolvedViewer viewer;

  @override
  Future<ResolvedViewer> resolve(KnowledgeItem item) async => viewer;
}

/// Dónde está la librería nativa de PDFium — ver
/// `open_document_viewer_test.dart`, que tiene el mismo requisito por el
/// mismo motivo.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

/// La vista previa de un documento de texto en el detalle es su primera
/// página, fija (F39): arrastrar encima desplaza el detalle —no el
/// documento—, y tocarla abre el lector a pantalla completa. Para cada
/// formato: un PDF, un DOCX o un EPUB (Markdown) y un `.txt` (texto tal cual).
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 23, 10);

  const pageOne = 'PRIMERA hoja del libro, la que se ve siempre.';
  const pageTwo = 'SEGUNDA hoja, que no se ve sin entrar al libro.';
  // Una hoja de verdad es larga: lo que no entra en la primera no se ve.
  final longPageOne = '$pageOne ${'Relleno de la primera hoja. ' * 120}';
  final content = '$longPageOne\n\n---\n\n$pageTwo';

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fixed_preview_test');
    if (_pdfiumPath != null) Pdfrx.pdfiumModulePath = _pdfiumPath;
    // `pdfrx` pide un directorio de caché a `path_provider` al abrir un
    // documento: ver `open_document_viewer_test.dart`.
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
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Mejor esfuerzo: `pdfrx` puede tener el archivo abierto un instante.
      }
    }
  });

  /// Deja que termine lo que tarda de verdad —abrir y renderizar un PDF—.
  Future<void> settle(WidgetTester tester, {bool real = false}) async {
    if (!real) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 50));
        final preview = find.byType(PdfFirstPagePreview);
        // Ya se vio la página, o ya se supo que no se puede abrir.
        if (find
                .descendant(of: preview, matching: find.byType(RawImage))
                .evaluate()
                .isNotEmpty ||
            find
                .descendant(
                  of: preview,
                  matching: find.byIcon(Icons.picture_as_pdf_outlined),
                )
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
    });
    await tester.pump();
  }

  /// El detalle de un documento cuya vista previa es [viewer], en una
  /// pantalla baja: el contenido de abajo no entra y hay que desplazarlo.
  Future<void> pumpDetail(
    WidgetTester tester,
    ResolvedViewer viewer, {
    String file = 'original.docx',
  }) async {
    final harness = await LibraryHarness.create(
      extraOverrides: [
        fileViewerResolverProvider.overrideWithValue(_FixedResolver(viewer)),
      ],
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'item-1',
            title: 'Un libro',
            source: Source(
              id: 'src-1',
              kind: SourceKind.document,
              capturedAt: now,
              originalFilePath: file,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'r1',
                itemId: 'item-1',
                kind: RenditionKind.markdown,
                content: content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    tester.view.physicalSize = const Size(800, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'item-1')),
    );
    await settle(tester);
  }

  /// Cuánto se desplazó el detalle.
  double detailOffset(WidgetTester tester) {
    final scroll = find
        .descendant(
          of: find.byType(ItemDetailScreen),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    return tester.widget<SingleChildScrollView>(scroll).controller!.offset;
  }

  /// Un arrastre vertical, de abajo hacia arriba, que empieza en [from] —sale
  /// del dedo, no de un widget— y pasa por encima de la vista previa.
  Future<void> dragUp(WidgetTester tester, Offset from) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Un punto de la vista previa que no es el botón del centro.
  Offset awayFromButton(WidgetTester tester, Finder preview) {
    final rect = tester.getRect(preview);
    return rect.topCenter + const Offset(0, 40);
  }

  /// El botón «Leer como libro», a la vista: en una pantalla baja queda
  /// debajo de lo que le precede.
  Future<Finder> bookButton(WidgetTester tester) async {
    final button = find.byKey(const Key('embedded-viewer-read-as-book'));
    await tester.ensureVisible(button);
    await tester.pump();
    return button;
  }

  final readerView = find.byType(DocumentReaderView);

  group('un documento de texto: DOCX, EPUB, Markdown', () {
    final textPreview = find.byType(DocumentFirstPagePreview);

    testWidgets('la vista previa es la primera página, quieta: no es el '
        'lector, ni tiene nada que se desplace', (tester) async {
      await pumpDetail(tester, TextResolvedViewer(content));

      expect(textPreview, findsOneWidget);
      expect(readerView, findsNothing);
      expect(
        find.textContaining('PRIMERA hoja', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('SEGUNDA hoja', findRichText: true),
        findsNothing,
      );
      expect(
        find.descendant(of: textPreview, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        find.descendant(of: textPreview, matching: find.byType(PageView)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: textPreview,
          matching: find.text(es.detailReadAsBook),
        ),
        findsNothing,
      );
      expect(find.text(es.detailReadAsBook), findsOneWidget);
    });

    testWidgets('lleva el texto que se estudia, para pintar lo estudiado y '
        'lo resaltado', (tester) async {
      await pumpDetail(
        tester,
        TextResolvedViewer(
          content,
          study: (
            itemId: 'item-1',
            renditionId: 'r1',
            content: content,
            markdown: true,
          ),
        ),
      );

      expect(
        tester.widget<DocumentFirstPagePreview>(textPreview).study?.renditionId,
        'r1',
      );
    });

    testWidgets('arrastrar sobre ella desplaza el detalle, y la primera '
        'página sigue siendo la primera', (tester) async {
      await pumpDetail(tester, TextResolvedViewer(content));
      expect(detailOffset(tester), 0);
      final preview = find.byKey(const Key('document-first-page-preview'));

      await dragUp(tester, awayFromButton(tester, preview));

      expect(detailOffset(tester), greaterThan(40));
      expect(
        find.textContaining('PRIMERA hoja', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('SEGUNDA hoja', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('arrastrar empezando sobre «Leer como libro» también '
        'desplaza el detalle', (tester) async {
      await pumpDetail(tester, TextResolvedViewer(content));

      final button = await bookButton(tester);
      final before = detailOffset(tester);

      await dragUp(tester, tester.getCenter(button));

      expect(detailOffset(tester), greaterThan(before + 40));
      expect(find.text(es.detailReadAsBook), findsOneWidget);
    });

    testWidgets('tocar la página abre el lector a pantalla completa', (
      tester,
    ) async {
      await pumpDetail(tester, TextResolvedViewer(content));

      await tester.tapAt(
        awayFromButton(
          tester,
          find.byKey(const Key('document-first-page-preview')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocumentReaderScreen), findsOneWidget);
    });

    testWidgets('«Leer como libro» abre el lector a pantalla completa', (
      tester,
    ) async {
      await pumpDetail(tester, TextResolvedViewer(content));

      await tester.tap(await bookButton(tester));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentReaderScreen), findsOneWidget);
    });
  });

  group('un texto plano: .txt', () {
    final plain = TextResolvedViewer(content, markdown: false);

    testWidgets('también es la primera página, quieta', (tester) async {
      await pumpDetail(tester, plain, file: 'original.txt');

      expect(find.byType(DocumentFirstPagePreview), findsOneWidget);
      expect(readerView, findsNothing);
      expect(
        find.textContaining('PRIMERA hoja', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('SEGUNDA hoja', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('arrastrar sobre ella desplaza el detalle', (tester) async {
      await pumpDetail(tester, plain, file: 'original.txt');
      final preview = find.byKey(const Key('document-first-page-preview'));

      await dragUp(tester, awayFromButton(tester, preview));

      expect(detailOffset(tester), greaterThan(40));
      expect(
        find.textContaining('PRIMERA hoja', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('tocarla abre el lector', (tester) async {
      await pumpDetail(tester, plain, file: 'original.txt');

      await tester.tapAt(
        awayFromButton(
          tester,
          find.byKey(const Key('document-first-page-preview')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocumentReaderScreen), findsOneWidget);
    });
  });

  group('un PDF', () {
    final pdfPreview = find.byType(PdfFirstPagePreview);

    /// Si la página 1 lleva encima la capa de lo estudiado.
    bool paintsStudy(WidgetTester tester) => find
        .descendant(of: pdfPreview, matching: find.byType(CustomPaint))
        .evaluate()
        .any(
          (e) =>
              (e.widget as CustomPaint).painter.runtimeType.toString() ==
              '_StudyPainter',
        );

    Future<ResolvedViewer> pdfViewer(
      WidgetTester tester, {
      bool withText = false,
    }) async {
      final file = File('${tempDir.path}/archivo.pdf');
      await tester.runAsync(
        () => file.writeAsBytes(
          buildPdf(pageTexts: ['PRIMERA hoja del PDF', 'SEGUNDA hoja del PDF']),
        ),
      );
      return PdfResolvedViewer(
        file.path,
        text: withText
            ? (
                itemId: 'item-1',
                renditionId: 'r1',
                content: 'PRIMERA hoja del PDF',
                markdown: false,
              )
            : null,
      );
    }

    testWidgets('la vista previa es la página 1 como imagen: ni visor ni '
        'nada que se desplace', (tester) async {
      await pumpDetail(tester, await pdfViewer(tester), file: 'a.pdf');
      await settle(tester, real: true);

      expect(pdfPreview, findsOneWidget);
      expect(find.byType(PdfViewer), findsNothing);
      expect(find.byType(PdfViewerView), findsNothing);
      final page = tester.widget<PdfPageView>(find.byType(PdfPageView));
      expect(page.pageNumber, 1);
      expect(
        find.descendant(of: pdfPreview, matching: find.byType(RawImage)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pdfPreview, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(find.text(es.detailReadAsBook), findsOneWidget);
      // Sin texto extraído no hay qué pintar encima.
      expect(paintsStudy(tester), isFalse);
    }, skip: _pdfiumPath == null);

    testWidgets('con su texto extraído, lo estudiado se pinta sobre la '
        'página 1', (tester) async {
      await pumpDetail(
        tester,
        await pdfViewer(tester, withText: true),
        file: 'a.pdf',
      );
      await settle(tester, real: true);

      expect(paintsStudy(tester), isTrue);
      expect(
        tester.widget<PdfFirstPagePreview>(pdfPreview).text?.renditionId,
        'r1',
      );
    }, skip: _pdfiumPath == null);

    testWidgets('arrastrar sobre la página desplaza el detalle, y sigue en '
        'la página 1', (tester) async {
      await pumpDetail(tester, await pdfViewer(tester), file: 'a.pdf');
      await settle(tester, real: true);
      final preview = find.byKey(const Key('pdf-first-page-preview'));

      await dragUp(tester, awayFromButton(tester, preview));

      expect(detailOffset(tester), greaterThan(40));
      expect(
        tester.widget<PdfPageView>(find.byType(PdfPageView)).pageNumber,
        1,
      );
      expect(find.byType(PdfViewer), findsNothing);
    }, skip: _pdfiumPath == null);

    testWidgets('arrastrar empezando sobre «Leer como libro» también '
        'desplaza el detalle', (tester) async {
      await pumpDetail(tester, await pdfViewer(tester), file: 'a.pdf');
      await settle(tester, real: true);

      final button = await bookButton(tester);
      final before = detailOffset(tester);

      await dragUp(tester, tester.getCenter(button));

      expect(detailOffset(tester), greaterThan(before + 40));
    }, skip: _pdfiumPath == null);

    testWidgets('tocar la página abre el visor del PDF a pantalla completa', (
      tester,
    ) async {
      await pumpDetail(tester, await pdfViewer(tester), file: 'a.pdf');
      await settle(tester, real: true);
      final preview = find.byKey(const Key('pdf-first-page-preview'));

      await tester.runAsync(() async {
        await tester.tapAt(awayFromButton(tester, preview));
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });

      expect(find.byType(PdfViewerScreen), findsOneWidget);
    }, skip: _pdfiumPath == null);

    testWidgets('un PDF que no se puede abrir no rompe el detalle: queda el '
        'ícono y «Leer como libro»', (tester) async {
      await pumpDetail(
        tester,
        PdfResolvedViewer('${tempDir.path}/no-existe.pdf'),
        file: 'a.pdf',
      );
      await settle(tester, real: true);

      expect(pdfPreview, findsOneWidget);
      expect(find.byType(PdfPageView), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.text(es.detailReadAsBook), findsOneWidget);
    }, skip: _pdfiumPath == null);
  });
}
