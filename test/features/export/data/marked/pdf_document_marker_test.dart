import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/pdf_document_marker.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';

import '../../../../support/pdf_annotations.dart';

const _turquoise = 0xFF4DD0E1;
const _orange = 0xFFFFB74D;

/// Una página del PDF de prueba: sus renglones de letras, uno bajo el otro, y
/// si va girada.
class _Page {
  const _Page(this.lines) : rotate = 0;

  /// Una página escaneada: sin letras, y sin tinta, para que el color de lo
  /// marcado se pueda buscar entre píxeles blancos.
  const _Page.blank({this.rotate = 0}) : lines = const [];

  final List<String> lines;
  final int rotate;
}

/// Un PDF de verdad con renglones de 24 puntos, separados 40 puntos, desde
/// arriba: lo que hace falta para probar un tramo en varios renglones, que
/// `buildPdf` —un solo renglón por página— no puede.
Uint8List _buildPdf(List<_Page> pages) {
  const font =
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>';
  final objects = <String>['<< /Type /Catalog /Pages 2 0 R >>', '', font];
  final refs = <String>[];
  for (final page in pages) {
    final number = objects.length + 1;
    refs.add('$number 0 R');
    final stream = [
      for (var i = 0; i < page.lines.length; i++)
        'BT /F1 24 Tf 72 ${700 - 40 * i} Td (${page.lines[i]}) Tj ET',
    ].join('\n');
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '${page.rotate == 0 ? '' : '/Rotate ${page.rotate} '}'
        '/Resources << /Font << /F1 3 0 R >> >> '
        '/Contents ${number + 1} 0 R >>',
      )
      ..add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }
  objects[1] =
      '<< /Type /Pages /Kids [${refs.join(' ')}] /Count ${pages.length} >>';

  final body = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(body.length);
    body.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = body.length;
  body
    ..write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n')
    ..writeAll([
      for (final offset in offsets)
        '${offset.toString().padLeft(10, '0')} 00000 n \n',
    ])
    ..write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
  return Uint8List.fromList(latin1.encode(body.toString()));
}

/// El texto extraído de [pdf] como lo deja `PdfParser`: las páginas, con el
/// texto limpio, unidas por el separador. El de las páginas de [ocr] (por
/// índice, desde 0) es el que reconoció un OCR, no el del PDF.
Future<String> _extractedText(
  Uint8List pdf, {
  Map<int, String> ocr = const {},
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final texts = <String>[];
    for (var i = 0; i < document.pages.length; i++) {
      final raw = (await document.pages[i].loadText())?.fullText ?? '';
      texts.add(ocr[i] ?? cleanPdfPageText(raw));
    }
    return texts.join(pdfPageSeparator);
  } finally {
    await document.dispose();
  }
}

/// Dónde están en la página [pageNumber] las letras de [text], leídas del PDF
/// sin pasar por nada de la app.
Future<PdfRect> _rectOf(
  Uint8List pdf,
  String text, {
  int pageNumber = 1,
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final raw = (await document.pages[pageNumber - 1].loadText())!;
    final at = raw.fullText.indexOf(text);
    expect(at, greaterThanOrEqualTo(0), reason: '«$text» no está en la página');
    return raw.charRects
        .sublist(at, at + text.length)
        .reduce((a, b) => a.merge(b));
  } finally {
    await document.dispose();
  }
}

/// El tramo de [content] que es [excerpt] (la [occurrence]-ésima vez que
/// aparece, desde 0), como lo armaría quien marca.
DocumentMark _mark(
  String content,
  String excerpt, {
  int color = _turquoise,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
  int occurrence = 0,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = content.indexOf(excerpt, start + 1);
  }
  expect(start, greaterThanOrEqualTo(0), reason: '«$excerpt» no está');
  return DocumentMark(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    color: color,
    style: style,
    note: note,
  );
}

void _expectRect(PdfRect actual, PdfRect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.right, closeTo(expected.right, 0.01));
  expect(actual.bottom, closeTo(expected.bottom, 0.01));
}

