// El XML de estas pruebas se arma en trozos que se pegan sin espacios: un
// espacio de más entre etiquetas cambiaría el documento que se prueba.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_files.dart';

const _yellow = 0xFFFFF59D;
const _turquoise = 0xFF4DD0E1;
const _violet = 0xFFB39DDB;

/// Un pedazo de texto de Word tal como quedó escrito: su texto y lo que
/// tiene en las propiedades.
typedef _Run = ({
  String text,
  String? fill,
  String? underlineColor,
  String? underline,
  bool bold,
  bool hasHighlight,
  List<String> properties,
});

XmlDocument _xmlOf(Uint8List docx, String part) {
  final file = ZipDecoder().decodeBytes(docx).findFile(part);
  expect(file, isNotNull, reason: 'falta $part');
  return XmlDocument.parse(utf8.decode(file!.readBytes()!));
}

List<_Run> _runsOf(Uint8List docx) {
  final runs = <_Run>[];
  for (final r in _xmlOf(docx, 'word/document.xml').findAllElements('w:r')) {
    final text = r.findElements('w:t').map((t) => t.innerText).join();
    if (text.isEmpty) continue;
    final rPr = r.getElement('w:rPr');
    runs.add((
      text: text,
      fill: rPr?.getElement('w:shd')?.getAttribute('w:fill'),
      underlineColor: rPr?.getElement('w:u')?.getAttribute('w:color'),
      underline: rPr?.getElement('w:u')?.getAttribute('w:val'),
      bold: rPr?.getElement('w:b') != null,
      hasHighlight: rPr?.getElement('w:highlight') != null,
      properties: [
        for (final e in rPr?.childElements ?? const <XmlElement>[])
          e.name.local,
      ],
    ));
  }
  return runs;
}

/// El texto de todos los `w:t` del cuerpo, de corrido.
String _plainText(Uint8List docx) => _xmlOf(
  docx,
  'word/document.xml',
).findAllElements('w:t').map((t) => t.innerText).join();

DocumentMark _mark(
  String text,
  String excerpt, {
  int occurrence = 0,
  int color = _yellow,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = text.indexOf(excerpt, start + 1);
    expect(start, isNonNegative, reason: '«$excerpt» no está en el texto');
  }
  return DocumentMark(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    color: color,
    style: style,
    note: note,
  );
}

/// Lo que el lector real de la app saca del Word: el texto extraído.
Future<String> _extract(Uint8List docx) async =>
    (await const DocxParser().parseBytes(docx)).markdown;

String _sampleBody() => [
  wordParagraph('Historia de Francia', style: 'Heading1'),
  '''
    <w:p>
      <w:r><w:t xml:space="preserve">La revolución </w:t></w:r>
      <w:r><w:rPr><w:b/><w:sz w:val="28"/><w:lang w:val="es-AR"/></w:rPr><w:t>francesa</w:t></w:r>
      <w:r><w:t xml:space="preserve"> cambió el mundo entero.</w:t></w:r>
    </w:p>''',
  wordParagraph('Un punto de una lista', listLevel: 0),
  wordParagraph('La caída de la Bastilla fue el comienzo.'),
  wordParagraph('La caída de la Bastilla fue también un símbolo.'),
  wordTable([
    ['Año', 'Hecho'],
    ['1789', 'Toma de la Bastilla'],
  ]),
].join();

