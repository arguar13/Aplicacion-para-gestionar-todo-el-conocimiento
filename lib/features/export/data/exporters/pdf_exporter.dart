import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Exporta a PDF, para leer o imprimir fuera de la app.
///
/// Usa [`pdf`](https://pub.dev/packages/pdf), Apache-2.0 y en Dart puro — no
/// depende de un motor nativo, así que genera igual en Android, iOS,
/// Windows, macOS, Linux y web. No tiene relación con `pdfrx_engine`: aquel
/// es un **lector** (extraer texto de un PDF ya existente, fase 5) y este es
/// un **escritor**; que los dos entiendan PDF no significa que sirva el
/// mismo paquete para las dos direcciones.
///
/// Igual que el exportador de texto plano, el contenido **no se convierte**
/// desde Markdown: los símbolos (`#`, `**`, `-`) quedan tal cual.
/// Interpretarlos para maquetar el PDF de verdad es un trabajo considerable y
/// con muchos casos borde, y esta exportación ya cumple su propósito con
/// texto corrido bien paginado — leer o imprimir fuera de la app no exige que
/// además se vea como un documento diseñado.
class PdfExporter implements Exporter {
  const PdfExporter();

  @override
  ExportFormat get format => ExportFormat.pdf;

  @override
  String suggestedFileName(KnowledgeItem item) =>
      '${sanitizeFileName(item.title)}.${format.fileExtension}';

  @override
  Future<Uint8List> export(KnowledgeItem item) async {
    final document = pw.Document()
      ..addPage(
        pw.MultiPage(
          // Sin este tope, un libro entero pasado por EPUB —cientos de
          // páginas de texto corrido— dispara `TooManyPagesException`: el
          // valor por defecto (20) está pensado para un documento corto, no
          // para lo que esta app guarda.
          maxPages: 100000,
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          build: (context) => [
            pw.Text(
              item.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            if (item.subtitle != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                item.subtitle!,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
            ],
            if (item.notes?.isNotEmpty ?? false) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.only(left: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.grey400, width: 2),
                  ),
                ),
                child: pw.Text(
                  item.notes!,
                  overflow: pw.TextOverflow.span,
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
                ),
              ),
            ],
            pw.SizedBox(height: 16),
            ..._content(item),
            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 8),
            for (final line in _provenance(item))
              pw.Text(
                line,
                overflow: pw.TextOverflow.span,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
          ],
        ),
      );

    return document.save();
  }

  /// El contenido, un párrafo por widget.
  ///
  /// Partir por párrafo —y no meter todo el texto en un único [pw.Text]— es
  /// lo que deja un espaciado legible entre ellos. `overflow: span` en cada
  /// uno es necesario aparte: sin eso, un párrafo más largo que una página
  /// entera —una transcripción sin cortes— no pasaría a la página
  /// siguiente, se recortaría en la primera.
  List<pw.Widget> _content(KnowledgeItem item) {
    final texts = item.renditions.whereType<TextRendition>();
    if (texts.isEmpty) {
      return [
        pw.Text(
          'Sin contenido extraído todavía.',
          style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
        ),
      ];
    }

    final widgets = <pw.Widget>[];
    for (final rendition in texts) {
      for (final paragraph in _paragraphs(rendition.content)) {
        widgets
          ..add(pw.Text(paragraph, overflow: pw.TextOverflow.span))
          ..add(pw.SizedBox(height: 8));
      }
    }
    return widgets;
  }

  Iterable<String> _paragraphs(String content) => content
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty);

  List<String> _provenance(KnowledgeItem item) {
    final source = item.source;
    final lines = <String>[
      'Guardado el ${source.capturedAt.toIso8601String().substring(0, 10)}.',
    ];

    if (source.url != null) lines.add('Fuente: ${source.url}');
    if (source.authorUrl != null) {
      lines.add('Autor: ${source.authorUrl}');
    } else if (source.authorName != null) {
      lines.add('Autor: ${source.authorName}');
    }

    return lines;
  }
}
