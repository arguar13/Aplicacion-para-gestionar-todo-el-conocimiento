import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_docx.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_markdown.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_pdf.dart';
import 'package:sinapsis/features/export/data/exporters/bibliography_plain_text.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

/// Los formatos en que se puede guardar una bibliografía sola (F15, D13): no
/// el `.bib` —esa exportación es de una obra, no de una lista de obras—.
const bibliographyFormats = [
  ExportFormat.markdown,
  ExportFormat.plainText,
  ExportFormat.pdf,
  ExportFormat.docx,
];

/// [bibliography] como un archivo de verdad, en [format] —uno de
/// [bibliographyFormats]—.
Future<Uint8List> buildBibliographyFile(
  Bibliography bibliography,
  ExportFormat format,
) async {
  return switch (format) {
    ExportFormat.markdown => buildBibliographyMarkdown(bibliography),
    ExportFormat.plainText => buildBibliographyPlainText(bibliography),
    ExportFormat.pdf => await buildBibliographyPdf(bibliography),
    ExportFormat.docx => buildBibliographyDocx(bibliography),
    ExportFormat.bibtex => throw ArgumentError(
      'La bibliografía no se exporta como .bib: eso es de una obra sola, '
      'no de esta lista.',
    ),
  };
}

/// El nombre con que se sugiere guardar una bibliografía en [format]: el de
/// [scope] —el espacio, la rama, la nota o «Bibliografía» a secas para una
/// selección— y no el de la lista —«Referencias», «Obras citadas»—, que es
/// el mismo en cualquier bibliografía del mismo estilo y no distingue una
/// exportación de otra.
String suggestedBibliographyFileName(String scope, ExportFormat format) =>
    '${sanitizeFileName(scope)}.${format.fileExtension}';
