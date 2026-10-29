/// Lo común de los PDF del mazo y del cuestionario (F43, paso 8): la letra de
/// la app y los colores, para que lo impreso se lea como lo de la pantalla.
library;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// La letra de los PDF: Inter, la de la app, que trae las tildes, la ñ, las
/// comillas latinas, la raya y los alfabetos griego y cirílico —la de fábrica
/// del PDF solo sabe Latin-1, y un cuestionario en griego saldría en
/// blanco—. Si no se puede leer, la de fábrica.
Future<pw.ThemeData> studyPdfTheme({AssetBundle? bundle}) async {
  try {
    final data = await (bundle ?? rootBundle).load(
      'assets/fonts/InterVariable.ttf',
    );
    final font = pw.Font.ttf(data);
    return pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
    );
    // Un recurso que falta es un `FlutterError`, no una `Exception`: sin la
    // letra, el PDF sale igual con la de fábrica.
  } on Object {
    return pw.ThemeData.base();
  }
}

/// El color del texto secundario.
const kStudyPdfMuted = PdfColor.fromInt(0xFF5F6368);

/// El de los bordes y las líneas finas.
const kStudyPdfLine = PdfColor.fromInt(0xFFDADCE0);

/// El de acertar, para la clave de respuestas.
const kStudyPdfGood = PdfColor.fromInt(0xFF188038);

/// Un documento A4 de varias páginas con [build], el [title] arriba y el
/// número de página abajo.
Future<Uint8List> buildStudyPdf({
  required String title,
  required String subtitle,
  required List<pw.Widget> Function() build,
  required String Function(int page, int pages) pageLabel,
  AssetBundle? bundle,
}) async {
  final theme = await studyPdfTheme(bundle: bundle);
  final document = pw.Document(title: title, theme: theme)
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 40),
        maxPages: 1000,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            pageLabel(context.pageNumber, context.pagesCount),
            style: const pw.TextStyle(fontSize: 9, color: kStudyPdfMuted),
          ),
        ),
        build: (context) => [
          pw.Text(title, style: const pw.TextStyle(fontSize: 22)),
          if (subtitle.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 11, color: kStudyPdfMuted),
            ),
          ],
          pw.SizedBox(height: 18),
          ...build(),
        ],
      ),
    );
  return document.save();
}
