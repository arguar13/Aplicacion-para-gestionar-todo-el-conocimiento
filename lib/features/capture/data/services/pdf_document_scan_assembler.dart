import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/features/capture/domain/services/document_scan_assembler.dart';

/// Arma el documento con [`pdf`](https://pub.dev/packages/pdf), el mismo
/// paquete que ya usa `PdfExporter` para exportar — ver la decisión 3 en
/// docs/arquitectura.md sobre por qué éste y no uno que dependa de un motor
/// nativo.
///
/// Cada foto es una página entera, sin márgenes: es la copia de una hoja de
/// papel, no un documento maquetado, así que un margen blanco alrededor
/// solo restaría lugar a lo que la foto ya encuadró.
class PdfDocumentScanAssembler implements DocumentScanAssembler {
  const PdfDocumentScanAssembler();

  @override
  Future<Uint8List> assemble(List<Uint8List> pages) async {
    final document = pw.Document();

    for (final page in pages) {
      final image = pw.MemoryImage(page);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Center(child: pw.Image(image)),
        ),
      );
    }

    return document.save();
  }
}
