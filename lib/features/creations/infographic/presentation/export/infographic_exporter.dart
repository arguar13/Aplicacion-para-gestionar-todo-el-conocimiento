import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/features/creations/design/creation_rasterizer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';

/// Guardar una infografía (F43: «Exportar: PNG en alta resolución, o PDF»).
///
/// Las dos salen de la misma `InfographicView` que se ve en pantalla,
/// dibujada fuera de pantalla con `CreationRasterizer`: la imagen es fiel
/// por construcción —la misma letra, los mismos fondos, el mismo ajuste del
/// texto—, sin un segundo dibujo hecho con otra librería.
///
/// - El PNG va sin pérdida, a [pngPixelRatio] píxeles por punto: una lámina
///   vertical de 1080×1920 sale de 2160×3840, nítida para imprimir o
///   compartir.
/// - El PDF es una sola página del tamaño exacto de la lámina, con la imagen
///   a sangre (en JPEG, que pesa diez veces menos que el PNG a la vista). El
///   costo, como en el mazo, es que su texto no se puede seleccionar.
///
/// Devuelve los bytes; guardarlos o compartirlos es de quien llama.
class InfographicExporter {
  const InfographicExporter();

  /// Píxeles por punto lógico del PNG.
  static const double pngPixelRatio = 2;

  /// Puntos de PDF del lado más largo de la página.
  static const double pdfLongSide = 842;

  Future<Uint8List> toPng({
    required Infographic sheet,
    required InfographicDesign design,
    double pixelRatio = pngPixelRatio,
    InfographicIllustrationResolver? illustrations,
  }) async {
    final image = await _render(sheet, design, pixelRatio, illustrations);
    try {
      return await CreationRasterizer.toPng(image);
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> toPdf({
    required Infographic sheet,
    required InfographicDesign design,
    double pixelRatio = pngPixelRatio,
    int jpegQuality = 92,
    InfographicIllustrationResolver? illustrations,
  }) async {
    final image = await _render(sheet, design, pixelRatio, illustrations);
    final Uint8List jpg;
    try {
      jpg = await CreationRasterizer.toJpeg(image, quality: jpegQuality);
    } finally {
      image.dispose();
    }
    final orientation = design.orientation;
    final scale =
        pdfLongSide /
        (orientation.logicalWidth > orientation.logicalHeight
            ? orientation.logicalWidth
            : orientation.logicalHeight);
    final format = PdfPageFormat(
      orientation.logicalWidth * scale,
      orientation.logicalHeight * scale,
    );
    final document =
        pw.Document(
          title: sheet.title,
          creator: 'Sinapsis',
          producer: 'Sinapsis',
        )..addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
            ),
          ),
        );
    return document.save();
  }

  Future<ui.Image> _render(
    Infographic sheet,
    InfographicDesign design,
    double pixelRatio,
    InfographicIllustrationResolver? illustrations,
  ) async {
    // Las ilustraciones, cargadas antes: fuera de pantalla no hay un cuadro
    // siguiente que espere a que lleguen.
    if (illustrations != null) {
      final references = [
        sheet.illustrationRef,
        for (final block in sheet.blocks) block.illustrationRef,
      ];
      for (final reference in references) {
        final provider = reference == null ? null : illustrations(reference);
        if (provider != null) await CreationRasterizer.precache(provider);
      }
    }
    return CreationRasterizer.render(
      InfographicView(
        sheet: sheet,
        design: design,
        illustrations: illustrations,
      ),
      logicalSize: Size(
        design.orientation.logicalWidth,
        design.orientation.logicalHeight,
      ),
      pixelRatio: pixelRatio,
    );
  }
}
