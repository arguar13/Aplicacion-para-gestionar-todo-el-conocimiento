import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/text_docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/document_parsing.dart';

const _yellow = 0xFFFFF59D;
const _orange = 0xFFFFCC80;

DocumentMark _mark(
  String text,
  String excerpt, {
  int color = _yellow,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
}) {
  final start = text.indexOf(excerpt);
  expect(start, isNonNegative, reason: '«$excerpt» no está en el texto');
  return DocumentMark(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    color: color,
    style: style,
    note: note,
  );
}

XmlDocument _document(Uint8List docx) {
  final file = ZipDecoder().decodeBytes(docx).findFile('word/document.xml');
  return XmlDocument.parse(utf8.decode(file!.readBytes()!));
}

void main() {
  const writer = TextDocxMarkWriter();

  const text =
      'Primera línea del apunte.\n'
      '\n'
      'Segunda línea con &amp; y <etiquetas> sueltas.\n'
      'Tercera\tcon tabulación y fin.';

  group('TextDocxMarkWriter', () {
    test('arma un Word con un párrafo por renglón y el mismo texto', () async {
      final docx = await writer.write(text: text, marks: [], title: 'Apunte');

      final paragraphs = _document(docx).findAllElements('w:p').toList();
      expect(paragraphs, hasLength(4));
      expect(paragraphs.map((p) => p.findAllElements('w:t').length), [
        1,
        0,
        1,
        2,
      ]);
      // La tabulación es un elemento de Word, no un carácter en el texto.
      expect(_document(docx).findAllElements('w:tab'), hasLength(1));
      // Es un Word de verdad: el lector de la app lo lee con todo el texto.
      final read = (await const DocxParser().parseBytes(docx)).markdown;
      expect(read, contains('Primera línea del apunte.'));
      expect(read, contains('Segunda línea con &amp; y <etiquetas> sueltas.'));
      expect(read, contains('Tercera'));
      expect(read, contains('con tabulación y fin.'));
      // Con sus propiedades, que Word pide para abrirlo.
      final names = ZipDecoder().decodeBytes(docx).files.map((f) => f.name);
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'docProps/core.xml',
        ]),
      );
      expect(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(docx)
              .findFile('docProps/core.xml')!
              .readBytes()!,
        ),
        contains('Apunte'),
      );
    });

    test(
      'los tramos salen marcados: fondo con el color exacto y subrayado',
      () async {
        final docx = await writer.write(
          text: text,
          marks: [
            _mark(text, 'línea del apunte'),
            _mark(
              text,
              '&amp; y <etiquetas>',
              color: _orange,
              style: HighlightStyle.underline,
            ),
          ],
        );

        final runs = _document(docx).findAllElements('w:r').toList();
        final filled = runs.where(
          (r) => r.getElement('w:rPr')?.getElement('w:shd') != null,
        );
        expect(filled.map((r) => r.innerText), ['línea del apunte']);
        expect(
          filled.single
              .getElement('w:rPr')!
              .getElement('w:shd')!
              .getAttribute('w:fill'),
          'FFF59D',
        );
        final underlined = runs.where(
          (r) => r.getElement('w:rPr')?.getElement('w:u') != null,
        );
        // Empieza y termina en letras: la puntuación de los bordes queda fuera.
        expect(underlined.map((r) => r.innerText).join(), 'amp; y <etiquetas');
        expect(
          underlined.first
              .getElement('w:rPr')!
              .getElement('w:u')!
              .getAttribute('w:color'),
          'FFCC80',
        );
        // El resto de las propiedades de cada run sigue ahí: la fuente.
        expect(
          filled.single
              .getElement('w:rPr')!
              .getElement('w:rFonts')!
              .getAttribute('w:ascii'),
          'Calibri',
        );
        // Y el texto completo, igual.
        expect(
          _document(docx).findAllElements('w:t').map((t) => t.innerText).join(),
          text.replaceAll('\n', '').replaceAll('\t', ''),
        );
      },
    );

    test('un tramo que cruza renglones marca cada párrafo', () async {
      final docx = await writer.write(
        text: text,
        marks: [_mark(text, 'apunte.\n\nSegunda línea')],
      );
      final marked = _document(docx)
          .findAllElements('w:r')
          .where((r) => r.getElement('w:rPr')?.getElement('w:shd') != null);
      expect(marked.map((r) => r.innerText), ['apunte.', 'Segunda línea']);
    });

    test('un tramo que no está se saltea', () async {
      final docx = await writer.write(
        text: text,
        marks: [
          const DocumentMark(
            start: 0,
            end: 4,
            excerpt: 'esto no está',
            color: _yellow,
          ),
        ],
      );
      expect(_document(docx).findAllElements('w:shd'), isEmpty);
    });

    test('con una nota, el comentario sale en el Word', () async {
      final docx = await writer.write(
        text: text,
        marks: [_mark(text, 'Primera línea', note: 'Revisar')],
      );
      final comments = ZipDecoder()
          .decodeBytes(docx)
          .findFile('word/comments.xml');
      expect(utf8.decode(comments!.readBytes()!), contains('Revisar'));
    });

    test('los caracteres de control que XML no admite se descartan', () async {
      final docx = await writer.write(text: 'Hola\u0000 mundo\u0008 raro');
      expect(
        _document(docx).findAllElements('w:t').map((t) => t.innerText).join(),
        'Hola mundo raro',
      );
    });
  });
}