/// Dónde, en píxeles de la página [pageNumber] pintada como la ve el lector,
/// hay píxeles de [color]: de la primera a la última fila y columna con
/// alguno, o `null` si no hay ninguno.
Future<({int top, int bottom, int left, int right})?> _paintedArea(
  Uint8List pdf,
  int color, {
  int pageNumber = 1,
}) async {
  final document = await PdfDocument.openData(pdf);
  try {
    final page = document.pages[pageNumber - 1];
    final image = await page.render(
      fullWidth: page.width,
      fullHeight: page.height,
      backgroundColor: 0xFFFFFFFF,
    );
    try {
      final pixels = image!.pixels;
      bool near(int value, int channel) => (value - channel).abs() <= 3;
      int? top;
      int? bottom;
      int? left;
      int? right;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final at = (y * image.width + x) * 4;
          if (near(pixels[at], color & 0xff) &&
              near(pixels[at + 1], (color >> 8) & 0xff) &&
              near(pixels[at + 2], (color >> 16) & 0xff)) {
            top ??= y;
            bottom = y;
            left = left == null || x < left ? x : left;
            right = right == null || x > right ? x : right;
          }
        }
      }
      if (top == null) return null;
      return (top: top, bottom: bottom!, left: left!, right: right!);
    } finally {
      image?.dispose();
    }
  } finally {
    await document.dispose();
  }
}

void main() {
  // Cada prueba pasa por PDFium de verdad: sin la librería no hay nada que
  // probar, y se dice por qué en vez de quedar en verde.
  group(
    'PdfDocumentMarker',
    _tests,
    skip: pdfiumPath == null ? missingPdfium : null,
  );
}

