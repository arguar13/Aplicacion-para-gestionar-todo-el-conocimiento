// El XML de estas pruebas se arma en trozos que se pegan sin espacios: un
// espacio de más entre etiquetas cambiaría el documento que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/export/data/marked/docx_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/epub_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/html_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/markdown_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/pdf_document_marker.dart';
import 'package:sinapsis/features/export/data/marked/text_docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/pdf_annotations.dart';
import '../../../../support/sample_files.dart';

/// Las notas en el texto (F45, mejora 19) en lo que se descarga marcado: en
/// el PDF, notas del PDF —las que se abren con un toque—; en el texto (Word,
/// Markdown, un texto suelto, un EPUB y una página), notas al pie. Cada
/// prueba lee de vuelta el archivo que sale.
const _violet = 0xFF7E57C2;
const _yellow = 0xFFFFF59D;

DocumentNote _note(String text, String excerpt, String note, {int from = 0}) {
  final start = text.indexOf(excerpt, from);
  expect(start, isNonNegative, reason: '«$excerpt» no está en el texto');
  return DocumentNote(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    note: note,
    color: _violet,
  );
}

XmlDocument _part(Uint8List zip, String name) {
  final file = ZipDecoder().decodeBytes(zip).findFile(name);
  expect(file, isNotNull, reason: 'falta $name');
  return XmlDocument.parse(utf8.decode(file!.readBytes()!));
}

/// Las notas al pie de la persona en un Word: id y texto, sin los
/// separadores.
Map<String, String> _footnotes(Uint8List docx) => {
  for (final f in _part(
    docx,
    'word/footnotes.xml',
  ).findAllElements('w:footnote'))
    if (f.getAttribute('w:type') == null)
      f.getAttribute('w:id')!: f
          .findAllElements('w:p')
          .map((p) => p.findAllElements('w:t').map((t) => t.innerText).join())
          .join('\n'),
};

/// Lo que se lee del cuerpo de un Word, con `[^id]` donde va cada llamada.
String _bodyWithCalls(Uint8List docx) {
  final out = StringBuffer();
  for (final e in _part(
    docx,
    'word/document.xml',
  ).rootElement.descendantElements) {
    if (e.name.qualified == 'w:t') out.write(e.innerText);
    if (e.name.qualified == 'w:footnoteReference') {
      out.write('[^${e.getAttribute('w:id')}]');
    }
  }
  return out.toString();
}

