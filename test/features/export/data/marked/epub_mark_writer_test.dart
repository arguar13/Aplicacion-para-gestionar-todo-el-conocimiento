import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/epub_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/sample_files.dart';

const _yellow = 0xFFFFF59D;
const _turquoise = 0xFF4DD0E1;
const _orange = 0xFFFFB74D;

final _chapters = [
  (
    name: 'cap1.xhtml',
    html: [
      '<h1>Primero</h1>',
      '<p>La <b>revolución</b> industrial cambió todo, también la ',
      '<a href="cap2.xhtml">vida cotidiana</a> de la gente.</p>',
      '<p>Una frase suelta.</p>',
    ].join(),
  ),
  (
    name: 'cap2.xhtml',
    html: [
      '<h1>Segundo</h1>',
      '<p>El vapor movió las fábricas.</p>',
      '<p>Una frase suelta.</p>',
    ].join(),
  ),
  (name: 'notas.xhtml', html: '<h1>Notas</h1><p>Nota al final del libro.</p>'),
];

/// El texto extraído de [epub], como lo guarda la app.
Future<String> _extract(Uint8List epub) async {
  final parsed = await const EpubParser().parse(
    DocumentSource.memory(epub, name: 'libro.epub'),
  );
  return parsed.markdown;
}

DocumentMark _mark(
  String content,
  String excerpt, {
  int color = _yellow,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
  int occurrence = 0,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = content.indexOf(excerpt, start + 1);
  }
  expect(start, isNonNegative, reason: 'el texto de prueba no tiene $excerpt');
  return DocumentMark(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    color: color,
    style: style,
    note: note,
  );
}

/// Un capítulo del libro, leído de vuelta.
String _chapter(Uint8List epub, String name) {
  final file = ZipDecoder()
      .decodeBytes(epub)
      .files
      .firstWhere((f) => f.name == 'OEBPS/$name');
  return utf8.decode(file.readBytes()!);
}

/// Los `<mark>` de un capítulo: su texto y su `style`.
List<({String text, String style, String? title})> _marks(
  Uint8List epub,
  String name,
) => XmlDocument.parse(_chapter(epub, name))
    .findAllElements('mark')
    .map(
      (m) => (
        text: m.innerText,
        style: m.getAttribute('style')!,
        title: m.getAttribute('title'),
      ),
    )
    .toList();

/// Lo que se lee de un capítulo, sin etiquetas.
String _readable(Uint8List epub, String name) =>
    XmlDocument.parse(_chapter(epub, name)).rootElement.innerText;

/// El método de compresión de la primera entrada del ZIP, leído de la
/// cabecera: 0 es «sin comprimir».
({String name, int method}) _firstEntry(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  expect(data.getUint32(0, Endian.little), 0x04034b50, reason: 'cabecera ZIP');
  final nameLength = data.getUint16(26, Endian.little);
  return (
    name: utf8.decode(zip.sublist(30, 30 + nameLength)),
    method: data.getUint16(8, Endian.little),
  );
}

