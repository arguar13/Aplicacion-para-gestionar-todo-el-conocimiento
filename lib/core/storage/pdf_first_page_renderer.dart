import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// A cuánto se renderiza la miniatura de un PDF: de sobra para el ancho de
/// una tarjeta a cualquier densidad de pantalla razonable, y chico para que
/// renderizar no demore ni pese como una página de lectura — el mismo
/// criterio que `PdfParser._ocrRenderScale`, pero pensado para mostrar, no
/// para reconocer texto.
const _thumbnailWidth = 240.0;

/// Renderiza la primera página de [pdfBytes] como PNG, con el mismo motor
/// —`pdfrx` sobre PDFium— que ya usa `PdfParser` para el OCR de páginas
/// escaneadas.
///
/// `null` ante cualquier fallo: un PDF cifrado, corrupto, o simplemente sin
/// páginas. Una tarjeta sin miniatura cae en su ícono de siempre, así que no
/// hace falta distinguir el motivo — ver `ItemThumbnailResolver`.
Future<Uint8List?> renderPdfFirstPageThumbnail(Uint8List pdfBytes) async {
  await pdfrxFlutterInitialize();

  PdfDocument? document;
  try {
    document = await PdfDocument.openData(pdfBytes);
    if (document.pages.isEmpty) return null;

    final page = document.pages.first;
    final scale = _thumbnailWidth / page.width;
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null) return null;

    try {
      return Uint8List.fromList(
        img.encodePng(
          img.Image.fromBytes(
            width: rendered.width,
            height: rendered.height,
            bytes: rendered.pixels.buffer,
            order: img.ChannelOrder.bgra,
            numChannels: 4,
          ),
        ),
      );
    } finally {
      rendered.dispose();
    }
    // PDFium informa sus fallos de varias formas —archivo corrupto, cifrado,
    // versión no soportada— y ninguna tiene un tipo propio en Dart, igual que
    // en `PdfParser._open`.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  } finally {
    await document?.dispose();
  }
}
