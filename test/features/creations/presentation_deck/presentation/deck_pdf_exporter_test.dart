import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/creations/design/creation_rasterizer.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/export/deck_pdf_exporter.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';

import '../../../../support/pdf_annotations.dart';
import '../support/sample_decks.dart';

/// El PDF de un mazo (F43, punto 5): una página por diapositiva, del tamaño
/// del formato, con el mismo dibujo que se ve en pantalla —dibujado fuera de
/// pantalla—, y si se pide, una página de notas después de cada una.
void main() {
  group('con PDFium', _tests, skip: pdfiumPath == null ? missingPdfium : null);

  // El dibujo fuera de pantalla no necesita PDFium.
  testWidgets('el dibujo fuera de pantalla es el de la diapositiva', (
    tester,
  ) async {
    final deck = sampleDeck();
    for (final (template, slide) in [
      (DeckTemplateId.swiss, 2),
      (DeckTemplateId.midnight, 2),
      (DeckTemplateId.pastel, 4),
    ]) {
      final design = DeckDesign(template: template);
      final pixels = await tester.runAsync(() async {
        final image = await CreationRasterizer.render(
          SlideView(
            slide: deck.slides[slide],
            design: design,
            deck: deck,
            index: slide,
          ),
          logicalSize: const Size(1920, 1080),
          pixelRatio: 0.25,
        );
        try {
          expect(image.width, 480);
          expect(image.height, 270);
          return (await image.toByteData())!;
        } finally {
          image.dispose();
        }
      });
      // La esquina de arriba a la izquierda es el fondo de la plantilla (con
      // el degradé de Medianoche, un poco más claro).
      final background = DeckTemplates.of(template).palettes.first.background;
      final r = pixels!.getUint8(4 * (2 * 480 + 2));
      final g = pixels.getUint8(4 * (2 * 480 + 2) + 1);
      final b = pixels.getUint8(4 * (2 * 480 + 2) + 2);
      expect(
        (r - (background.r * 255).round()).abs(),
        lessThanOrEqualTo(24),
        reason: template.id,
      );
      expect((g - (background.g * 255).round()).abs(), lessThanOrEqualTo(24));
      expect((b - (background.b * 255).round()).abs(), lessThanOrEqualTo(24));
      // Y hay algo dibujado encima: el texto no es del color del fondo.
      var different = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if ((pixels.getUint8(i) - r).abs() > 40) different++;
      }
      expect(different, greaterThan(500), reason: template.id);
    }
  });

  testWidgets('a JPEG y a PNG', (tester) async {
    await tester.runAsync(() async {
      final image = await CreationRasterizer.render(
        const ColoredBox(color: Colors.teal),
        logicalSize: const Size(64, 32),
      );
      try {
        final jpg = await CreationRasterizer.toJpeg(image);
        expect(jpg.sublist(0, 2), [0xFF, 0xD8]);
        final png = await CreationRasterizer.toPng(image);
        expect(png.sublist(1, 4), 'PNG'.codeUnits);
      } finally {
        image.dispose();
      }
    });
  });
}

