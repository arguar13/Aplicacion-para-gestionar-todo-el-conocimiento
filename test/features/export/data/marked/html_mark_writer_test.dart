import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/html_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';

/// Una página archivada como las de la app: con su menú, su hoja de estilos,
/// su programa y su foto incrustada como datos.
const _photo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

const _page =
    '''
<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>La revolución</title>
<style>p { margin: 0 }</style></head>
<body>
<nav><a href="/">Inicio</a> <a href="/otra">Otra nota</a></nav>
<article>
<h1>La revolución industrial</h1>
<p>Intro corta.</p>
<p>La <b>revolución</b> industrial cambió todo, también la <a href="/x">vida
cotidiana</a> de la gente.</p>
<img src="$_photo" alt="una foto">
<p>Segunda parte: el vapor movió las fábricas.</p>
<p>Segunda parte: el vapor movió las fábricas.</p>
</article>
<script>var x = "La revolución industrial cambió todo";</script>
</body></html>''';

/// El texto extraído de [_page]: el artículo en Markdown.
const _content =
    '# La revolución industrial\n\n'
    'Intro corta.\n\n'
    'La **revolución** industrial cambió todo, también la '
    '[vida cotidiana](/x) de la gente.\n\n'
    '![una foto]($_photo)\n\n'
    'Segunda parte: el vapor movió las fábricas.\n\n'
    'Segunda parte: el vapor movió las fábricas.';

const _yellow = 0xFFFFF59D;
const _turquoise = 0xFF4DD0E1;

