import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/processed/data/services/pdfium_outline_reader.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Dónde está PDFium: lo trae `tool/fetch_pdfium.sh`. Sin él, las pruebas
/// que abren un PDF de verdad se saltan con un motivo visible.
final _pdfiumPath = Platform.environment['PDFIUM_PATH'];

const _missingPdfium =
    r'Falta PDFIUM_PATH. Correr: export PDFIUM_PATH="$(tool/fetch_pdfium.sh)"';

Future<void> _initialize() async {
  Pdfrx.pdfiumModulePath = _pdfiumPath;
  await pdfrxInitialize();
}

/// Los marcadores de un PDF con PDFium (F46, decisión B): su árbol aplanado
/// en el orden en que se leen, con la profundidad y la página de cada uno, y
/// ubicados en el texto que saca la extracción de siempre.
void main() {
  group('flattenPdfOutline: el árbol, en el orden en que se lee', () {
    PdfOutlineNode node(
      String title, {
      int? page,
      List<PdfOutlineNode> children = const [],
    }) => PdfOutlineNode(
      title: title,
      dest: page == null ? null : PdfDest(page, PdfDestCommand.xyz, null),
      children: children,
    );

    test('cada uno y después los suyos, con su profundidad y su página', () {
      expect(
        flattenPdfOutline([
          node(
            'Parte I',
            page: 1,
            children: [
              node('Capítulo 1', page: 2, children: [node('1.1', page: 3)]),
              node('Capítulo 2', page: 5),
            ],
          ),
          node('Parte II', page: 9),
        ]),
        const [
          PdfBookmark(title: 'Parte I', depth: 1, page: 1),
          PdfBookmark(title: 'Capítulo 1', depth: 2, page: 2),
          PdfBookmark(title: '1.1', depth: 3, page: 3),
          PdfBookmark(title: 'Capítulo 2', depth: 2, page: 5),
          PdfBookmark(title: 'Parte II', depth: 1, page: 9),
        ],
      );
    });

    test('sin destino, sin página; el título, limpio; uno sin título se '
        'queda para que sus hijos cuelguen de él', () {
      expect(
        flattenPdfOutline([
          node(' \u0000', children: [node('  Anexo\r\n A ')]),
        ]),
        const [
          PdfBookmark(title: '', depth: 1),
          PdfBookmark(title: 'Anexo A', depth: 2),
        ],
      );
    });

    test('un árbol muy hondo no agota la pila', () {
      var deepest = node('Hoja', page: 1);
      for (var i = 0; i < 20000; i++) {
        deepest = node('Nivel $i', children: [deepest]);
      }
      final flat = flattenPdfOutline([deepest]);
      expect(flat, hasLength(20001));
      expect(
        flat.last,
        const PdfBookmark(title: 'Hoja', depth: 20001, page: 1),
      );
    });

    test('sin marcadores, ninguno', () {
      expect(flattenPdfOutline(const []), isEmpty);
    });
  });

  group('PdfiumOutlineReader, con un PDF de verdad', () {
    const reader = PdfiumOutlineReader(initialize: _initialize);
    const body =
        'Un parrafo con lo que cuenta el libro, de punta a punta, para que '
        'la pagina tenga su cuerpo.';

    /// Un libro de tres páginas: el índice, la introducción y un capítulo
    /// con una sección. Los títulos de los marcadores llevan tildes; el
    /// texto, no (la letra de base del PDF es Helvetica).
    Future<Uint8List> book({bool withOutline = true}) {
      pw.Widget titled(String text, String mark, int level) => withOutline
          ? pw.Outline(
              name: mark,
              title: text,
              level: level,
              child: pw.Text(mark),
            )
          : pw.Text(mark);
      final document = pw.Document()
        ..addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                pw.Text('Indice'),
                pw.Text('Introduccion'),
                pw.Text('El origen'),
                pw.Text('Los reyes'),
              ],
            ),
          ),
        )
        ..addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                titled('Introducción', 'Introduccion', 0),
                pw.Text(body),
              ],
            ),
          ),
        )
        ..addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                titled('El origen', 'El origen', 0),
                pw.Text(body),
                titled('Los reyes', 'Los reyes', 1),
                pw.Text(body),
              ],
            ),
          ),
        );
      return document.save();
    }

    test('lee cuántas páginas tiene y sus marcadores, con su nivel y su '
        'página', () async {
      final outline = await reader.read(DocumentSource.memory(await book()));
      expect(outline.pageCount, 3);
      expect(outline.bookmarks, const [
        PdfBookmark(title: 'Introducción', depth: 1, page: 2),
        PdfBookmark(title: 'El origen', depth: 1, page: 3),
        PdfBookmark(title: 'Los reyes', depth: 2, page: 3),
      ]);
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('un PDF sin marcadores trae la lista vacía', () async {
      final outline = await reader.read(
        DocumentSource.memory(await book(withOutline: false)),
      );
      expect(outline, PdfOutline(pageCount: 3));
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('lo que no es un PDF no se puede leer', () async {
      await expectLater(
        reader.read(
          DocumentSource.memory(Uint8List.fromList(utf8.encode('no es'))),
        ),
        throwsA(isA<UnreadableDocumentException>()),
      );
    }, skip: _pdfiumPath == null ? _missingPdfium : null);

    test('los marcadores se ubican en el texto que saca la extracción de '
        'siempre, en su página: el índice del libro no se lleva '
        'ninguno', () async {
      final bytes = await book();
      final parsed = await const PdfParser(
        initialize: _initialize,
      ).parse(DocumentSource.memory(bytes));
      final text = parsed.markdown;
      final headings = readProcessedHeadings(
        ProcessedHeadingsSource(
          pages: [for (final page in processedTextPages(text)) page.text],
          kind: ProcessedTextKind.pdf,
          pdf: await reader.read(DocumentSource.memory(bytes)),
        ),
      );
      expect(
        [for (final h in headings) (h.level, h.title, h.pdfPage)],
        [(1, 'Introducción', 2), (1, 'El origen', 3), (2, 'Los reyes', 3)],
      );
      final contents = text.indexOf('Introduccion');
      for (final heading in headings) {
        expect(heading.located, isTrue, reason: heading.title);
        // En el cuerpo, después del índice de la primera página.
        expect(heading.start, greaterThan(contents), reason: heading.title);
      }
      expect(
        text.substring(headings.last.start!, headings.last.end),
        'Los reyes',
      );
    }, skip: _pdfiumPath == null ? _missingPdfium : null);
  });
}