void _tests() {
  const exporter = DeckPdfExporter();

  setUpAll(() async {
    Pdfrx.pdfiumModulePath = pdfiumPath;
    await pdfrxInitialize();
  });

  final deck = sampleDeck();
  final short = deck.copyWith(slides: deck.slides.take(3).toList());

  Future<Uint8List> export(
    WidgetTester tester,
    SlideDeck deck,
    DeckDesign design, {
    bool notes = false,
  }) async => (await tester.runAsync(
    () => exporter.export(
      deck: deck,
      design: design,
      includeSpeakerNotes: notes,
      pixelWidth: 640,
    ),
  ))!;

  Future<List<(double, double)>> pageSizes(
    WidgetTester tester,
    Uint8List pdf,
  ) async => (await tester.runAsync(() async {
    final document = await PdfDocument.openData(pdf);
    try {
      return [for (final page in document.pages) (page.width, page.height)];
    } finally {
      await document.dispose();
    }
  }))!;

  /// El color de un punto de la página [index], pintada a un píxel por
  /// punto.
  Future<int> pixelAt(
    WidgetTester tester,
    Uint8List pdf,
    int index,
    int x,
    int y,
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
        final at = (y * image!.width + x) * 4;
        final p = image.pixels;
        // BGRA → 0xRRGGBB.
        return (p[at + 2] << 16) | (p[at + 1] << 8) | p[at];
      } finally {
        image?.dispose();
      }
    } finally {
      await document.dispose();
    }
  }))!;

  testWidgets('una página por diapositiva, del tamaño del formato', (
    tester,
  ) async {
    final wide = await export(tester, short, const DeckDesign());
    expect(wide.sublist(0, 5), '%PDF-'.codeUnits);
    final sizes = await pageSizes(tester, wide);
    expect(sizes, hasLength(3));
    for (final (width, height) in sizes) {
      expect(width / height, closeTo(16 / 9, 0.01));
    }

    final narrow = await export(
      tester,
      short,
      const DeckDesign(aspect: DeckAspect.standard),
    );
    for (final (width, height) in await pageSizes(tester, narrow)) {
      expect(width / height, closeTo(4 / 3, 0.01));
    }
  });

  testWidgets('las páginas de notas van después de cada diapositiva', (
    tester,
  ) async {
    final pdf = await export(
      tester,
      short,
      const DeckDesign(template: DeckTemplateId.midnight),
      notes: true,
    );
    expect(await pageSizes(tester, pdf), hasLength(6));
    // La diapositiva, oscura; sus notas, en blanco para imprimir.
    final slide = await pixelAt(tester, pdf, 0, 4, 4);
    final notes = await pixelAt(tester, pdf, 1, 4, 4);
    int light(int rgb) =>
        ((rgb >> 16) & 0xff) + ((rgb >> 8) & 0xff) + (rgb & 0xff);
    expect(light(slide), lessThan(150));
    expect(light(notes), greaterThan(740));
  });

  testWidgets('cada página es la diapositiva entera, sin márgenes', (
    tester,
  ) async {
    final pdf = await export(
      tester,
      const SlideDeck(
        title: 'T',
        slides: [Slide.section(title: 'Parte')],
      ),
      const DeckDesign(template: DeckTemplateId.swiss),
    );
    // El cuadrado rojo de la sección suiza llega hasta la esquina de arriba
    // a la derecha de la página.
    final sizes = await pageSizes(tester, pdf);
    final corner = await pixelAt(
      tester,
      pdf,
      0,
      sizes.single.$1.floor() - 3,
      3,
    );
    expect((corner >> 16) & 0xff, greaterThan(180));
    expect((corner >> 8) & 0xff, lessThan(60));
  });

  testWidgets('las ilustraciones ya hechas se cargan antes de dibujar', (
    tester,
  ) async {
    final png = await tester.runAsync(() async {
      final image = await CreationRasterizer.render(
        const ColoredBox(color: Color(0xFF00FF00)),
        logicalSize: const Size(32, 32),
      );
      try {
        return await CreationRasterizer.toPng(image);
      } finally {
        image.dispose();
      }
    });
    final pdf = await tester.runAsync(
      () => exporter.export(
        deck: const SlideDeck(
          title: 'T',
          slides: [Slide.imageText(title: 'Con imagen', illustrationRef: 'x')],
        ),
        design: const DeckDesign(template: DeckTemplateId.swiss),
        pixelWidth: 640,
        illustrations: (reference) => MemoryImage(png!),
      ),
    );
    // La imagen (verde puro) ocupa la mitad de la diapositiva: con la de
    // reserva no habría verde.
    final sizes = await pageSizes(tester, pdf!);
    final (width, height) = sizes.single;
    final left = await pixelAt(
      tester,
      pdf,
      0,
      (width * 0.25).floor(),
      (height / 2).floor(),
    );
    final right = await pixelAt(
      tester,
      pdf,
      0,
      (width * 0.75).floor(),
      (height / 2).floor(),
    );
    bool green(int rgb) =>
        ((rgb >> 8) & 0xff) > 200 && ((rgb >> 16) & 0xff) < 60;
    expect(green(left) || green(right), isTrue);
  });
}