void main() {
  group('Word: notas al pie', () {
    const writer = DocxMarkWriter();
    final docx = buildDocx(
      body:
          '<w:p><w:r><w:t xml:space="preserve">La revolución </w:t></w:r>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>francesa</w:t></w:r>'
          '<w:r><w:t xml:space="preserve"> cambió el mundo.</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>La Bastilla cayó en 1789.</w:t></w:r></w:p>',
    );

    test('la llamada va justo después del pedazo —también en medio de un '
        'run, que se parte con sus propiedades— y la nota, en las notas al '
        'pie, con su relación y su tipo de contenido', () async {
      final text = (await const DocxParser().parseBytes(docx)).markdown;

      final marked = await writer.write(
        docx: docx,
        text: text,
        marks: const [],
        notes: [
          _note(text, 'revolución', 'Una de tantas'),
          _note(text, 'francesa', 'La de 1789\nY sus ideas'),
          _note(text, 'Bastilla', 'Una cárcel'),
        ],
      );

      expect(
        _bodyWithCalls(marked),
        'La revolución[^1] francesa[^2] cambió el mundo.'
        'La Bastilla[^3] cayó en 1789.',
      );
      expect(_footnotes(marked), {
        '1': ' Una de tantas',
        '2': ' La de 1789\nY sus ideas',
        '3': ' Una cárcel',
      });
      // «francesa» sigue en negrita: el run que la tiene no se tocó.
      final bold = _part(marked, 'word/document.xml')
          .findAllElements('w:r')
          .where((r) => r.getElement('w:rPr')?.getElement('w:b') != null)
          .map((r) => r.findAllElements('w:t').map((t) => t.innerText).join());
      expect(bold, ['francesa']);
      // El resto de «La revolución », partido, conserva su espacio.
      expect(
        _part(
          marked,
          'word/document.xml',
        ).findAllElements('w:t').map((t) => t.innerText).take(2),
        ['La revolución', ' '],
      );
      final rels = _part(
        marked,
        'word/_rels/document.xml.rels',
      ).findAllElements('Relationship').map((r) => r.getAttribute('Type')!);
      expect(rels, contains(endsWith('/footnotes')));
      final types = utf8.decode(
        ZipDecoder()
            .decodeBytes(marked)
            .findFile('[Content_Types].xml')!
            .readBytes()!,
      );
      expect(types, contains('footnotes+xml'));
      // Y el lector de la app lo lee de vuelta: el texto, con cada llamada
      // en su lugar, y las notas al pie con lo que dicen.
      final read = (await const DocxParser().parseBytes(marked)).markdown;
      expect(
        read,
        startsWith('La revolución[^1] **francesa**[^2] cambió el mundo.'),
      );
      expect(read, contains('[^2]: La de 1789'));
      expect(read, contains('[^3]: Una cárcel'));
    });

    test(
      'un resaltado con su nota (comentario) y una nota en el texto (nota '
      'al pie) sobre el mismo pedazo conviven, cada uno con su relación',
      () async {
        final text = (await const DocxParser().parseBytes(docx)).markdown;
        final start = text.indexOf('Bastilla');

        final marked = await writer.write(
          docx: docx,
          text: text,
          marks: [
            DocumentMark(
              start: start,
              end: start + 8,
              excerpt: 'Bastilla',
              color: _yellow,
              note: 'Comentario',
            ),
          ],
          notes: [_note(text, 'Bastilla', 'Al pie')],
        );

        expect(_footnotes(marked).values, [' Al pie']);
        expect(
          _part(
            marked,
            'word/comments.xml',
          ).findAllElements('w:t').single.innerText,
          'Comentario',
        );
        final rels = _part(marked, 'word/_rels/document.xml.rels')
            .findAllElements('Relationship')
            .map((r) => r.getAttribute('Type')!)
            .toList();
        expect(rels.where((t) => t.endsWith('/comments')), hasLength(1));
        expect(rels.where((t) => t.endsWith('/footnotes')), hasLength(1));
        // El pedazo sigue pintado.
        expect(_bodyWithCalls(marked), contains('Bastilla[^1]'));
      },
    );

    test(
      'un Word que ya tenía notas al pie suma las nuevas sin pisarlas',
      () async {
        final withNotes = buildDocx(
          body:
              '<w:p><w:r><w:t>Hola mundo.</w:t></w:r><w:r><w:rPr><w:vertAlign '
              'w:val="superscript"/></w:rPr><w:footnoteReference w:id="1"/>'
              '</w:r></w:p>',
          parts: {
            'word/footnotes.xml': wordPart(
              'w:footnotes',
              '<w:footnote w:type="separator" w:id="-1"><w:p/></w:footnote>'
                  '<w:footnote w:id="1"><w:p><w:r><w:t>Del autor</w:t></w:r>'
                  '</w:p></w:footnote>',
            ),
            'word/_rels/document.xml.rels':
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/'
                'package/2006/relationships"><Relationship Id="rId7" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships/footnotes" Target="footnotes.xml"/>'
                '</Relationships>',
          },
        );
        final text = (await const DocxParser().parseBytes(withNotes)).markdown;

        final marked = await writer.write(
          docx: withNotes,
          text: text,
          marks: const [],
          notes: [_note(text, 'mundo', 'Mía')],
        );

        expect(_footnotes(marked), {'1': 'Del autor', '2': ' Mía'});
        expect(_bodyWithCalls(marked), 'Hola mundo[^2].[^1]');
      },
    );

    test('un texto suelto sale como Word con sus notas al pie', () async {
      const text = 'Primera línea.\nLa Bastilla cayó.';
      final marked = await const TextDocxMarkWriter().write(
        text: text,
        notes: [_note(text, 'Bastilla', 'En 1789')],
      );

      expect(_footnotes(marked), {'1': ' En 1789'});
      expect(_bodyWithCalls(marked), 'Primera línea.La Bastilla[^1] cayó.');
    });
  });

  group('Markdown: notas al pie', () {
    const writer = MarkdownMarkWriter();

    test('la llamada después del pedazo y las notas al final, en el orden del '
        'texto, con sus renglones; junto con un resaltado', () {
      const markdown = '# Título\n\nLa revolución francesa cambió el mundo.\n';
      final start = markdown.indexOf('revolución');

      final marked = writer.write(
        markdown: markdown,
        text: markdown,
        marks: [
          DocumentMark(
            start: start,
            end: start + 'revolución francesa'.length,
            excerpt: 'revolución francesa',
            color: _yellow,
          ),
        ],
        notes: [
          _note(markdown, 'mundo', 'Todo\nel mundo'),
          _note(markdown, 'francesa', 'De 1789'),
        ],
      );

      expect(
        marked,
        '# Título\n\n'
        'La ==revolución francesa==[^nota-1] cambió el mundo[^nota-2].\n\n'
        '[^nota-1]: De 1789\n'
        '[^nota-2]: Todo\n'
        '    el mundo\n',
      );
    });

    test('nunca dentro de la sintaxis: después de un código, de la dirección '
        'de un enlace y de un bloque de código, en un renglón propio', () {
      const markdown =
          'Usá `print` y [el sitio](https://a.org/x) hoy.\n\n'
          '```\ncódigo suelto\n```\nFin.';

      final marked = writer.write(
        markdown: markdown,
        text: markdown,
        marks: const [],
        notes: [
          _note(markdown, 'prin', 'Del código'),
          _note(markdown, 'a.org', 'De la dirección'),
          _note(markdown, 'suelto', 'Del bloque'),
        ],
      );

      expect(marked, contains('`print`[^nota-1]'));
      expect(marked, contains('(https://a.org/x)[^nota-2]'));
      expect(marked, contains('```\n[^nota-3]\n\nFin.'));
    });

    test('las etiquetas no pisan las notas al pie que ya tenía', () {
      const markdown = 'Hola mundo.[^nota-1]\n\n[^nota-1]: Del autor\n';

      final marked = writer.write(
        markdown: markdown,
        text: markdown,
        marks: const [],
        notes: [_note(markdown, 'mundo', 'Mía')],
      );

      expect(marked, contains('mundo[^sinapsis-nota-1]'));
      expect(marked, endsWith('[^sinapsis-nota-1]: Mía\n'));
      expect(marked, contains('[^nota-1]: Del autor'));
    });
  });

  group('EPUB: notas al pie de EPUB 3', () {
    final epub = buildEpub(
      chapters: const [
        (
          name: 'cap1.xhtml',
          html: '<h1>Uno</h1><p>La <b>revolución</b> industrial.</p>',
        ),
        (
          name: 'cap2.xhtml',
          html: '<h1>Dos</h1><p>El vapor movió fábricas.</p>',
        ),
      ],
    );

    test('la llamada después del pedazo, la nota en un aside al final de su '
        'capítulo, numeradas en el orden del libro', () async {
      final content = (await const EpubParser().parse(
        DocumentSource.memory(epub, name: 'libro.epub'),
      )).markdown;

      final marked = const EpubMarkWriter().write(epub, content, const [], [
        _note(content, 'vapor', 'Watt'),
        _note(content, 'revolución', 'Inglesa'),
      ]);

      String chapter(String name) => utf8.decode(
        ZipDecoder()
            .decodeBytes(marked)
            .files
            .firstWhere((f) => f.name == 'OEBPS/$name')
            .readBytes()!,
      );
      final one = XmlDocument.parse(chapter('cap1.xhtml'));
      final two = XmlDocument.parse(chapter('cap2.xhtml'));
      const ops = 'http://www.idpf.org/2007/ops';

      final call = one
          .findAllElements('a')
          .firstWhere(
            (a) => a.getAttribute('type', namespace: ops) == 'noteref',
          );
      expect(call.innerText, '1');
      expect(call.getAttribute('href'), '#sinapsis-nota-1');
      expect(call.parentElement!.name.local, 'sup');
      // Justo después de la palabra, adentro de la negrita.
      expect(call.parentElement!.parentElement!.name.local, 'b');
      final aside = one.findAllElements('aside').single;
      expect(aside.getAttribute('type', namespace: ops), 'footnote');
      expect(aside.getAttribute('id'), 'sinapsis-nota-1');
      expect(aside.innerText, '1. Inglesa');

      expect(two.findAllElements('aside').single.innerText, '2. Watt');
      expect(two.findAllElements('sup').single.innerText, '2');
    });
  });

  group('Página web: notas al pie', () {
    test('la llamada después del pedazo y las notas al final de la página, '
        'con su vuelta', () {
      const page =
          '<!DOCTYPE html><html><body><article><p>La <b>revolución</b> '
          'industrial cambió todo.</p></article></body></html>';
      const content = 'La **revolución** industrial cambió todo.';

      final marked = const HtmlMarkWriter().write(page, content, const [], [
        _note(content, 'industrial', 'Inglesa\ny textil'),
      ]);

      final document = html_parser.parse(marked);
      final call = document.querySelector('a[role="doc-noteref"]')!;
      expect(call.text, '1');
      expect(call.attributes['href'], '#sinapsis-nota-1');
      expect(
        document.querySelector('article p')!.text,
        'La revolución industrial1 cambió todo.',
      );
      final note = document.querySelector('#sinapsis-nota-1')!;
      expect(note.text, 'Inglesay textil ↩');
      expect(note.querySelectorAll('br'), hasLength(1));
      expect(
        note.querySelector('a[role="doc-backlink"]')!.attributes['href'],
        '#sinapsis-llamada-1',
      );
    });
  });

  group('PDF: notas del PDF', () {
    setUpAll(() async {
      Pdfrx.pdfiumModulePath = pdfiumPath;
      await pdfrxInitialize();
    });

    test('cada nota es una nota del estándar —el ícono que se abre con un '
        'toque— con lo que dice, en el margen a la altura del renglón, y su '
        'pedazo subrayado de su color, sin repetir la nota', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo']);
      const content = 'Hola mundo';

      final marked = await const PdfDocumentMarker().mark(
        pdf,
        content: content,
        marks: const [],
        notes: [_note(content, 'mundo', 'Acá — con acento')],
      );

      final [annotations] = await readAnnotations(marked);
      expect(annotations, hasLength(2));
      final underline = annotations.firstWhere(
        (a) => a.subtype == pdfium_bindings.FPDF_ANNOT_UNDERLINE,
      );
      expect(underline.note, isEmpty);
      final mundo = await lettersRect(pdf, start: 5, end: 10);
      expect(underline.quads.single.left, closeTo(mundo.left, 0.01));

      final note = annotations.firstWhere(
        (a) => a.subtype == pdfium_bindings.FPDF_ANNOT_TEXT,
      );
      expect(note.note, 'Acá — con acento');
      expect(note.flags & pdfium_bindings.FPDF_ANNOT_FLAG_PRINT, isNot(0));
      expect(note.flags & pdfium_bindings.FPDF_ANNOT_FLAG_NOZOOM, isNot(0));
      expect(note.appearance, greaterThan(2));
      final rect = await annotationRect(marked, index: 1);
      expect(rect.right, lessThanOrEqualTo(612));
      expect(rect.left, greaterThan(mundo.right));
      expect(rect.top, closeTo(mundo.top, 1));
    });

    test(
      'un resaltado con nota y una nota en el texto: cada uno lo suyo',
      () async {
        final pdf = buildPdf(pageTexts: ['Hola mundo']);
        const content = 'Hola mundo';

        final marked = await const PdfDocumentMarker().mark(
          pdf,
          content: content,
          marks: const [
            DocumentMark(
              start: 0,
              end: 4,
              excerpt: 'Hola',
              color: _yellow,
              note: 'Del resaltado',
            ),
          ],
          notes: [_note(content, 'mundo', 'De la nota')],
        );

        final [annotations] = await readAnnotations(marked);
        expect(
          {for (final a in annotations) a.subtype: a.note},
          {
            pdfium_bindings.FPDF_ANNOT_HIGHLIGHT: 'Del resaltado',
            pdfium_bindings.FPDF_ANNOT_UNDERLINE: '',
            pdfium_bindings.FPDF_ANNOT_TEXT: 'De la nota',
          },
        );
      },
    );
  }, skip: pdfiumPath == null ? missingPdfium : null);
}