void _tests() {
  const marker = PdfDocumentMarker();

  setUpAll(() async {
    Pdfrx.pdfiumModulePath = pdfiumPath;
    await pdfrxInitialize();
  });

  late Uint8List book;
  late String content;
  setUp(() async {
    book = _buildPdf(const [
      _Page(['Primera linea', 'Segunda linea', 'Tercera linea']),
      _Page(['Cuarta linea', 'Quinta linea']),
    ]);
    content = await _extractedText(book);
  });

  group('sobre las letras', () {
    test('el resaltado cae sobre las letras del tramo, y no sobre las de al '
        'lado', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [_mark(content, 'Segunda')],
      );

      final [first, second] = await readAnnotations(marked);
      expect(second, isEmpty);
      final annotation = first.single;
      expect(annotation.subtype, pdfium_bindings.FPDF_ANNOT_HIGHLIGHT);
      expect(annotation.appearance, greaterThan(2));
      final segunda = await _rectOf(book, 'Segunda');
      _expectRect(annotation.quads.single, segunda);
      // Solo «Segunda»: ni el «linea» que sigue ni los otros renglones.
      final line = await _rectOf(book, 'Segunda linea');
      expect(annotation.quads.single.right, lessThan(line.right - 10));
      // Y el lector lo pinta ahí, con el color del tramo.
      expect(await pixelsOf(marked, segunda, _turquoise), greaterThan(0));
      expect(
        await pixelsOf(marked, await _rectOf(book, 'Tercera'), _turquoise),
        0,
      );
    });

    test('un tramo en varios renglones: un cuadrilátero por renglón, en una '
        'sola anotación', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [_mark(content, 'linea\nSegunda linea\nTercera')],
      );

      final [first, _] = await readAnnotations(marked);
      final quads = first.single.quads;
      expect(quads, hasLength(3));
      _expectRect(quads[0], await _rectOf(book, 'linea'));
      _expectRect(quads[1], await _rectOf(book, 'Segunda linea'));
      _expectRect(quads[2], await _rectOf(book, 'Tercera'));
    });

    test('un tramo que cruza de página: una anotación en cada una, y nada '
        'sobre el separador', () async {
      final start = content.indexOf('Tercera');
      final end = content.indexOf('Cuarta') + 'Cuarta'.length;
      final spanning = DocumentMark(
        start: start,
        end: end,
        excerpt: content.substring(start, end),
        color: _orange,
        note: 'cruza',
      );

      final marked = await marker.mark(
        book,
        content: content,
        marks: [spanning],
      );

      final [first, second] = await readAnnotations(marked);
      _expectRect(
        first.single.quads.single,
        await _rectOf(book, 'Tercera linea'),
      );
      _expectRect(
        second.single.quads.single,
        await _rectOf(book, 'Cuarta', pageNumber: 2),
      );
      // El color del tramo, en las dos páginas.
      expect(
        await pixelsOf(marked, await _rectOf(book, 'Tercera'), _orange),
        greaterThan(0),
      );
      expect(
        await pixelsOf(
          marked,
          await _rectOf(book, 'Cuarta', pageNumber: 2),
          _orange,
          pageNumber: 2,
        ),
        greaterThan(0),
      );
      expect(first.single.note, 'cruza');
      expect(second.single.note, 'cruza');
    });

    test('el subrayado sale como una anotación de subrayado', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [_mark(content, 'Cuarta', style: HighlightStyle.underline)],
      );

      final [first, second] = await readAnnotations(marked);
      expect(first, isEmpty);
      expect(second.single.subtype, pdfium_bindings.FPDF_ANNOT_UNDERLINE);
      _expectRect(
        second.single.quads.single,
        await _rectOf(book, 'Cuarta', pageNumber: 2),
      );
    });

    test('la nota viaja con la anotación', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [_mark(content, 'Quinta', note: 'Revisar — con acento')],
      );

      final [_, second] = await readAnnotations(marked);
      expect(second.single.note, 'Revisar — con acento');
    });

    test('dos tramos que se pisan salen los dos enteros: la palabra clave no '
        'le quita renglón a su oración', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [
          _mark(content, 'Segunda linea', color: _orange),
          _mark(content, 'Segunda'),
        ],
      );

      final [first, _] = await readAnnotations(marked);
      expect(first, hasLength(2));
      _expectRect(first[0].quads.single, await _rectOf(book, 'Segunda linea'));
      _expectRect(first[1].quads.single, await _rectOf(book, 'Segunda'));
    });

    test('varios tramos de la misma página: cada uno en su lugar', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [
          _mark(content, 'linea', occurrence: 2),
          _mark(content, 'Primera'),
        ],
      );

      final [first, _] = await readAnnotations(marked);
      expect(first, hasLength(2));
      // El «linea» del tercer renglón, no el del primero.
      expect(
        first[0].quads.single.top,
        closeTo((await _rectOf(book, 'Tercera linea')).top, 0.01),
      );
      _expectRect(first[1].quads.single, await _rectOf(book, 'Primera'));
    });

    test('un texto con letras acentuadas y con la ñ cae donde va', () async {
      final accented = _buildPdf(const [
        _Page([r'Educaci\363n y a\361os']),
      ]);
      final text = await _extractedText(accented);
      expect(text, contains('Educación'));

      final marked = await marker.mark(
        accented,
        content: text,
        marks: [_mark(text, 'años')],
      );

      final [page] = await readAnnotations(marked);
      _expectRect(page.single.quads.single, await _rectOf(accented, 'años'));
    });
  });

  group('un tramo que no se puede ubicar', () {
    test('se saltea, y los demás se marcan igual', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [
          const DocumentMark(
            start: 0,
            end: 11,
            excerpt: 'No está acá',
            color: _turquoise,
          ),
          _mark(content, 'Quinta'),
        ],
      );

      final [first, second] = await readAnnotations(marked);
      expect(first, isEmpty);
      expect(second, hasLength(1));
    });

    test('sin ningún tramo que ubicar, el PDF sale tal cual', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [
          const DocumentMark(
            start: 5000,
            end: 5004,
            excerpt: 'nada',
            color: _turquoise,
          ),
          const DocumentMark(start: 4, end: 4, excerpt: '', color: _turquoise),
        ],
      );

      expect(marked, book);
      expect(await marker.mark(book, content: content, marks: []), book);
    });

    test('con posiciones que ya no son las de su texto, se busca el texto '
        'más cerca de donde estaba', () async {
      // «linea» está en cinco renglones; el tramo dice estar cerca del
      // cuarto, pero las posiciones se corrieron.
      final fourth = content.indexOf('Cuarta linea') + 'Cuarta '.length;
      final moved = DocumentMark(
        start: fourth + 2,
        end: fourth + 7,
        excerpt: 'linea',
        color: _turquoise,
      );

      final marked = await marker.mark(book, content: content, marks: [moved]);

      final [first, second] = await readAnnotations(marked);
      expect(first, isEmpty);
      _expectRect(
        second.single.quads.single,
        await _rectOf(book, 'linea', pageNumber: 2),
      );
    });

    test('con posiciones fuera del texto, también lo encuentra', () async {
      final moved = DocumentMark(
        start: content.length + 50,
        end: content.length + 55,
        excerpt: 'Quinta',
        color: _turquoise,
      );

      final marked = await marker.mark(book, content: content, marks: [moved]);

      final [_, second] = await readAnnotations(marked);
      _expectRect(
        second.single.quads.single,
        await _rectOf(book, 'Quinta', pageNumber: 2),
      );
    });

    test('tramos en páginas distintas: cada página lleva el suyo', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [_mark(content, 'Primera'), _mark(content, 'Cuarta')],
      );

      final [first, second] = await readAnnotations(marked);
      _expectRect(first.single.quads.single, await _rectOf(book, 'Primera'));
      _expectRect(
        second.single.quads.single,
        await _rectOf(book, 'Cuarta', pageNumber: 2),
      );
    });

    test('con posiciones que no son las suyas, se prefiere la aparición de '
        'su texto que queda más cerca, antes o después', () async {
      final fifth = content.indexOf('Quinta linea') + 'Quinta '.length;
      // Tres letras antes del «linea» del quinto renglón: ese es el más
      // cercano, y no el del cuarto.
      final before = DocumentMark(
        start: fifth - 3,
        end: fifth + 2,
        excerpt: 'linea',
        color: _turquoise,
      );
      // Y desde el principio del texto, la única aparición cercana es la
      // de más adelante.
      final fromStart = DocumentMark(
        start: -5,
        end: 3,
        excerpt: 'Quinta',
        color: _orange,
      );

      final marked = await marker.mark(
        book,
        content: content,
        marks: [before, fromStart],
      );

      final [first, second] = await readAnnotations(marked);
      expect(first, isEmpty);
      final quinta = await _rectOf(book, 'Quinta', pageNumber: 2);
      expect(second, hasLength(2));
      final line = await _rectOf(book, 'Quinta linea', pageNumber: 2);
      expect(second[0].quads.single.right, closeTo(line.right, 0.01));
      expect(second[0].quads.single.left, greaterThan(quinta.right));
      _expectRect(second[1].quads.single, quinta);
    });

    test('si el texto del tramo difiere solo en los espacios, se confía en '
        'sus posiciones', () async {
      const lines = 'linea\nSegunda';
      final start = content.indexOf(lines);
      final joined = DocumentMark(
        start: start,
        end: start + lines.length,
        excerpt: 'linea  Segunda',
        color: _turquoise,
      );

      final marked = await marker.mark(book, content: content, marks: [joined]);

      final [first, _] = await readAnnotations(marked);
      expect(first.single.quads, hasLength(2));
    });

    test('si el tramo cayó en blanco, entre renglones, no deja nada', () async {
      final marked = await marker.mark(
        book,
        content: content,
        marks: [
          DocumentMark(
            start: content.indexOf(pdfPageSeparator),
            end: content.indexOf(pdfPageSeparator) + pdfPageSeparator.length,
            excerpt: pdfPageSeparator,
            color: _turquoise,
          ),
        ],
      );

      expect(marked, book);
    });
  });

  group('una página escaneada', () {
    // Cuatro renglones que reconoció un OCR sobre una foto: la página no
    // tiene esas letras.
    const ocr = 'Uno\nDos\nTres\nCuatro';

    test('lleva un recuadro de color en el lugar aproximado del renglón: más '
        'abajo cuanto más abajo está en el texto', () async {
      final scan = _buildPdf(const [
        _Page.blank(),
        _Page(['Con letras']),
      ]);
      final text = await _extractedText(scan, ocr: {0: ocr});

      final marked = await marker.mark(
        scan,
        content: text,
        marks: [
          _mark(text, 'Dos'),
          _mark(text, 'Cuatro', color: _orange),
        ],
      );

      final [first, second] = await readAnnotations(marked);
      expect(second, isEmpty);
      expect(first, hasLength(2));
      final dos = first[0].quads.single;
      final cuatro = first[1].quads.single;
      // Dentro de la página y entre márgenes, a todo el ancho.
      expect(dos.left, closeTo(612 * 0.08, 0.01));
      expect(dos.right, closeTo(612 * 0.92, 0.01));
      expect(dos.top, lessThan(792 * 0.94));
      expect(cuatro.bottom, greaterThan(792 * 0.06));
      // El segundo renglón de cuatro está arriba del cuarto, y los dos
      // renglones son recuadros apartados.
      expect(dos.top, greaterThan(cuatro.top));
      expect(dos.bottom, greaterThan(cuatro.top));
      // Y se ve: el lector los pinta donde dicen.
      final dosArea = (await _paintedArea(marked, _turquoise))!;
      final cuatroArea = (await _paintedArea(marked, _orange))!;
      expect(dosArea.bottom, lessThan(cuatroArea.top));
      expect(dosArea.left, closeTo(612 * 0.08, 2));
      expect(dosArea.right, closeTo(612 * 0.92, 2));
      expect(dosArea.top, closeTo(792 - dos.top, 2));
    });

    test(
      'un tramo en dos renglones de la foto: un recuadro por renglón',
      () async {
        final scan = _buildPdf(const [_Page.blank()]);
        final text = await _extractedText(scan, ocr: {0: ocr});

        final marked = await marker.mark(
          scan,
          content: text,
          marks: [_mark(text, 'Dos\nTres')],
        );

        final [page] = await readAnnotations(marked);
        final quads = page.single.quads;
        expect(quads, hasLength(2));
        expect(quads[0].bottom, greaterThanOrEqualTo(quads[1].top));
      },
    );

    test('la subrayada también: una línea en el recuadro', () async {
      final scan = _buildPdf(const [_Page.blank()]);
      final text = await _extractedText(scan, ocr: {0: ocr});

      final marked = await marker.mark(
        scan,
        content: text,
        marks: [_mark(text, 'Uno', style: HighlightStyle.underline)],
      );

      final [page] = await readAnnotations(marked);
      expect(page.single.subtype, pdfium_bindings.FPDF_ANNOT_UNDERLINE);
    });

    test('una página escaneada girada: el recuadro cae donde se ve el '
        'renglón, no donde estaría sin girar', () async {
      final scan = _buildPdf(const [_Page.blank(rotate: 90)]);
      final text = await _extractedText(scan, ocr: {0: ocr});

      final marked = await marker.mark(
        scan,
        content: text,
        marks: [
          _mark(text, 'Uno'),
          _mark(text, 'Cuatro', color: _orange),
        ],
      );

      // La página se ve apaisada (792 de ancho): los dos renglones son
      // bandas a lo ancho, uno arriba del otro.
      final uno = (await _paintedArea(marked, _turquoise))!;
      final cuatro = (await _paintedArea(marked, _orange))!;
      expect(uno.bottom, lessThan(cuatro.top));
      expect(uno.left, closeTo(792 * 0.08, 2));
      expect(uno.right, closeTo(792 * 0.92, 2));
      expect(uno.bottom - uno.top, lessThan(612 * 0.04));
    });

    test('con un «---» dentro del texto de la foto, las páginas con letras '
        'siguen ubicadas exacto', () async {
      // El texto reconocido trae un separador de verdad: ya no hay un tramo
      // por página, y hay que recorrerlas en orden.
      final mixed = _buildPdf(const [
        _Page(['Hola mundo']),
        _Page.blank(),
      ]);
      final text = await _extractedText(mixed, ocr: {1: 'Uno\n\n---\n\nDos'});

      final marked = await marker.mark(
        mixed,
        content: text,
        marks: [
          _mark(text, 'mundo'),
          _mark(text, 'Dos', color: _orange),
        ],
      );

      final [first, second] = await readAnnotations(marked);
      _expectRect(first.single.quads.single, await _rectOf(mixed, 'mundo'));
      expect(await _paintedArea(marked, _orange, pageNumber: 2), isNotNull);
    });
  });
}
