import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';

/// La bibliografía de un conjunto como un PDF de verdad (F15): el título de la
/// lista y una entrada por párrafo, con las cursivas del estilo.
///
/// Es solo la lista, sin el texto de una nota ni nada más: la bibliografía al
/// pie de una nota exportada es otro camino —[bibliographyPdfWidgets], que
/// `PdfExporter` agrega después de su propio contenido, en el mismo
/// documento—.
Future<Uint8List> buildBibliographyPdf(Bibliography bibliography) async {
  final document = pw.Document()
    ..addPage(
      pw.MultiPage(
        // Mismo tope que `PdfExporter`: una bibliografía de miles de fuentes
        // no puede toparse con el límite pensado para un documento corto.
        maxPages: 100000,
        build: (context) => bibliographyPdfWidgets(bibliography),
      ),
    );
  return document.save();
}

/// El título de la lista y una entrada por párrafo de [bibliography], listos
/// para entrar en cualquier [pw.MultiPage] —solos, en [buildBibliographyPdf],
/// o al pie del contenido de una nota, en `PdfExporter`—. Vacío si
/// [bibliography] no tiene entradas.
List<pw.Widget> bibliographyPdfWidgets(Bibliography bibliography) {
  if (bibliography.isEmpty) return const [];

  return [
    pw.Text(
      bibliography.title,
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 8),
    for (final entry in bibliography.entries) ...[
      _citationText(entry.citation),
      pw.SizedBox(height: 8),
    ],
  ];
}

/// Una cita, con sus cursivas: cada corrida —de texto llano, en cursiva o un
/// hueco— es un `TextSpan` propio, y solo la cursiva cambia el estilo.
pw.Widget _citationText(Citation citation) => pw.RichText(
  overflow: pw.TextOverflow.span,
  text: pw.TextSpan(
    children: [
      for (final run in citation.runs)
        pw.TextSpan(
          text: run.text,
          style: run is ItalicRun
              ? pw.TextStyle(fontStyle: pw.FontStyle.italic)
              : null,
        ),
    ],
  ),
);
