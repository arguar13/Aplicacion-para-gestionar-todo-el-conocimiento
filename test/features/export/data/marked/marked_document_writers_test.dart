import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/marked_document_writers.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';

import '../../../../support/pdf_annotations.dart';
import '../../../../support/sample_files.dart';

/// Los adaptadores de cada formato (F38): que cada uno le dé a su escritor
/// el archivo y el texto que corresponden, y devuelva lo que sale.
void main() {
  const turquoise = 0xFF4DD0E1;

  DocumentMark markOf(
    String content,
    String excerpt, {
    HighlightStyle style = HighlightStyle.fill,
  }) {
    final start = content.indexOf(excerpt);
    expect(start, greaterThanOrEqualTo(0), reason: '«$excerpt» no está');
    return DocumentMark(
      start: start,
      end: start + excerpt.length,
      excerpt: excerpt,
      color: turquoise,
      style: style,
    );
  }

  String bodyOf(Uint8List docx) => utf8.decode(
    ZipDecoder().decodeBytes(docx).findFile('word/document.xml')!.readBytes()!,
  );

  test('el Word sale con el tramo sombreado de su color', () async {
    final docx = buildDocx(body: wordParagraph('La revolución cambió todo'));
    const content = 'La revolución cambió todo';

    final out = await const DocxMarkedDocumentWriter().write(
      docx,
      content: content,
      marks: [markOf(content, 'cambió')],
    );

    expect(bodyOf(out), contains('w:fill="4DD0E1"'));
  });

  test('un texto suelto sale como Word con el texto extraído y su tramo '
      'marcado', () async {
    const content = 'Primera línea\nSegunda línea';

    final out = await const TextMarkedDocumentWriter().write(
      // El archivo no se lee: el texto es el extraído, el de las posiciones.
      Uint8List.fromList(utf8.encode('otra cosa')),
      content: content,
      marks: [markOf(content, 'Segunda', style: HighlightStyle.underline)],
    );

    final body = bodyOf(out);
    expect(body, contains('Primera línea'));
    expect(body, isNot(contains('otra cosa')));
    expect(body, contains('w:color="4DD0E1"'));
  });

  test('el Markdown se lee como al importarlo —acá, un UTF-16 con su '
      'marca— y sale en UTF-8 con ==así==', () async {
    const content = '# Título\n\nUna frase con acentuación.';
    final original = Uint8List.fromList([
      0xFF, 0xFE, // la marca de UTF-16 LE
      for (final unit in content.codeUnits) ...[unit & 0xFF, unit >> 8],
    ]);

    final out = await const MarkdownMarkedDocumentWriter().write(
      original,
      content: content,
      marks: [markOf(content, 'acentuación')],
    );

    expect(utf8.decode(out), '# Título\n\nUna frase con ==acentuación==.');
  });

  group('el PDF', () {
    setUpAll(() {
      Pdfrx.pdfiumModulePath = pdfiumPath;
    });

    test('prepara el motor antes de abrirlo y sale con su anotación', () async {
      var initialized = false;
      final writer = PdfMarkedDocumentWriter(
        initialize: () async {
          await pdfrxInitialize();
          initialized = true;
        },
      );
      final pdf = buildPdf(); // una página: «Hola mundo»

      final out = await writer.write(
        pdf,
        content: 'Hola mundo',
        marks: [markOf('Hola mundo', 'mundo')],
      );

      expect(initialized, isTrue);
      final annotations = await readAnnotations(out);
      expect(annotations.single, hasLength(1));
    });
  }, skip: pdfiumPath == null ? missingPdfium : null);
}