DocumentMark _mark(
  String excerpt, {
  int color = _yellow,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
  int occurrence = 0,
  String content = _content,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = content.indexOf(excerpt, start + 1);
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

Document _parse(String html) => html_parser.parse(html);

String _marked(Document page) =>
    page.querySelectorAll('mark').map((e) => e.text).join('|');

void main() {
  const writer = HtmlMarkWriter();

  test('un tramo de fondo: su <mark> lleva el color exacto y la página sigue '
      'diciendo lo mismo', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.', color: _turquoise),
    ]);

    final page = _parse(out);
    final mark = page.querySelector('mark')!;
    expect(mark.text, 'Intro corta.');
    expect(mark.attributes['style'], 'background-color:#4DD0E1');
    expect(mark.parent?.localName, 'p');
    expect(page.querySelectorAll('mark'), hasLength(1));
    // Lo que se lee no cambió ni una letra.
    expect(page.body!.text, _parse(_page).body!.text);
  });

  test('la foto incrustada, la hoja de estilos y el programa quedan como '
      'estaban: se abre sin conexión igual', () {
    final out = writer.write(_page, _content, [_mark('Intro corta.')]);

    final page = _parse(out);
    expect(page.querySelector('img')!.attributes['src'], _photo);
    expect(page.querySelector('img')!.attributes['alt'], 'una foto');
    expect(page.querySelector('style')!.text, 'p { margin: 0 }');
    expect(
      page.querySelector('script')!.text,
      'var x = "La revolución industrial cambió todo";',
    );
    expect(page.querySelector('title')!.text, 'La revolución');
    expect(page.querySelector('nav mark'), isNull);
    expect(page.documentElement!.attributes['lang'], 'es');
  });

  test('un tramo que cruza etiquetas —una negrita, un enlace— se parte en un '
      '<mark> por cada texto, todos del mismo color', () {
    const sentence =
        'La **revolución** industrial cambió todo, también la '
        '[vida cotidiana](/x) de la gente.';
    final out = writer.write(_page, _content, [
      _mark(sentence, color: _turquoise),
    ]);

    final page = _parse(out);
    final marks = page.querySelectorAll('mark');
    expect(marks.length, greaterThan(1));
    expect(marks.map((m) => m.attributes['style']).toSet(), {
      'background-color:#4DD0E1',
    });
    expect(page.querySelector('b mark')?.text, 'revolución');
    expect(page.querySelector('a mark')?.text, 'vida\ncotidiana');
    // Con el punto del final, y sin llevarse nada más: ni el menú ni el
    // párrafo de al lado.
    expect(
      marks.map((m) => m.text).join(),
      'La revolución industrial cambió todo, también la vida\n'
      'cotidiana de la gente.',
    );
    expect(page.body!.text, _parse(_page).body!.text);
  });

  test('varios tramos, cada uno con su color, y dos pasajes iguales se '
      'distinguen por su lugar en el texto', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.'),
      _mark('Segunda parte: el vapor movió las fábricas.', color: _turquoise),
      _mark(
        'Segunda parte: el vapor movió las fábricas.',
        occurrence: 1,
        style: HighlightStyle.underline,
        color: 0xFFFF9800,
      ),
    ]);

    final page = _parse(out);
    final paragraphs = page.querySelectorAll('article p');
    expect(
      paragraphs[0].querySelector('mark')?.attributes['style'],
      contains('#FFF59D'),
    );
    expect(paragraphs[1].querySelector('mark'), isNull);
    expect(
      paragraphs[2].querySelector('mark')?.attributes['style'],
      'background-color:#4DD0E1',
    );
    expect(
      paragraphs[3].querySelector('mark')?.attributes['style'],
      contains('text-decoration-color:#FF9800'),
    );
  });

  test('un subrayado es una línea del color y no un fondo: el amarillo de '
      'fábrica del <mark> queda apagado', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.', style: HighlightStyle.underline, color: _turquoise),
    ]);

    final style = _parse(out).querySelector('mark')!.attributes['style']!;
    expect(style, contains('text-decoration:underline'));
    expect(style, contains('text-decoration-color:#4DD0E1'));
    expect(style, contains('background-color:transparent;color:inherit'));
    expect(style, isNot(contains('background-color:#')));
  });

  test(
    'un fondo y un subrayado sobre lo mismo conviven en el mismo <mark>',
    () {
      final out = writer.write(_page, _content, [
        _mark('Intro corta.'),
        _mark(
          'Intro corta.',
          style: HighlightStyle.underline,
          color: _turquoise,
        ),
      ]);

      final marks = _parse(out).querySelectorAll('mark');
      expect(marks, hasLength(1));
      expect(
        marks.single.attributes['style'],
        'background-color:#FFF59D;text-decoration:underline;'
        'text-decoration-color:#4DD0E1',
      );
    },
  );

  test('cuando dos tramos se pisan, queda el color del que viene después', () {
    final out = writer.write(_page, _content, [
      _mark('Segunda parte: el vapor movió las fábricas.'),
      _mark('el vapor movió', color: _turquoise),
    ]);

    final marks = _parse(
      out,
    ).querySelectorAll('article p')[2].querySelectorAll('mark');
    expect(marks.map((m) => '${m.text}:${m.attributes['style']}').toList(), [
      'Segunda parte: :background-color:#FFF59D',
      'el vapor movió:background-color:#4DD0E1',
      ' las fábricas.:background-color:#FFF59D',
    ]);
  });

  test('la nota va en el title, con comillas y signos escapados', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.', note: 'Ver "cap. 2" & <más>'),
    ]);

    // Las comillas y el «&» no pueden quedar sueltos dentro del atributo.
    expect(out, contains('title="Ver &quot;cap. 2&quot; &amp; <más>"'));
    expect(
      _parse(out).querySelector('mark')!.attributes['title'],
      'Ver "cap. 2" & <más>',
    );
  });

  test('un tramo sin nota no lleva title', () {
    final out = writer.write(_page, _content, [_mark('Intro corta.')]);

    expect(
      _parse(out).querySelector('mark')!.attributes,
      isNot(contains('title')),
    );
  });

  test('lo que no está en la página se saltea, y los demás se pintan', () {
    final out = writer.write(_page, _content, [
      const DocumentMark(
        start: 0,
        end: 20,
        excerpt: 'Una oración que la página no tiene',
        color: _yellow,
      ),
      _mark('Intro corta.'),
    ]);

    expect(_marked(_parse(out)), 'Intro corta.');
  });

  test('si ningún tramo está, devuelve la página tal cual', () {
    const lost = DocumentMark(
      start: 0,
      end: 5,
      excerpt: 'Nada de esto está',
      color: _yellow,
    );

    expect(writer.write(_page, _content, [lost]), _page);
    expect(writer.write(_page, _content, const []), _page);
  });

  test('si las posiciones no coinciden con el texto, se ubica por el texto '
      'copiado', () {
    final out = writer.write(_page, _content, [
      const DocumentMark(
        start: 9000,
        end: 9012,
        excerpt: 'Intro corta.',
        color: _yellow,
      ),
    ]);

    expect(_marked(_parse(out)), 'Intro corta.');
  });

  test('el texto de un <script> o de un <style> no se pinta aunque diga lo '
      'mismo', () {
    final out = writer.write(
      '<html><body><p>Hola mundo.</p><script>Hola mundo.</script></body></html>',
      'Hola mundo.',
      [_mark('Hola mundo.', content: 'Hola mundo.')],
    );

    final page = _parse(out);
    expect(page.querySelectorAll('p mark'), hasLength(1));
    expect(page.querySelector('script mark'), isNull);
    expect(page.querySelector('script')!.text, 'Hola mundo.');
  });

  test('el espacio entre dos celdas o ítems no se envuelve en un <mark>', () {
    const html = '<html><body><ul><li>Uno</li> <li>Dos</li></ul></body></html>';
    const content = '- Uno\n- Dos';
    final out = writer.write(html, content, [
      _mark('Uno\n- Dos', content: content),
    ]);

    final page = _parse(out);
    expect(page.querySelector('ul > mark'), isNull);
    expect(page.querySelectorAll('li mark').map((m) => m.text), ['Uno', 'Dos']);
  });

  test('un color con ceros adelante sale completo, en seis dígitos', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.', color: 0xFF0000FF),
    ]);

    expect(
      _parse(out).querySelector('mark')!.attributes['style'],
      'background-color:#0000FF',
    );
  });

  test('una nota en blanco no se escribe', () {
    final out = writer.write(_page, _content, [
      _mark('Intro corta.', note: '   '),
    ]);

    expect(
      _parse(out).querySelector('mark')!.attributes,
      isNot(contains('title')),
    );
  });

  test('un subrayado sobre una parte de lo que tiene fondo parte el <mark> en '
      'tres: el fondo entero y la línea solo en el medio', () {
    final out = writer.write(_page, _content, [
      _mark('Segunda parte: el vapor movió las fábricas.'),
      _mark('el vapor', style: HighlightStyle.underline, color: _turquoise),
    ]);

    final marks = _parse(
      out,
    ).querySelectorAll('article p')[2].querySelectorAll('mark');
    expect(marks.map((m) => m.text).toList(), [
      'Segunda parte: ',
      'el vapor',
      ' movió las fábricas.',
    ]);
    expect(marks.map((m) => m.attributes['style']!.contains('underline')), [
      false,
      true,
      false,
    ]);
    expect(
      marks.map(
        (m) => m.attributes['style']!.contains('background-color:#FFF59D'),
      ),
      everyElement(isTrue),
    );
  });
}
