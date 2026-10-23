import 'dart:convert';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/export/data/marked/docx_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/markdown_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/pdf_document_marker.dart';
import 'package:sinapsis/features/export/data/marked/text_docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/services/marked_document_writer.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';

// Los escritores de cada formato llevados a `MarkedDocumentWriter` (F38):
// cada uno tiene su firma, y acá se acomodan los parámetros.

/// El PDF, con anotaciones de resaltado de verdad (decisión B).
class PdfMarkedDocumentWriter implements MarkedDocumentWriter {
  const PdfMarkedDocumentWriter({
    PdfDocumentMarker marker = const PdfDocumentMarker(),
    PdfEngineInitializer initialize = pdfrxFlutterInitialize,
  }) : _marker = marker,
       _initialize = initialize;

  final PdfDocumentMarker _marker;

  /// Cómo se prepara PDFium: lo mismo que al leer un PDF, ver `PdfParser`.
  /// Abrirlo sin preparar el motor revienta.
  final PdfEngineInitializer _initialize;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) async {
    await _initialize();
    return _marker.mark(original, content: content, marks: marks);
  }
}

/// El Word, con el sombreado o el subrayado de cada tramo en sus runs.
class DocxMarkedDocumentWriter implements MarkedDocumentWriter {
  const DocxMarkedDocumentWriter([this._writer = const DocxMarkWriter()]);

  final DocxMarkWriter _writer;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) => _writer.write(docx: original, text: content, marks: marks);
}

/// Un texto suelto, que no tiene dónde guardar un color: sale como un Word
/// con el mismo texto (decisión C).
///
/// El texto que se escribe es el extraído, no el archivo: de un `.txt` es el
/// mismo texto ya decodificado, y las posiciones de los tramos son de él, así
/// que caen exactas sin tener que buscarlas.
class TextMarkedDocumentWriter implements MarkedDocumentWriter {
  const TextMarkedDocumentWriter([this._writer = const TextDocxMarkWriter()]);

  final TextDocxMarkWriter _writer;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) => _writer.write(text: content, marks: marks);
}

/// El Markdown, con `==resaltado==`: se decodifica como al leerlo —sin la
/// marca de orden de bytes— y sale en UTF-8.
class MarkdownMarkedDocumentWriter implements MarkedDocumentWriter {
  const MarkdownMarkedDocumentWriter([
    this._writer = const MarkdownMarkWriter(),
  ]);

  final MarkdownMarkWriter _writer;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
  }) async => utf8.encode(
    _writer.write(
      markdown: decodePlainText(original),
      text: content,
      marks: marks,
    ),
  );
}