/// El mismo Word con la entrada [name] cambiada (o agregada) por [content].
Uint8List _withEntry(Uint8List docx, String name, String content) {
  final archive = Archive();
  var replaced = false;
  for (final f in ZipDecoder().decodeBytes(docx).files) {
    if (f.name == name) {
      replaced = true;
      archive.addFile(ArchiveFile.string(name, content));
    } else {
      archive.addFile(ArchiveFile.bytes(f.name, f.readBytes()!));
    }
  }
  if (!replaced) archive.addFile(ArchiveFile.string(name, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _sampleDocx({Map<String, String> parts = const {}}) => buildDocx(
  body: _sampleBody(),
  parts: {
    'word/styles.xml': wordPart('w:styles', '<w:style w:styleId="Normal"/>'),
    ...parts,
  },
);

void main() {
  const writer = DocxMarkWriter();

  group('DocxMarkWriter', () {
    late Uint8List docx;
    late String text;

    setUp(() async {
      docx = _sampleDocx();
      text = await _extract(docx);
    });

    test('un tramo de fondo: el run lleva el sombreado con el color exacto '
        'y el texto sigue igual', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [_mark(text, 'símbolo')],
      );

      final marked = _runsOf(result).where((r) => r.fill != null).toList();
      expect(marked, hasLength(1));
      expect(marked.single.text, 'símbolo');
      // 0xFFFFF59D sin transparencia: el color de la persona, tal cual.
      expect(marked.single.fill, 'FFF59D');
      expect(_plainText(result), _plainText(docx));
      // Y es un Word que la app sigue leyendo igual.
      expect(await _extract(result), text);
    });

    test('un tramo que cruza runs los parte y conserva las propiedades de '
        'cada uno', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [_mark(text, 'revolución **francesa** cambió')],
      );

      final marked = _runsOf(result).where((r) => r.fill != null).toList();
      expect(marked.map((r) => r.text), ['revolución ', 'francesa', ' cambió']);
      expect(marked.map((r) => r.fill).toSet(), {'FFF59D'});
      // La negrita, el tamaño y el idioma siguen en el run del medio, con el
      // sombreado en su lugar del esquema: después del tamaño, antes del
      // idioma.
      final bold = marked[1];
      expect(bold.bold, isTrue);
      expect(bold.properties, ['b', 'sz', 'shd', 'lang']);
      // Lo de antes y lo de después del tramo quedó sin marcar.
      final all = _runsOf(result);
      expect(all.firstWhere((r) => r.text == 'La ').fill, isNull);
      expect(all.firstWhere((r) => r.text == ' el mundo entero.').fill, isNull);
      expect(_plainText(result), _plainText(docx));
    });

    test('varios tramos, cada uno con su color; el que viene después gana '
        'si se pisan', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [
          _mark(text, 'La caída de la Bastilla'),
          _mark(text, 'Bastilla fue el comienzo', color: _turquoise),
          _mark(text, 'Toma de la Bastilla', color: _violet),
        ],
      );

      final fills = {
        for (final r in _runsOf(result))
          if (r.fill != null) r.text: r.fill,
      };
      // Primero amarillo, y el turquesa le pisa la «Bastilla».
      expect(fills['La caída de la '], 'FFF59D');
      expect(fills['Bastilla fue el comienzo'], '4DD0E1');
      expect(fills['Toma de la Bastilla'], 'B39DDB');
      expect(_plainText(result), _plainText(docx));
    });

    test('elige la repetición que corresponde, aunque el texto extraído '
        'tenga de más un encabezado con la misma frase', () async {
      final withHeader = 'Cabecera: La caída de la Bastilla\n\n$text';
      // Es la segunda vez en el texto extraído (la primera es la cabecera) y
      // la primera en el cuerpo del Word: sin mirar lo que la precede, caería
      // en la tercera.
      final first = _mark(withHeader, 'La caída de la Bastilla', occurrence: 1);
      final result = await writer.write(
        docx: docx,
        text: withHeader,
        marks: [first],
      );

      final marked = _xmlOf(result, 'word/document.xml')
          .findAllElements('w:r')
          .where((r) => r.getElement('w:rPr')?.getElement('w:shd') != null)
          .single;
      expect(marked.innerText, 'La caída de la Bastilla');
      expect(marked.parent!.innerText, contains('fue el comienzo'));
    });

    test('si el contexto no coincide, toma la misma repetición que en el '
        'texto extraído', () async {
      final doc = buildDocx(
        body: [
          wordParagraph('Fin.'),
          wordParagraph('Fin.'),
          wordParagraph('Fin.'),
          wordParagraph('Fin.'),
        ].join(),
      );
      // El texto extraído trae números que el Word no tiene: lo de antes no
      // coincide, solo queda contar.
      const numbered = '1. Fin.\n2. Fin.\n3. Fin.\n4. Fin.';
      final result = await writer.write(
        docx: doc,
        text: numbered,
        marks: [_mark(numbered, 'Fin', occurrence: 1)],
      );
      final runs = _xmlOf(result, 'word/document.xml')
          .findAllElements('w:r')
          .map((r) => r.getElement('w:rPr')?.getElement('w:shd') != null)
          .toList();
      // La segunda; cada «Fin.» son dos runs si está marcado.
      expect(runs, [false, true, false, false, false]);
    });

    test('un tramo cuyas letras cambiaron de lugar o no están se saltea: el '
        'documento queda exactamente igual', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [
          const DocumentMark(
            start: 0,
            end: 12,
            excerpt: 'esto no está en el documento',
            color: _yellow,
          ),
        ],
      );
      expect(result, docx);
    });

    test('el que no se encuentra no impide marcar los demás', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [
          const DocumentMark(
            start: 0,
            end: 5,
            excerpt: 'inexistente',
            color: _yellow,
          ),
          _mark(text, 'Toma de la Bastilla', color: _violet),
        ],
      );
      final marked = _runsOf(result).where((r) => r.fill != null);
      expect(marked.map((r) => r.text), ['Toma de la Bastilla']);
    });

    test('compara solo letras y números: acentos, mayúsculas y puntuación '
        'no impiden ubicarlo', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [
          // Como lo copia otra herramienta: sin tildes y con otra puntuación.
          DocumentMark(
            start: text.indexOf('La revolución'),
            end: text.indexOf('La revolución') + 20,
            excerpt: 'LA REVOLUCION... francesa',
            color: _yellow,
          ),
        ],
      );
      final marked = _runsOf(result).where((r) => r.fill != null);
      expect(marked.map((r) => r.text), ['La revolución ', 'francesa']);
    });

    test(
      'un subrayado: w:u simple con el color exacto, y sin sombreado',
      () async {
        final result = await writer.write(
          docx: docx,
          text: text,
          marks: [
            _mark(
              text,
              'cambió el mundo',
              style: HighlightStyle.underline,
              color: _turquoise,
            ),
          ],
        );
        final underlined = _runsOf(result).where((r) => r.underline != null);
        expect(underlined.map((r) => r.text).join(), 'cambió el mundo');
        expect(underlined.map((r) => r.underline).toSet(), {'single'});
        expect(underlined.map((r) => r.underlineColor).toSet(), {'4DD0E1'});
        expect(underlined.every((r) => r.fill == null), isTrue);
      },
    );

    test('el fondo reemplaza el w:highlight que el run ya tenía, que lo '
        'taparía', () async {
      final withHighlight = buildDocx(
        body:
            '<w:p><w:r><w:rPr><w:highlight w:val="green"/></w:rPr>'
            '<w:t>Texto resaltado antes</w:t></w:r></w:p>',
      );
      final extracted = await _extract(withHighlight);
      final result = await writer.write(
        docx: withHighlight,
        text: extracted,
        marks: [_mark(extracted, 'resaltado')],
      );
      final run = _runsOf(result).singleWhere((r) => r.fill != null);
      expect(run.text, 'resaltado');
      expect(run.hasHighlight, isFalse);
      // Lo de al lado conserva su resaltado.
      expect(
        _runsOf(
          result,
        ).where((r) => r.fill == null).every((r) => r.hasHighlight),
        isTrue,
      );
    });

    test(
      'un color con transparencia se mezcla con el blanco del papel',
      () async {
        final result = await writer.write(
          docx: docx,
          text: text,
          marks: [_mark(text, 'Toma de la Bastilla', color: 0x80FF0000)],
        );
        // 50 % de rojo sobre blanco.
        expect(
          _runsOf(result).singleWhere((r) => r.fill != null).fill,
          'FF7F7F',
        );
      },
    );

    test('las otras entradas del ZIP quedan con los mismos bytes', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [_mark(text, 'símbolo')],
      );
      final beforeFiles = ZipDecoder().decodeBytes(docx).files;
      final afterFiles = ZipDecoder().decodeBytes(result).files;
      final before = {for (final f in beforeFiles) f.name: f.readBytes()};
      final after = {for (final f in afterFiles) f.name: f.readBytes()};
      expect(
        afterFiles.map((f) => f.name).toList(),
        beforeFiles.map((f) => f.name).toList(),
        reason: 'mismas entradas, mismo orden, ninguna repetida',
      );
      for (final name in before.keys) {
        if (name == 'word/document.xml') continue;
        expect(after[name], before[name], reason: name);
      }
      expect(after['word/document.xml'], isNot(before['word/document.xml']));
    });

    test('el sombreado se escribe como sombreado liso, y reemplaza al que el '
        'run ya tenía en vez de sumarse', () async {
      final doc = buildDocx(
        body:
            '<w:p><w:r><w:rPr><w:shd w:val="pct25" w:fill="00FF00"/></w:rPr>'
            '<w:t>Con fondo previo</w:t></w:r></w:p>',
      );
      final extracted = await _extract(doc);
      final result = await writer.write(
        docx: doc,
        text: extracted,
        marks: [_mark(extracted, 'fondo')],
      );
      final shades = _xmlOf(result, 'word/document.xml')
          .findAllElements('w:r')
          .where((r) => r.innerText == 'fondo')
          .single
          .getElement('w:rPr')!
          .findElements('w:shd')
          .toList();
      expect(shades, hasLength(1));
      expect(shades.single.getAttribute('w:val'), 'clear');
      expect(shades.single.getAttribute('w:color'), 'auto');
      expect(shades.single.getAttribute('w:fill'), 'FFF59D');
    });

    test('el subrayado reemplaza al que el run ya tenía', () async {
      final doc = buildDocx(
        body:
            '<w:p><w:r><w:rPr><w:u w:val="double" w:color="FF0000"/></w:rPr>'
            '<w:t>Ya subrayado</w:t></w:r></w:p>',
      );
      final extracted = await _extract(doc);
      final result = await writer.write(
        docx: doc,
        text: extracted,
        marks: [_mark(extracted, 'subrayado', style: HighlightStyle.underline)],
      );
      final underlines = _xmlOf(result, 'word/document.xml')
          .findAllElements('w:r')
          .where((r) => r.innerText == 'subrayado')
          .single
          .getElement('w:rPr')!
          .findElements('w:u')
          .toList();
      expect(underlines, hasLength(1));
      expect(underlines.single.getAttribute('w:val'), 'single');
    });

    test('el sombreado va antes de lo que el esquema pone después, aunque '
        'sea algo que no conocemos', () async {
      final doc = buildDocx(
        body:
            '<w:p><w:r><w:rPr><w:b/><w:rPrChange w:id="1"/></w:rPr>'
            '<w:t>Con cambio</w:t></w:r></w:p>',
      );
      final extracted = await _extract(doc);
      final result = await writer.write(
        docx: doc,
        text: extracted,
        marks: [_mark(extracted, 'cambio')],
      );
      final run = _runsOf(result).singleWhere((r) => r.fill != null);
      expect(run.properties, ['b', 'shd', 'rPrChange']);
    });

    test('sin tramos devuelve el mismo archivo', () async {
      expect(await writer.write(docx: docx, text: text, marks: []), docx);
    });

    test('en una tabla, en un enlace y con tabulaciones: parte el run sin '
        'mover lo que tiene alrededor', () async {
      final doc = buildDocx(
        body:
            '<w:p><w:r><w:t xml:space="preserve">Ver </w:t></w:r>'
            '<w:hyperlink w:anchor="x"><w:r><w:rPr><w:u w:val="single"/></w:rPr>'
            '<w:t>el sitio oficial</w:t></w:r></w:hyperlink>'
            '<w:r><w:t xml:space="preserve"> ahora</w:t><w:tab/><w:t>y despues</w:t></w:r></w:p>'
            '${wordTable([
              ['Uno', 'Dos tres'],
            ])}',
      );
      final extracted = await _extract(doc);
      final result = await writer.write(
        docx: doc,
        text: extracted,
        marks: [
          _mark(extracted, 'sitio oficial ahora'),
          _mark(extracted, 'y despues', color: _violet),
          _mark(extracted, 'Dos tres', color: _turquoise),
        ],
      );

      final runs = _runsOf(result);
      expect(runs.where((r) => r.fill == 'FFF59D').map((r) => r.text), [
        'sitio oficial',
        ' ahora',
      ]);
      expect(runs.singleWhere((r) => r.fill == 'B39DDB').text, 'y despues');
      expect(runs.singleWhere((r) => r.fill == '4DD0E1').text, 'Dos tres');
      // El run del enlace conserva su subrayado de antes.
      expect(
        runs.singleWhere((r) => r.text == 'sitio oficial').underline,
        'single',
      );
      expect(_plainText(result), _plainText(doc));
      // La tabulación sigue entre «ahora» y «y despues», en su lugar.
      final body = _xmlOf(result, 'word/document.xml');
      final tab = body.findAllElements('w:tab').single;
      final runAround = tab.parent!;
      expect(runAround.findElements('w:t').single.innerText, ' ahora');
      expect(
        (runAround.nextSibling! as XmlElement)
            .findElements('w:t')
            .single
            .innerText,
        'y despues',
      );
    });

    test('los espacios de los bordes de un run partido se conservan', () async {
      final result = await writer.write(
        docx: docx,
        text: text,
        marks: [_mark(text, 'revolución')],
      );
      final body = _xmlOf(result, 'word/document.xml');
      final spaced = body
          .findAllElements('w:t')
          .where((t) => t.innerText == 'La ')
          .single;
      expect(spaced.getAttribute('xml:space'), 'preserve');
    });

    test('un cuadro de texto, que Word escribe dos veces, se marca una sola '
        'vez', () async {
      final doc = buildDocx(
        body:
            '<w:p><w:r><mc:AlternateContent>'
            '<mc:Choice Requires="wps"><w:drawing><wps:txbx><w:txbxContent>'
            '<w:p><w:r><w:t>Texto del cuadro</w:t></w:r></w:p>'
            '</w:txbxContent></wps:txbx></w:drawing></mc:Choice>'
            '<mc:Fallback><w:pict><v:textbox><w:txbxContent>'
            '<w:p><w:r><w:t>Texto del cuadro</w:t></w:r></w:p>'
            '</w:txbxContent></v:textbox></w:pict></mc:Fallback>'
            '</mc:AlternateContent></w:r></w:p>'
            '<w:p><w:r><w:t>Otra vez Texto del cuadro aquí</w:t></w:r></w:p>',
      );
      // Un texto extraído cuyo contexto no está en el Word: solo queda contar
      // las repeticiones, y la copia de respaldo no cuenta.
      const extracted = 'Zeta Texto del cuadro. Omega Texto del cuadro.';
      final result = await writer.write(
        docx: doc,
        text: extracted,
        marks: [_mark(extracted, 'Texto del cuadro', occurrence: 1)],
      );
      final marked = _xmlOf(result, 'word/document.xml')
          .findAllElements('w:r')
          .where((r) => r.getElement('w:rPr')?.getElement('w:shd') != null)
          .single;
      expect(marked.innerText, 'Texto del cuadro');
      // Con la copia de respaldo contada, caería en ella y no en el párrafo.
      expect(marked.parent!.innerText, 'Otra vez Texto del cuadro aquí');
    });

    test('el cuerpo es la parte que nombra la relación officeDocument, no un '
        'nombre fijo', () async {
      final original = _sampleDocx();
      final source = ZipDecoder().decodeBytes(original);
      final archive = Archive();
      for (final f in source.files) {
        if (f.name == 'word/document.xml') {
          archive.addFile(
            ArchiveFile.bytes('word/principal.xml', f.readBytes()!),
          );
        } else {
          archive.addFile(ArchiveFile.bytes(f.name, f.readBytes()!));
        }
      }
      archive.addFile(
        ArchiveFile.string(
          '_rels/.rels',
          '<?xml version="1.0"?><Relationships '
              'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="/word/principal.xml"/>'
              '</Relationships>',
        ),
      );
      final renamed = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await writer.write(
        docx: renamed,
        text: text,
        marks: [_mark(text, 'símbolo')],
      );
      final file = ZipDecoder()
          .decodeBytes(result)
          .findFile('word/principal.xml');
      expect(file, isNotNull);
      expect(utf8.decode(file!.readBytes()!), contains('FFF59D'));
    });

    group('las notas, como comentarios de Word', () {
      test('sin comments.xml: se arma, con su relación y su tipo de '
          'contenido, y el cuerpo marca el rango', () async {
        // Con la relación de las partes del cuerpo y el tipo de contenido ya
        // escritos, como los trae Word.
        final withRels = _sampleDocx(
          parts: {
            'word/_rels/document.xml.rels':
                '<?xml version="1.0"?><Relationships '
                'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
                '</Relationships>',
          },
        );
        final extracted = await _extract(withRels);
        final result = await writer.write(
          docx: withRels,
          text: extracted,
          marks: [
            _mark(extracted, 'símbolo', note: 'Ojo con esto\nOtra línea'),
          ],
        );

        final comments = _xmlOf(result, 'word/comments.xml');
        final comment = comments.findAllElements('w:comment').single;
        expect(comment.getAttribute('w:id'), '0');
        expect(comment.getAttribute('w:author'), 'Sinapsis');
        expect(comment.findAllElements('w:t').map((t) => t.innerText), [
          'Ojo con esto',
          'Otra línea',
        ]);

        final body = _xmlOf(result, 'word/document.xml');
        final start = body.findAllElements('w:commentRangeStart').single;
        final end = body.findAllElements('w:commentRangeEnd').single;
        final reference = body.findAllElements('w:commentReference').single;
        expect(
          [start, end, reference].map((e) => e.getAttribute('w:id')).toSet(),
          {'0'},
        );
        // El rango envuelve exactamente al run marcado.
        final siblings = start.parent!.children
            .whereType<XmlElement>()
            .toList();
        final at = siblings.indexOf(start);
        expect(
          siblings[at + 1].findElements('w:t').single.innerText,
          'símbolo',
        );
        expect(siblings[at + 2], end);

        final rels = _xmlOf(result, 'word/_rels/document.xml.rels');
        final relation = rels
            .findAllElements('Relationship')
            .singleWhere((e) => e.getAttribute('Target') == 'comments.xml');
        expect(
          relation.getAttribute('Type'),
          endsWith('/relationships/comments'),
        );
        expect(relation.getAttribute('Id'), 'rId2');

        final types = _xmlOf(result, '[Content_Types].xml');
        expect(
          types
              .findAllElements('Override')
              .where((e) => e.getAttribute('PartName') == '/word/comments.xml')
              .single
              .getAttribute('ContentType'),
          contains('wordprocessingml.comments+xml'),
        );
        // Y sigue siendo un Word legible, con el mismo texto.
        expect(await _extract(result), contains('símbolo'));
      });

      test('con comments.xml: se le agrega, sin repetir números', () async {
        var withComments = _sampleDocx(
          parts: {
            'word/comments.xml': wordPart(
              'w:comments',
              '<w:comment w:id="7" w:author="Ana"><w:p><w:r><w:t>Vieja</w:t>'
                  '</w:r></w:p></w:comment>',
            ),
            'word/_rels/document.xml.rels':
                '<?xml version="1.0"?><Relationships '
                'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/>'
                '</Relationships>',
          },
        );
        // Con el tipo de contenido de los comentarios ya declarado.
        withComments = _withEntry(
          withComments,
          '[Content_Types].xml',
          '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
              '<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>'
              '</Types>',
        );
        final extracted = await _extract(withComments);
        final result = await writer.write(
          docx: withComments,
          text: extracted,
          marks: [_mark(extracted, 'símbolo', note: 'Nueva')],
        );

        final comments = _xmlOf(result, 'word/comments.xml');
        expect(
          comments
              .findAllElements('w:comment')
              .map((c) => c.getAttribute('w:id')),
          ['7', '8'],
        );
        expect(comments.findAllElements('w:comment').first.innerText, 'Vieja');
        // La relación que había se usó; no se agregó otra.
        final rels = _xmlOf(result, 'word/_rels/document.xml.rels');
        expect(rels.findAllElements('Relationship'), hasLength(1));
        // Y el tipo de contenido, que ya estaba, no se repite.
        final types = _xmlOf(result, '[Content_Types].xml');
        expect(
          types
              .findAllElements('Override')
              .where((e) => e.getAttribute('PartName') == '/word/comments.xml'),
          hasLength(1),
        );
      });

      test(
        'un tramo de varios runs: el rango abarca del primero al último',
        () async {
          final result = await writer.write(
            docx: docx,
            text: text,
            marks: [
              _mark(
                text,
                'revolución **francesa** cambió',
                note: 'Varios runs',
              ),
            ],
          );
          final body = _xmlOf(result, 'word/document.xml');
          final start = body.findAllElements('w:commentRangeStart').single;
          final siblings = start.parent!.children
              .whereType<XmlElement>()
              .toList();
          final at = siblings.indexOf(start);
          // Inicio, los tres runs marcados, fin y la marca del comentario.
          expect(siblings.sublist(at + 1, at + 4).map((e) => e.innerText), [
            'revolución ',
            'francesa',
            ' cambió',
          ]);
          expect(siblings[at + 4].name.local, 'commentRangeEnd');
          expect(
            siblings[at + 5].findElements('w:commentReference'),
            hasLength(1),
          );
          // El último run no marcado sigue después, sin comentario.
          expect(siblings[at + 6].innerText, ' el mundo entero.');
          // Y antes del inicio, lo que no se marcó.
          expect(siblings[at - 1].innerText, 'La ');
        },
      );

      test('una nota vacía no arma comentarios', () async {
        final result = await writer.write(
          docx: docx,
          text: text,
          marks: [_mark(text, 'símbolo', note: '  ')],
        );
        expect(
          ZipDecoder().decodeBytes(result).findFile('word/comments.xml'),
          isNull,
        );
      });
    });
  });
}