void main() {
  const writer = EpubMarkWriter();
  late Uint8List epub;
  late String content;

  setUp(() async {
    epub = buildEpub(chapters: _chapters, nonLinear: {'notas.xhtml'});
    content = await _extract(epub);
  });

  test('el texto extraído une los capítulos con el no lineal al final: es '
      'sobre lo que se prueba', () {
    expect(content, contains('Segundo'));
    expect(
      content.indexOf('Nota al final'),
      greaterThan(content.indexOf('vapor')),
    );
  });

  test('un tramo de fondo: su <mark> lleva el color exacto y el texto del '
      'capítulo queda completo', () {
    final out = writer.write(epub, content, [
      _mark(content, 'El vapor movió las fábricas.', color: _turquoise),
    ]);

    expect(_marks(out, 'cap2.xhtml'), [
      (
        text: 'El vapor movió las fábricas.',
        style: 'background-color:#4DD0E1',
        title: null,
      ),
    ]);
    expect(_marks(out, 'cap1.xhtml'), isEmpty);
    for (final name in ['cap1.xhtml', 'cap2.xhtml', 'notas.xhtml']) {
      expect(_readable(out, name), _readable(epub, name));
    }
  });

  test(
    'el libro marcado se vuelve a leer igual: mismo texto extraído',
    () async {
      final out = writer.write(epub, content, [
        _mark(content, 'El vapor movió las fábricas.'),
        _mark(content, 'Nota al final del libro.', color: _orange),
      ]);

      expect(await _extract(out), content);
    },
  );

  test('mimetype sigue siendo la primera entrada y va sin comprimir', () {
    final out = writer.write(epub, content, [
      _mark(content, 'El vapor movió las fábricas.'),
    ]);

    final first = _firstEntry(out);
    expect(first.name, 'mimetype');
    expect(first.method, 0, reason: 'sin comprimir');
    expect(
      utf8.decode(ZipDecoder().decodeBytes(out).files.first.readBytes()!),
      'application/epub+zip',
    );
  });

  test('las entradas que no se tocan quedan igual, y en el mismo orden', () {
    final out = writer.write(epub, content, [
      _mark(content, 'El vapor movió las fábricas.'),
    ]);

    final before = ZipDecoder().decodeBytes(epub).files;
    final after = ZipDecoder().decodeBytes(out).files;
    expect(after.map((f) => f.name), before.map((f) => f.name));
    for (var i = 0; i < before.length; i++) {
      if (before[i].name == 'OEBPS/cap2.xhtml') {
        expect(after[i].readBytes(), isNot(before[i].readBytes()));
      } else {
        expect(
          after[i].readBytes(),
          before[i].readBytes(),
          reason: before[i].name,
        );
      }
    }
  });

  test('un tramo que cruza etiquetas —una negrita, un enlace— se parte en un '
      '<mark> por cada texto, del mismo color', () {
    final out = writer.write(epub, content, [
      _mark(
        content,
        'La **revolución** industrial cambió todo, también la '
        '[vida cotidiana](cap2.xhtml) de la gente.',
        color: _turquoise,
      ),
    ]);

    final marks = _marks(out, 'cap1.xhtml');
    expect(marks.map((m) => m.style).toSet(), {'background-color:#4DD0E1'});
    expect(
      marks.map((m) => m.text).join(),
      'La revolución industrial cambió todo, también la vida cotidiana de la '
      'gente.',
    );
    final xml = XmlDocument.parse(_chapter(out, 'cap1.xhtml'));
    expect(
      xml.findAllElements('b').single.findElements('mark').single.innerText,
      'revolución',
    );
    expect(
      xml.findAllElements('a').single.findElements('mark').single.innerText,
      'vida cotidiana',
    );
    expect(_readable(out, 'cap1.xhtml'), _readable(epub, 'cap1.xhtml'));
  });

  test('varios tramos en varios capítulos, y dos pasajes iguales se ubican '
      'cada uno en su capítulo', () {
    final out = writer.write(epub, content, [
      _mark(content, 'Una frase suelta.'),
      _mark(
        content,
        'Una frase suelta.',
        occurrence: 1,
        color: _orange,
        style: HighlightStyle.underline,
      ),
      _mark(content, 'Nota al final del libro.', color: _turquoise),
    ]);

    expect(_marks(out, 'cap1.xhtml').single.style, 'background-color:#FFF59D');
    expect(
      _marks(out, 'cap2.xhtml').single.style,
      contains('text-decoration-color:#FFB74D'),
    );
    expect(_marks(out, 'notas.xhtml').single.style, 'background-color:#4DD0E1');
  });

  test('un subrayado es una línea del color y no un fondo', () {
    final out = writer.write(epub, content, [
      _mark(
        content,
        'El vapor movió las fábricas.',
        style: HighlightStyle.underline,
        color: _orange,
      ),
    ]);

    final style = _marks(out, 'cap2.xhtml').single.style;
    expect(style, contains('text-decoration:underline'));
    expect(style, contains('text-decoration-color:#FFB74D'));
    expect(style, contains('background-color:transparent;color:inherit'));
  });

  test('la nota va en el title', () {
    final out = writer.write(epub, content, [
      _mark(content, 'El vapor movió las fábricas.', note: 'Ver "vapor" & más'),
    ]);

    expect(_marks(out, 'cap2.xhtml').single.title, 'Ver "vapor" & más');
  });

  test('lo que no está en el libro se saltea; si nada está, devuelve el '
      'libro tal cual', () {
    const lost = DocumentMark(
      start: 0,
      end: 18,
      excerpt: 'Esto no está acá',
      color: _yellow,
    );

    expect(writer.write(epub, content, [lost]), same(epub));
    expect(writer.write(epub, content, const []), same(epub));

    final out = writer.write(epub, content, [
      lost,
      _mark(content, 'El vapor movió las fábricas.'),
    ]);
    expect(_marks(out, 'cap2.xhtml'), hasLength(1));
  });

  test('si el texto guardado no es el que sale del libro, cada tramo se '
      'ubica por su texto copiado', () {
    // El libro de hoy no coincide con el texto guardado: capítulos de más y
    // posiciones que no son.
    final stored = 'Texto viejo antes de todo.\n\n---\n\n$content';
    final shifted = stored.indexOf('El vapor');
    final out = writer.write(epub, 'otro texto completamente', [
      DocumentMark(
        start: shifted,
        end: shifted + 28,
        excerpt: 'El vapor movió las fábricas.',
        color: _turquoise,
      ),
    ]);

    expect(_marks(out, 'cap2.xhtml').map((m) => m.text), [
      'El vapor movió las fábricas.',
    ]);
  });

  test('posiciones que son de otro texto, con el mismo capítulo: manda el '
      'texto copiado, no las posiciones', () {
    // Las posiciones caen en «Primero», pero el texto copiado es del segundo.
    final out = writer.write(epub, content, [
      const DocumentMark(
        start: 0,
        end: 8,
        excerpt: 'El vapor movió las fábricas.',
        color: _turquoise,
      ),
    ]);

    expect(_marks(out, 'cap1.xhtml'), isEmpty);
    expect(_marks(out, 'cap2.xhtml').map((m) => m.text), [
      'El vapor movió las fábricas.',
    ]);
  });

  const underline = 'text-decoration:underline;text-decoration-color:#FFB74D';
  const yellowLine = 'background-color:#FFF59D;$underline';
  const turquoiseLine = 'background-color:#4DD0E1;$underline';

  test('un fondo y un subrayado sobre lo mismo conviven; si dos fondos se '
      'pisan, queda el que viene después', () {
    final out = writer.write(epub, content, [
      _mark(content, 'El vapor movió las fábricas.'),
      _mark(
        content,
        'El vapor movió las fábricas.',
        style: HighlightStyle.underline,
        color: _orange,
      ),
      _mark(content, 'vapor movió', color: _turquoise),
    ]);

    expect(
      _marks(out, 'cap2.xhtml').map((m) => '${m.text}|${m.style}').toList(),
      [
        'El |$yellowLine',
        'vapor movió|$turquoiseLine',
        ' las fábricas.|$yellowLine',
      ],
    );
  });

  test('un capítulo en UTF-16 o en ISO-8859-1 se vuelve a escribir en su '
      'codificación', () async {
    final strange = buildEpub(
      chapters: const [
        (name: 'a.xhtml', html: '<p>La canción más corta del año.</p>'),
        (name: 'b.xhtml', html: '<p>El corazón de la ciudad.</p>'),
        (name: 'c.xhtml', html: '<p>Otro capítulo normal.</p>'),
      ],
      utf16: {'a.xhtml'},
      latin1Chapters: {'b.xhtml'},
    );
    final text = await _extract(strange);
    final out = writer.write(strange, text, [
      _mark(text, 'La canción más corta del año.'),
      _mark(text, 'El corazón de la ciudad.', note: 'Corazón ♥'),
    ]);

    final files = {
      for (final f in ZipDecoder().decodeBytes(out).files)
        f.name: f.readBytes(),
    };
    // UTF-16 con su marca de orden de bytes.
    expect(files['OEBPS/a.xhtml']!.take(2), [0xFF, 0xFE]);
    expect(
      EpubParser.decodeChapter(files['OEBPS/a.xhtml']!),
      contains(
        '<mark style="background-color:#FFF59D">La canción más corta del año.</mark>',
      ),
    );
    // Latin-1: la «ó» es un solo byte y la nota lleva lo que ese alfabeto no
    // tiene como referencia numérica.
    final latin = files['OEBPS/b.xhtml']!;
    expect(latin1.decode(latin), contains('El corazón de la ciudad.'));
    expect(latin1.decode(latin), contains('title="Corazón &#9829;"'));
    expect(await _extract(out), text);
  });

  test('un capítulo con una entidad de HTML se escribe sin '
      'perder lo que se lee', () async {
    final entities = buildEpub(
      chapters: const [
        (
          name: 'a.xhtml',
          html: '<p>Caf&eacute;&nbsp;con leche, bien caliente.</p>',
        ),
      ],
    );
    final text = await _extract(entities);
    final out = writer.write(entities, text, [
      _mark(text, 'Café con leche, bien caliente.'),
    ]);

    expect(_marks(out, 'a.xhtml'), hasLength(1));
    expect(await _extract(out), text);
  });

  test('un capítulo que no es XML válido se deja como está', () async {
    final broken = buildEpub(
      chapters: const [
        (name: 'a.xhtml', html: '<p>Línea uno<br>y línea dos sin cerrar.</p>'),
        (name: 'b.xhtml', html: '<p>Este sí es válido.</p>'),
      ],
    );
    final text = await _extract(broken);
    final out = writer.write(broken, text, [
      _mark(text, 'Este sí es válido.'),
      _mark(text, 'y línea dos sin cerrar.'),
    ]);

    expect(_marks(out, 'b.xhtml'), hasLength(1));
    final before = ZipDecoder().decodeBytes(broken).files;
    final after = ZipDecoder().decodeBytes(out).files;
    expect(
      after.firstWhere((f) => f.name == 'OEBPS/a.xhtml').readBytes(),
      before.firstWhere((f) => f.name == 'OEBPS/a.xhtml').readBytes(),
    );
  });

  test('dos capítulos con el mismo texto: cada tramo cae en el suyo, por '
      'sus posiciones', () async {
    final twins = buildEpub(
      chapters: const [
        (name: 'x.xhtml', html: '<p>Texto repetido en dos capítulos.</p>'),
        (name: 'y.xhtml', html: '<p>Texto repetido en dos capítulos.</p>'),
      ],
    );
    final text = await _extract(twins);
    final out = writer.write(twins, text, [
      _mark(text, 'Texto repetido en dos capítulos.', occurrence: 1),
    ]);

    expect(_marks(out, 'x.xhtml'), isEmpty);
    expect(_marks(out, 'y.xhtml'), hasLength(1));
  });

  test('si las posiciones no dicen lo mismo que el texto copiado, se busca '
      'primero en el capítulo que le tocaba', () {
    // Las posiciones son de «El vapor…», en el segundo capítulo; el texto
    // copiado es una frase que está en los dos. Le toca el segundo.
    final vapor = _mark(content, 'El vapor movió las fábricas.');
    final out = writer.write(epub, content, [
      DocumentMark(
        start: vapor.start,
        end: vapor.end,
        excerpt: 'Una frase suelta.',
        color: _turquoise,
      ),
    ]);

    expect(_marks(out, 'cap1.xhtml'), isEmpty);
    expect(_marks(out, 'cap2.xhtml').map((m) => m.text), ['Una frase suelta.']);
  });

  test('un pasaje repetido dentro de un capítulo: cada tramo en el suyo, '
      'aunque la lista venga en otro orden', () async {
    final repeated = buildEpub(
      chapters: const [
        (name: 'a.xhtml', html: '<p>Primer capítulo, sin repeticiones.</p>'),
        (
          name: 'b.xhtml',
          html:
              '<p>Dicho una vez.</p><p>Dicho una vez.</p><p>Dicho una vez.</p>',
        ),
      ],
    );
    final text = await _extract(repeated);
    final out = writer.write(repeated, text, [
      _mark(text, 'Dicho una vez.', occurrence: 2, color: _orange),
      _mark(text, 'Dicho una vez.', occurrence: 1, color: _turquoise),
    ]);

    final paragraphs = XmlDocument.parse(_chapter(out, 'b.xhtml'))
        .findAllElements('p')
        .map((p) => p.findElements('mark').firstOrNull?.getAttribute('style'))
        .toList();
    expect(paragraphs, [
      null,
      'background-color:#4DD0E1',
      'background-color:#FFB74D',
    ]);
  });

  test('cuando se pisan un tramo ubicado por sus posiciones y otro por su '
      'texto, queda el que viene después en la lista', () {
    // El de «vapor movió» (el último) manda sobre el que lo contiene (el
    // segundo), que tiene mal las posiciones y se busca por su texto.
    final out = writer.write(epub, content, [
      _mark(content, 'Primero'),
      const DocumentMark(
        start: 9000,
        end: 9028,
        excerpt: 'El vapor movió las fábricas.',
        color: _yellow,
      ),
      _mark(content, 'vapor movió', color: _turquoise),
    ]);

    expect(_marks(out, 'cap2.xhtml').map((m) => '${m.text}|${m.style}'), [
      'El |background-color:#FFF59D',
      'vapor movió|background-color:#4DD0E1',
      ' las fábricas.|background-color:#FFF59D',
    ]);
  });

  test('un tramo mal ubicado que está en dos capítulos se pinta una sola '
      'vez, en el primero', () {
    final out = writer.write(epub, content, [
      const DocumentMark(
        start: 9000,
        end: 9017,
        excerpt: 'Una frase suelta.',
        color: _yellow,
      ),
    ]);

    expect(_marks(out, 'cap1.xhtml'), hasLength(1));
    expect(_marks(out, 'cap2.xhtml'), isEmpty);
  });

  test('lo que le tocaba a un capítulo que no se puede reescribir no se '
      'pinta en otro que dice lo mismo', () async {
    final twin = buildEpub(
      chapters: const [
        (name: 'a.xhtml', html: '<p>Frase repetida<br>sin cerrar.</p>'),
        (name: 'b.xhtml', html: '<p>Frase repetida sin cerrar.</p>'),
      ],
    );
    final text = await _extract(twin);
    final out = writer.write(twin, text, [_mark(text, 'Frase repetida')]);

    expect(_marks(out, 'b.xhtml'), isEmpty);
  });
}
