// El XML de estas pruebas se arma en trozos que se pegan sin espacios: un
// espacio de más entre etiquetas cambiaría el documento que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
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
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/pdf_annotations.dart';
import '../../../../support/sample_files.dart';

/// Las notas sobre el documento entero (F45, paso 8c) en lo que se descarga
/// marcado: al comienzo, como notas del documento, con el mismo estilo de
/// las demás notas de cada formato —en el PDF, notas del PDF arriba a la
/// izquierda de la primera página; en el texto, un bloque con su título—.
/// Cada prueba lee de vuelta el archivo que sale.
const _violet = 0xFF7E57C2;
const _teal = 0xFF00897B;

const _whole = WholeDocumentNotes(
  title: 'Notas del documento',
  notes: [
    WholeDocumentNote(note: 'Repasar entero', color: _violet),
    WholeDocumentNote(note: 'Para el examen\ndel lunes', color: _teal),
  ],
);

DocumentNote _note(String text, String excerpt, String note) {
  final start = text.indexOf(excerpt);
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

/// Los párrafos del cuerpo de un Word: su texto, con «⏎» donde hay un salto
/// de renglón, y su raya de la izquierda, si tiene.
List<({String text, String? left})> _paragraphs(Uint8List docx) => [
  for (final p in _part(docx, 'word/document.xml').findAllElements('w:p'))
    (
      text: [
        for (final e in p.descendantElements)
          if (e.name.qualified == 'w:t')
            e.innerText
          else if (e.name.qualified == 'w:br')
            '⏎',
      ].join(),
      left: p.findAllElements('w:left').firstOrNull?.getAttribute('w:color'),
    ),
];

void main() {
  group('Word: un bloque al comienzo', () {
    final docx = buildDocx(
      body:
          '<w:p><w:r><w:t xml:space="preserve">La revolución francesa.</w:t>'
          '</w:r></w:p>',
    );

    test('el título y cada nota en su párrafo, con la letra de una nota al '
        'pie y la raya de su color, y la raya que lo separa, antes de lo '
        'primero del documento', () async {
      final text = (await const DocxParser().parseBytes(docx)).markdown;
      final marked = await const DocxMarkWriter().write(
        docx: docx,
        text: text,
        marks: const [],
        wholeNotes: _whole,
      );

      final paragraphs = _paragraphs(marked);
      expect(
        [for (final p in paragraphs) p.text],
        [
          'Notas del documento',
          'Repasar entero',
          'Para el examen⏎del lunes',
          '',
          'La revolución francesa.',
        ],
      );
      expect(
        [for (final p in paragraphs) p.left],
        [null, '7E57C2', '00897B', null, null],
      );
      final body = _part(marked, 'word/document.xml');
      final title = body.findAllElements('w:p').first;
      expect(title.findAllElements('w:b'), hasLength(1));
      expect(
        body
            .findAllElements('w:p')
            .elementAt(1)
            .findAllElements('w:sz')
            .first
            .getAttribute('w:val'),
        '20',
      );
      expect(
        body.findAllElements('w:p').elementAt(3).findAllElements('w:bottom'),
        hasLength(1),
      );
    });

    test('con notas sobre pedazos: sus llamadas siguen en su lugar y el '
        'bloque no se cuenta como texto del documento', () async {
      final text = (await const DocxParser().parseBytes(docx)).markdown;
      final marked = await const DocxMarkWriter().write(
        docx: docx,
        text: text,
        marks: const [],
        notes: [_note(text, 'francesa', 'De 1789')],
        wholeNotes: _whole,
      );
      final body = _part(marked, 'word/document.xml');
      expect(body.findAllElements('w:footnoteReference'), hasLength(1));
      expect(_paragraphs(marked).first.text, 'Notas del documento');
    });

    test('sin notas sobre el texto entero, no hay bloque', () async {
      final text = (await const DocxParser().parseBytes(docx)).markdown;
      final marked = await const DocxMarkWriter().write(
        docx: docx,
        text: text,
        marks: const [],
        notes: [_note(text, 'francesa', 'De 1789')],
      );
      expect(
        [for (final p in _paragraphs(marked)) p.text],
        ['La revolución francesa.'],
      );
    });

    test('un texto suelto sale como Word con el bloque al comienzo', () async {
      final marked = await const TextDocxMarkWriter().write(
        text: 'Primera línea.',
        wholeNotes: _whole,
      );
      expect(_paragraphs(marked).first.text, 'Notas del documento');
      expect(_paragraphs(marked).last.text, 'Primera línea.');
    });
  });

  group('Markdown: una cita al comienzo', () {
    const writer = MarkdownMarkWriter();

    test('el título en negrita y cada nota en una viñeta, con sus renglones; '
        'y las notas al pie de los pedazos, como siempre', () {
      const markdown = '# Título\n\nLa revolución francesa.\n';
      final marked = writer.write(
        markdown: markdown,
        text: markdown,
        marks: const [],
        notes: [_note(markdown, 'francesa', 'De 1789')],
        wholeNotes: _whole,
      );
      expect(
        marked,
        '> **Notas del documento**\n'
        '>\n'
        '> - Repasar entero\n'
        '> - Para el examen\n'
        '>   del lunes\n'
        '\n'
        '# Título\n\n'
        'La revolución francesa[^nota-1].\n\n'
        '[^nota-1]: De 1789\n',
      );
    });

    test('después del encabezado `---` del principio', () {
      const markdown = '---\ntitle: Roma\n---\n\nTexto.\n';
      final marked = writer.write(
        markdown: markdown,
        text: markdown,
        marks: const [],
        wholeNotes: _whole,
      );
      expect(marked, startsWith('---\ntitle: Roma\n---\n> **Notas'));
      expect(marked, endsWith('>   del lunes\n\nTexto.\n'));
    });

    test('sin notas sobre el texto entero, nada cambia', () {
      const markdown = 'Texto.\n';
      expect(
        writer.write(markdown: markdown, text: markdown, marks: const []),
        markdown,
      );
    });
  });

  group('EPUB: al comienzo del primer capítulo', () {
    final epub = buildEpub(
      chapters: const [
        (name: 'cap1.xhtml', html: '<h1>Uno</h1><p>La revolución.</p>'),
        (name: 'cap2.xhtml', html: '<h1>Dos</h1><p>El vapor.</p>'),
      ],
    );

    String chapter(Uint8List marked, String name) => utf8.decode(
      ZipDecoder()
          .decodeBytes(marked)
          .files
          .firstWhere((f) => f.name == 'OEBPS/$name')
          .readBytes()!,
    );

    test('el mismo bloque que en la página web, aunque el capítulo no tenga '
        'nada marcado; los demás, como estaban', () async {
      final content = (await const EpubParser().parse(
        DocumentSource.memory(epub, name: 'libro.epub'),
      )).markdown;
      final marked = const EpubMarkWriter().write(
        epub,
        content,
        const [],
        const [],
        _whole,
      );

      final one = XmlDocument.parse(chapter(marked, 'cap1.xhtml'));
      final body = one.findAllElements('body').single;
      final section = body.childElements.first;
      expect(section.name.local, 'section');
      expect(section.getAttribute('aria-label'), 'Notas del documento');
      expect(
        section.findAllElements('strong').single.innerText,
        'Notas del documento',
      );
      final items = section.findAllElements('li').toList();
      expect(items.map((li) => li.innerText), [
        'Repasar entero',
        'Para el examendel lunes',
      ]);
      expect(items[1].findAllElements('br'), hasLength(1));
      expect(items[0].getAttribute('style'), contains('#7e57c2'));
      expect(section.findAllElements('hr'), hasLength(1));
      expect(chapter(marked, 'cap2.xhtml'), isNot(contains('sinapsis-notas')));
    });
  });

  group('Página web: un bloque al comienzo de la página', () {
    test('su título, la lista con la raya de cada color y la raya que lo '
        'separa, antes de lo primero de la página', () {
      const page =
          '<!DOCTYPE html><html><body><article><p>La revolución.</p>'
          '</article></body></html>';
      final marked = const HtmlMarkWriter().write(
        page,
        'La revolución.',
        const [],
        const [],
        _whole,
      );
      final document = html_parser.parse(marked);
      final first = document.body!.children.first;
      expect(first.localName, 'section');
      expect(first.attributes['role'], 'doc-preface');
      expect(first.attributes['aria-label'], 'Notas del documento');
      expect(first.querySelector('strong')!.text, 'Notas del documento');
      final items = first.querySelectorAll('li');
      expect(items.map((li) => li.text), [
        'Repasar entero',
        'Para el examendel lunes',
      ]);
      expect(items[1].attributes['style'], contains('#00897b'));
      expect(first.querySelector('hr'), isNotNull);
      expect(document.querySelector('article p')!.text, 'La revolución.');
    });
  });

  group('PDF: notas del PDF arriba a la izquierda', () {
    setUpAll(() async {
      Pdfrx.pdfiumModulePath = pdfiumPath;
      await pdfrxInitialize();
    });

    test('cada nota sobre el documento entero es una nota del estándar de su '
        'color, con lo que dice y el título del bloque, en la primera página, '
        'una al lado de la otra, sin marcar nada', () async {
      final pdf = buildPdf(pageTexts: ['Hola mundo', 'Segunda']);
      final marked = await const PdfDocumentMarker().mark(
        pdf,
        content: 'Hola mundo\n\n---\n\nSegunda',
        marks: const [],
        wholeNotes: _whole,
      );

      final [first, second] = await readAnnotations(marked);
      expect(second, isEmpty);
      expect(first.map((a) => a.subtype), [
        pdfium_bindings.FPDF_ANNOT_TEXT,
        pdfium_bindings.FPDF_ANNOT_TEXT,
      ]);
      expect(first.map((a) => a.note), [
        'Repasar entero',
        'Para el examen\ndel lunes',
      ]);
      expect(first.every((a) => a.quads.isEmpty), isTrue);
      expect(await _title(marked, 0), 'Notas del documento');
      final one = await annotationRect(marked, index: 0);
      final two = await annotationRect(marked, index: 1);
      expect(one.left, 8);
      expect(two.left, greaterThan(one.right));
      expect(two.top, one.top);
      expect(one.top, greaterThan(700));
    });
  }, skip: pdfiumPath == null ? missingPdfium : null);
}

/// El título (`T`) de la anotación [index] de la primera página de [pdf].
Future<String> _title(Uint8List pdf, int index) async {
  final document = await PdfDocument.openData(pdf);
  try {
    return await document.useNativeDocumentHandle(
      (handle) => using((arena) {
        final pdfium = pdfium_bindings.getPdfium(modulePath: pdfiumPath);
        final doc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
        final page = pdfium.FPDF_LoadPage(doc, 0);
        final annot = pdfium.FPDFPage_GetAnnot(page, index);
        final key = 'T'.toNativeUtf8(allocator: arena).cast<Char>();
        final bytes = pdfium.FPDFAnnot_GetStringValue(annot, key, nullptr, 0);
        final buffer = arena<Uint16>(bytes ~/ 2 + 1);
        pdfium
          ..FPDFAnnot_GetStringValue(annot, key, buffer.cast(), bytes)
          ..FPDFPage_CloseAnnot(annot)
          ..FPDF_ClosePage(page);
        return String.fromCharCodes(
          buffer.asTypedList(bytes ~/ 2).takeWhile((unit) => unit != 0),
        );
      }),
    );
  } finally {
    await document.dispose();
  }
}
