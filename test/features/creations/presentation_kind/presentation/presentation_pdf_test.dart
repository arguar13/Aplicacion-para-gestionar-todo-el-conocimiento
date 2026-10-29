import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/presentation_exporter.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_viewer.dart';

import '../../../../support/pdf_annotations.dart';
import '../support/presentation_harness.dart';

/// El PDF de una presentación (F43, punto 5), leído de vuelta con PDFium:
/// una página por diapositiva con el diseño que se ve —el del visor, aunque
/// todavía no se haya guardado— y, en «Del presentador», sus notas.
void main() {
  group('con PDFium', _tests, skip: pdfiumPath == null ? missingPdfium : null);
}

void _tests() {
  setUpAll(() async {
    Pdfrx.pdfiumModulePath = pdfiumPath;
    await pdfrxInitialize();
  });

  Future<List<(double, double)>> pages(
    WidgetTester tester,
    Uint8List pdf,
  ) async => (await tester.runAsync(() async {
    final document = await PdfDocument.openData(pdf);
    try {
      return [for (final p in document.pages) (p.width, p.height)];
    } finally {
      await document.dispose();
    }
  }))!;

  /// La luz del punto de arriba a la izquierda de la página [index].
  Future<int> cornerLight(
    WidgetTester tester,
    Uint8List pdf,
    int index,
  ) async => (await tester.runAsync(() async {
    final document = await PdfDocument.openData(pdf);
    try {
      final page = document.pages[index];
      final image = await page.render(
        fullWidth: page.width,
        fullHeight: page.height,
        backgroundColor: 0xFFFF00FF,
      );
      try {
        final p = image!.pixels;
        final at = (4 * image.width + 4) * 4;
        return p[at] + p[at + 1] + p[at + 2];
      } finally {
        image?.dispose();
      }
    } finally {
      await document.dispose();
    }
  }))!;

  testWidgets('«Del presentador»: cada diapositiva con su página de notas, '
      'en la plantilla que se ve, con su ilustración', (tester) async {
    final h = await PresentationHarness.create();
    await h.processed('d1', 'Éxodo');
    final c = await h.ready(
      viewerDeck(),
      options: {
        ...presenterOptions,
        PresentationOptionKeys.design: const DeckDesign(
          template: DeckTemplateId.midnight,
        ).toJson(),
      },
      illustrated: const [0],
    );
    await h.openViewer(tester, c);
    final element = tester.element(find.byType(PresentationViewer));

    final file = (await tester.runAsync(
      () => exportPresentationPdf(element, element as WidgetRef, c),
    ))!;
    expect(file.mimeType, 'application/pdf');
    expect(file.fileName, 'Éxodo_ liberación y alianza.pdf');
    expect(file.bytes.sublist(0, 5), '%PDF-'.codeUnits);

    final sizes = await pages(tester, file.bytes);
    expect(sizes, hasLength(10));
    for (final (width, height) in sizes) {
      expect(width / height, closeTo(16 / 9, 0.01));
    }
    // La diapositiva, oscura (Medianoche); sus notas, en blanco.
    expect(await cornerLight(tester, file.bytes, 0), lessThan(150));
    expect(await cornerLight(tester, file.bytes, 1), greaterThan(740));
  });

  testWidgets('«Detallada»: solo las diapositivas, en 4:3 si se eligió', (
    tester,
  ) async {
    final h = await PresentationHarness.create();
    await h.processed('d1', 'Éxodo');
    final c = await h.ready(
      viewerDeck(format: DeckFormat.detailed),
      options: {
        PresentationOptionKeys.design: const DeckDesign(
          aspect: DeckAspect.standard,
        ).toJson(),
      },
    );
    await h.openViewer(tester, c);
    final element = tester.element(find.byType(PresentationViewer));

    final file = (await tester.runAsync(
      () => exportPresentationPdf(element, element as WidgetRef, c),
    ))!;
    final sizes = await pages(tester, file.bytes);
    expect(sizes, hasLength(5));
    expect(sizes.first.$1 / sizes.first.$2, closeTo(4 / 3, 0.01));
  });
}
