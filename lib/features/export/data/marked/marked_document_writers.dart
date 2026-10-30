import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/export/data/marked/docx_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/epub_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/html_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/markdown_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/pdf_document_marker.dart';
import 'package:sinapsis/features/export/data/marked/text_docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
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
    List<DocumentNote> notes = const [],
  }) async {
    await _initialize();
    return _marker.mark(original, content: content, marks: marks, notes: notes);
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
    List<DocumentNote> notes = const [],
  }) =>
      _writer.write(docx: original, text: content, marks: marks, notes: notes);
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
    List<DocumentNote> notes = const [],
  }) => _writer.write(text: content, marks: marks, notes: notes);
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
    List<DocumentNote> notes = const [],
  }) async => utf8.encode(
    _writer.write(
      markdown: decodePlainText(original),
      text: content,
      marks: marks,
      notes: notes,
    ),
  );
}

/// El EPUB, con cada tramo en un `<mark>` de su color en su capítulo.
///
/// Descomprimir y recorrer un libro entero congelaría la pantalla: se hace en
/// otro isolate, como al leerlo.
class EpubMarkedDocumentWriter implements MarkedDocumentWriter {
  const EpubMarkedDocumentWriter([this._writer = const EpubMarkWriter()]);

  final EpubMarkWriter _writer;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) {
    final writer = _writer;
    return Isolate.run(() => writer.write(original, content, marks, notes));
  }
}

/// La página web archivada, con cada tramo en un `<mark>` de su color.
///
/// El archivador la guarda siempre en UTF-8 (`HtmlPageArchiver`), y en UTF-8
/// sale. Una página archivada pesa megas —sus imágenes van adentro—: se
/// marca en otro isolate, como al mostrarla.
class WebPageMarkedDocumentWriter implements MarkedDocumentWriter {
  const WebPageMarkedDocumentWriter([this._writer = const HtmlMarkWriter()]);

  final HtmlMarkWriter _writer;

  @override
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) {
    final writer = _writer;
    return Isolate.run(
      () => utf8.encode(
        writer.write(utf8.decode(original), content, marks, notes),
      ),
    );
  }
}
