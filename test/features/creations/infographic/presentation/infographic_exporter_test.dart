import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/export/infographic_exporter.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';

import '../../../../support/pdf_annotations.dart';
import '../support/infographic_muestrario.dart';
import '../support/sample_infographics.dart';

/// Guardar una infografía (F43: «Exportar: PNG en alta resolución, o
/// PDF»): la misma lámina de la pantalla, dibujada fuera de ella.
void main() {
  setUpAll(loadInfographicFonts);

  const exporter = InfographicExporter();

  testWidgets('el PNG, sin pérdida, al doble de la lámina y con su fondo', (
    tester,
  ) async {
    for (final orientation in InfographicOrientation.values) {
      final design = InfographicDesign(
        style: InfographicStyleId.chalkboard,
        orientation: orientation,
        background: InfographicBackground.plain,
      );
      final png = (await tester.runAsync(
        () => exporter.toPng(
          sheet: sampleInfographic(),
          design: design,
          pixelRatio: 0.5,
        ),
      ))!;
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final decoded = img.decodePng(png)!;
      expect(decoded.width, (orientation.logicalWidth / 2).round());
      expect(decoded.height, (orientation.logicalHeight / 2).round());
      // La esquina es el fondo liso de Pizarra.
      final background = InfographicStyles.of(
        InfographicStyleId.chalkboard,
      ).palettes.first.background;
      final corner = decoded.getPixel(2, 2);
      expect(
        (corner.r - (background.r * 255).round()).abs(),
        lessThanOrEqualTo(6),
      );
      expect(
        (corner.g - (background.g * 255).round()).abs(),
        lessThanOrEqualTo(6),
      );
      // Y hay algo dibujado encima.
      var different = 0;
      for (final pixel in decoded) {
        if ((pixel.r - corner.r).abs() > 40) different++;
      }
      expect(different, greaterThan(500), reason: orientation.id);
    }
    expect(InfographicExporter.pngPixelRatio, 2);
  });

  testWidgets('una ilustración ya hecha sale en la imagen', (tester) async {
    final green = (await tester.runAsync(
      () => solidPng(const Color(0xFF00FF00)),
    ))!;
    final sheet = sampleInfographic().copyWith(illustrationRef: 'cabecera');
    Future<int> greens({required bool withImage}) async {
      final png = (await tester.runAsync(
        () => exporter.toPng(
          sheet: sheet,
          design: const InfographicDesign(style: InfographicStyleId.photo),
          pixelRatio: 0.25,
          illustrations: withImage ? (_) => MemoryImage(green) : null,
        ),
      ))!;
      var count = 0;
      for (final pixel in img.decodePng(png)!) {
        if (pixel.g > 200 && pixel.r < 60 && pixel.b < 60) count++;
      }
      return count;
    }

    expect(await greens(withImage: true), greaterThan(200));
    expect(await greens(withImage: false), 0);
  });

  group('el PDF', () {
    setUpAll(() async {
      Pdfrx.pdfiumModulePath = pdfiumPath;
      await pdfrxInitialize();
    });

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

    testWidgets('una sola página, de la forma de la lámina', (tester) async {
      for (final orientation in InfographicOrientation.values) {
        final pdf = (await tester.runAsync(
          () => exporter.toPdf(
            sheet: sampleInfographic(),
            design: InfographicDesign(orientation: orientation),
            pixelRatio: 0.4,
          ),
        ))!;
        expect(pdf.sublist(0, 5), '%PDF-'.codeUnits);
        final sizes = await pageSizes(tester, pdf);
        expect(sizes, hasLength(1));
        final (width, height) = sizes.single;
        expect(width / height, closeTo(orientation.ratio, 0.01));
        expect(
          width > height ? width : height,
          closeTo(InfographicExporter.pdfLongSide, 1),
        );
      }
    });
  }, skip: pdfiumPath == null ? missingPdfium : null);
}
