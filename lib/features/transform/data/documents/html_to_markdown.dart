import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// Convierte HTML a Markdown liviano sin tocar el texto (F22).
///
/// Lo usan los dos lectores que reciben HTML: el de EPUB, con cada capítulo,
/// y el de páginas web, con el artículo que dejó el modo lectura. Reemplaza
/// a `html2md`, que no servía para guardar un original: escapaba el texto
/// —"[1]" quedaba "\[1\]", "1. Intro" quedaba "1\. Intro", "a_b_c" quedaba
/// "a\_b\_c"—, sin ninguna opción para no hacerlo porque el escape es una
/// función privada que se aplica a todo nodo de texto; pegaba los
/// superíndices ("10⁶" pasaba a "106"); volcaba el `<title>` y el CSS y el
/// JavaScript del `<head>` como si fueran texto; dejaba las tablas anidadas
/// como HTML crudo, y guardaba sus opciones en variables globales que una
/// llamada le dejaba puestas a la siguiente.
///
/// **El texto sale igual que en el original, carácter por carácter.** Lo
/// único que se agrega es el marcado de estructura, porque así se muestra en
/// la app y así lo leen Obsidian y compañía:
///
/// - Párrafos y bloques separados por una línea en blanco, y `<br>` como un
///   salto de línea simple —no los dos espacios ni la barra invertida del
///   salto "duro" de CommonMark: serían caracteres que el original no tiene—.
/// - Títulos con `#` según su nivel. Un título con `<br>` adentro —"Capítulo
///   1⏎El comienzo", común en los libros— lleva la almohadilla en cada línea,
///   en vez de juntar las dos líneas o dejar la segunda como párrafo.
/// - Listas con `- ` y `n. `, con el número real: el `start` de la lista, el
///   `value` de cada ítem y el orden inverso de `reversed`. Una lista con
///   letras o romanos (`type="a"`, `"i"`…) conserva sus letras y sus romanos,
///   aunque Markdown no tenga cómo marcarla como lista: lo que se lee es lo
///   que el libro numeró.
/// - Negrita con `**` y cursiva con `*` —no con `_`: el visor de la app y
///   CommonMark aceptan `*` en medio de una palabra, "pala*bra*"—.
/// - Enlaces como `[texto](dirección)` e imágenes como `![alt](dirección)`.
/// - Citas con `> ` y bloques de código entre ` ``` `, con su texto intacto:
///   dentro de `<pre>` no se toca ni un espacio.
/// - Superíndices y subíndices como `<sup>6</sup>` y `<sub>2</sub>`: HTML en
///   línea, que CommonMark admite tal cual y Obsidian dibuja. Se descartó el
///   `^6^` de Pandoc: Obsidian no lo entiende, y un `^` al final de una línea
///   es para él una referencia a un bloque.
/// - Una línea divisoria (`<hr>`) como `* * *`, y no como `---`: `---` es lo
///   que separa los capítulos de un libro, y una pausa dentro de un capítulo
///   no puede confundirse con un capítulo nuevo.
/// - Tablas simples como tablas de Markdown. Adentro de una celda, y solo
///   ahí, `|` se escribe `\|`: sin eso partiría la celda en dos y el texto
///   quedaría en la columna equivocada. Es la misma convención que usa el
///   lector de Word. Una tabla que Markdown no puede representar —con otra
///   tabla adentro, celdas que ocupan varias filas o con más de una línea—
///   se aplana: el contenido de cada celda, en orden de lectura, como
///   bloques sueltos. Se pierde la grilla, nunca el texto.
///
/// **Lo que no se escapa.** Un "*" o un "[1]" que el texto trae de verdad se
/// guarda tal cual, aunque un visor de Markdown pueda interpretarlo como
/// marcado. Es el costo de no alterar el original, y se resuelve al
/// mostrarlo, no al guardarlo.
///
/// **Los espacios de formato del HTML sí se colapsan.** En HTML, una serie de
/// espacios, tabulaciones o saltos de línea del código fuente se ve como un
/// solo espacio: no es contenido, es cómo quedó indentado el archivo.
/// Colapsarlos es leer el HTML como lo lee un navegador, no alterar el texto.
/// El espacio duro (`&nbsp;`) sí es contenido y se conserva, igual que todo
/// dentro de `<pre>`. Las entidades (`&#233;`, `&amp;`…) llegan ya
/// traducidas por el parser.
///
/// **Lo que no es texto del documento** —`<head>` con su `<title>`,
/// `<script>`, `<style>`, `<template>`, `<noscript>`, `<iframe>`— se ignora.
/// El atributo `title` de un enlace, que es un globo al pasar el mouse y no
/// parte del texto, también.
String htmlToMarkdown(String html) {
  final body = html_parser.parse(html).body;
  return body == null ? '' : _render(body.nodes);
}

/// Lo mismo que [htmlToMarkdown], para el XHTML de un EPUB.
///
/// El XHTML se lee como XML, que es lo que es y como lo lee cualquier lector
/// de libros. Leerlo como HTML pierde capítulos enteros: un `<title/>` vacío
/// —frecuente en libros armados con herramientas automáticas— es para el
/// parser de HTML un título que no se cierra nunca, y todo el capítulo
/// termina adentro del título. Lo mismo con un `<script src="…"/>`.
///
/// Las entidades con nombre de HTML (`&nbsp;`, `&eacute;`) se reconocen
/// aunque el XML no las declare, porque los libros las usan igual. Si el
/// capítulo no es XML válido —pasa con libros mal armados—, se lee como
/// HTML en vez de perderlo.
String xhtmlToMarkdown(String xhtml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      xhtml,
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
  } on XmlException {
    return htmlToMarkdown(xhtml);
  }

  final root = document.rootElement;
  final body = root.localName == 'body'
      ? root
      : root.descendantElements
            .where((element) => element.localName == 'body')
            .firstOrNull;
  if (body == null) return '';

  final converted = _fromXml(body);
  return converted == null ? '' : _render(converted.nodes);
}

// ---------------------------------------------------------------------
// De XML al árbol de `package:html`
// ---------------------------------------------------------------------

/// Pasa un nodo de XML al árbol de `package:html`, para que las dos lecturas
/// compartan una sola conversión a Markdown.
dom.Node? _fromXml(XmlNode node) {
  if (node is XmlText || node is XmlCDATA) return dom.Text(node.value);
  if (node is! XmlElement) return null;

  final element = dom.Element.tag(node.localName.toLowerCase());
  for (final attribute in node.attributes) {
    element.attributes[attribute.localName] = attribute.value;
  }
  for (final child in node.children) {
    final converted = _fromXml(child);
    if (converted != null) element.append(converted);
  }

  // El parser de HTML descarta el salto de línea que sigue a `<pre>`: es
  // parte de cómo se escribe la etiqueta, no del texto. El de XML no lo
  // sabe, y sin esto el mismo bloque saldría distinto según el camino.
  if (element.localName == 'pre') {
    final first = element.nodes.firstOrNull;
    if (first is dom.Text && first.data.startsWith('\n')) {
      first.data = first.data.substring(1);
    }
  }

  return element;
}

// ---------------------------------------------------------------------
// La conversión
// ---------------------------------------------------------------------

String _render(List<dom.Node> nodes) =>
    (_Writer()..visitAll(nodes)).blocks.join('\n\n');

/// Lo que no es texto del documento.
const _ignored = {
  'head',
  'title',
  'meta',
  'link',
  'script',
  'style',
  'template',
  'noscript',
  'iframe',
};

/// Las etiquetas que arman bloques: cortan el párrafo en curso.
const _blockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'caption',
  'center',
  'dd',
  'details',
  'dialog',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'html',
  'legend',
  'li',
  'main',
  'menu',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'summary',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
};

final _formattingWhitespace = RegExp(r'[ \t\n\r\f]+');
final _repeatedSpaces = RegExp(' {2,}');
final _spacesAroundBreak = RegExp(r' *\n *');
final _edgeWhitespace = RegExp(r'^[ \n]+|[ \n]+$');
final _edges = RegExp(r'^([ \n]*)(.*?)([ \n]*)$', dotAll: true);
final _backtickRun = RegExp('`+');

/// Arma los bloques de una lista de nodos.
///
/// El texto en línea se va juntando en [_inline] y se cierra como un bloque
/// cuando aparece una etiqueta de bloque o se termina el contenido. Así un
/// `<div>` con texto suelto y párrafos adentro —HTML de verdad, no el de un
/// ejemplo prolijo— sale con cada cosa en su bloque y sin perder nada.
class _Writer {
  final _blocks = <String>[];
  final _inline = StringBuffer();

  List<String> get blocks {
    _flush();
    return _blocks;
  }

  /// Lo juntado en línea, sin cerrarlo como bloque: el contenido de una
  /// etiqueta en línea, que después se envuelve en su marcado.
  String get inline => _inline.toString();

  void visitAll(Iterable<dom.Node> nodes) {
    for (final node in nodes) {
      visit(node);
    }
  }

  void visit(dom.Node node) {
    if (node is dom.Text) {
      _inline.write(node.data.replaceAll(_formattingWhitespace, ' '));
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName ?? '';
    if (_ignored.contains(tag)) return;

    switch (tag) {
      case 'br':
        _inline.write('\n');
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _flush();
        _add(_heading(node, int.parse(tag.substring(1))));
      case 'ul' || 'ol' || 'menu':
        _flush();
        _add(_list(node));
      case 'li':
        // Un ítem fuera de una lista: HTML mal armado, pero el texto está.
        _flush();
        _add(_listItem('- ', node));
      case 'blockquote':
        _flush();
        _add(_quote(node));
      case 'pre':
        _flush();
        _add(_pre(node));
      case 'hr':
        _flush();
        _add('* * *');
      case 'table':
        _flush();
        _table(node).forEach(_add);
      default:
        if (_blockTags.contains(tag)) {
          _flush();
          visitAll(node.nodes);
          _flush();
        } else if (_containsBlock(node)) {
          // Una etiqueta en línea con bloques adentro —un enlace que envuelve
          // un párrafo entero—: no hay forma de marcarla sin romper los
          // bloques, así que se deja pasar su contenido tal cual.
          visitAll(node.nodes);
        } else {
          _inline.write(_inlineElement(node, tag));
        }
    }
  }

  void _add(String block) {
    if (block.isNotEmpty) _blocks.add(block);
  }

  /// Cierra el texto en línea juntado como un bloque.
  ///
  /// Al juntar nodos pueden quedar espacios repetidos —"uno " y " dos"— o
  /// pegados a un salto de línea: son el mismo espacio de formato que ya se
  /// colapsó adentro de cada nodo, y se colapsan igual. Nunca se toca un
  /// espacio duro: no es espacio de formato.
  void _flush() {
    final text = _inline
        .toString()
        .replaceAll(_repeatedSpaces, ' ')
        .replaceAll(_spacesAroundBreak, '\n')
        .replaceAll(_edgeWhitespace, '');
    _inline.clear();
    _add(text);
  }

  // -------------------------------------------------------------------
  // En línea
  // -------------------------------------------------------------------

  String _inlineElement(dom.Element element, String tag) {
    switch (tag) {
      case 'img':
        return _image(element);
      case 'wbr' || 'input':
        return '';
      case 'code' || 'kbd' || 'samp' || 'tt':
        return _code(element.text.replaceAll(_formattingWhitespace, ' '));
    }

    final content = (_Writer()..visitAll(element.nodes)).inline;
    return switch (tag) {
      'strong' || 'b' => _wrap(content, '**', '**'),
      'em' || 'i' => _wrap(content, '*', '*'),
      'sup' => _wrap(content, '<sup>', '</sup>'),
      'sub' => _wrap(content, '<sub>', '</sub>'),
      'a' => _link(content, element.attributes['href']),
      _ => content,
    };
  }

  /// Envuelve [content] en su marcado, con los espacios de los bordes
  /// afuera: `** hola **` no es negrita para ningún visor, y el espacio
  /// tiene que seguir estando entre las palabras. Sin contenido visible no
  /// hay nada que marcar.
  String _wrap(String content, String open, String close) {
    final match = _edges.firstMatch(content)!;
    final core = match[2]!;
    if (core.isEmpty) return content;
    return '${match[1]}$open$core$close${match[3]}';
  }

  /// Un enlace sin dirección —el ancla de una nota, un `<a id>` de los que
  /// los libros usan para marcar páginas— es solo su texto.
  String _link(String content, String? href) {
    final target = href?.trim() ?? '';
    if (target.isEmpty) return content;
    return _wrap(content, '[', '](${_destination(target)})');
  }

  /// Una imagen sin dirección es su texto alternativo: es lo que la
  /// reemplaza cuando no se puede ver.
  String _image(dom.Element element) {
    final alt = (element.attributes['alt'] ?? '')
        .replaceAll(_formattingWhitespace, ' ')
        .trim();
    final src = element.attributes['src']?.trim() ?? '';
    if (src.isEmpty) return alt;
    return '![$alt](${_destination(src)})';
  }

  /// Una dirección con espacios o paréntesis va entre `<>`: es la forma que
  /// tiene Markdown de aceptarla entera sin cambiarle ni un carácter.
  String _destination(String url) =>
      url.contains(RegExp(r'[\s()]')) ? '<$url>' : url;

  /// El código en línea, con una cerca de comillas invertidas más larga que
  /// cualquiera que el texto traiga adentro: así el texto va tal cual.
  String _code(String text) {
    if (text.trim().isEmpty) return text;
    final longest = _backtickRun
        .allMatches(text)
        .fold(0, (max, m) => m[0]!.length > max ? m[0]!.length : max);
    final fence = '`' * (longest + 1);
    final pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
    return '$fence$pad$text$pad$fence';
  }

  // -------------------------------------------------------------------
  // Bloques
  // -------------------------------------------------------------------

  String _heading(dom.Element element, int level) {
    final marker = '#' * level;
    return (_Writer()..visitAll(element.nodes)).blocks
        .join('\n')
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => '$marker $line')
        .join('\n');
  }

  String _list(dom.Element list) {
    final ordered = list.localName == 'ol';
    final type = list.attributes['type'] ?? '1';
    final reversed = list.attributes.containsKey('reversed');
    final items = list.children.where((child) => child.localName == 'li');
    var number =
        int.tryParse(list.attributes['start']?.trim() ?? '') ??
        (reversed ? items.length : 1);

    final lines = <String>[];
    for (final child in list.nodes) {
      if (child is dom.Element && child.localName == 'li') {
        number =
            int.tryParse(child.attributes['value']?.trim() ?? '') ?? number;
        final marker = ordered ? '${_ordinal(number, type)}. ' : '- ';
        lines.add(_listItem(marker, child));
        number += reversed ? -1 : 1;
      } else {
        // Lo que no es un ítem —una lista anidada puesta directo adentro de
        // otra, texto suelto— es HTML mal armado, pero es contenido: va
        // indentado bajo el ítem anterior.
        final stray = (_Writer()..visit(child)).blocks.join('\n');
        if (stray.isNotEmpty) lines.add(_indent(stray, '  '));
      }
    }
    return lines.join('\n');
  }

  /// Un ítem con su marcador en la primera línea y el resto indentado a la
  /// misma altura, que es lo que hace que una lista anidada o un segundo
  /// párrafo sigan dentro del ítem.
  String _listItem(String marker, dom.Element item) {
    final content = (_Writer()..visitAll(item.nodes)).blocks.join('\n');
    if (content.isEmpty) return marker.trimRight();

    final newline = content.indexOf('\n');
    if (newline == -1) return '$marker$content';
    final rest = _indent(content.substring(newline + 1), ' ' * marker.length);
    return '$marker${content.substring(0, newline)}\n$rest';
  }

  String _indent(String text, String pad) => text
      .split('\n')
      .map((line) => line.isEmpty ? line : '$pad$line')
      .join('\n');

  String _quote(dom.Element element) {
    final content = (_Writer()..visitAll(element.nodes)).blocks.join('\n\n');
    if (content.isEmpty) return '';
    return content
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
  }

  /// Un bloque preformateado, entre cercas: su texto va entero y sin tocar,
  /// con cada espacio y cada salto de línea donde estaban.
  String _pre(dom.Element element) {
    final text = _rawText(element);
    if (text.isEmpty) return '';
    final longest = _backtickRun
        .allMatches(text)
        .fold(0, (max, m) => m[0]!.length > max ? m[0]!.length : max);
    final fence = '`' * (longest < 3 ? 3 : longest + 1);
    final newline = text.endsWith('\n') ? '' : '\n';
    return '$fence\n$text$newline$fence';
  }

  /// El texto tal cual, con los `<br>` como saltos de línea: dentro de un
  /// `<pre>` no se colapsa nada.
  String _rawText(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    if (_ignored.contains(tag)) return '';
    if (tag == 'br') return '\n';
    return node.nodes.map(_rawText).join();
  }

  // -------------------------------------------------------------------
  // Tablas
  // -------------------------------------------------------------------

  List<String> _table(dom.Element table) {
    final blocks = <String>[];

    final caption = table.children
        .where((child) => child.localName == 'caption')
        .firstOrNull;
    if (caption != null) {
      blocks.addAll((_Writer()..visitAll(caption.nodes)).blocks);
    }

    // Solo las filas de esta tabla, no las de una tabla anidada.
    final rows = <dom.Element>[];
    var headerInThead = false;
    for (final child in table.children) {
      if (child.localName == 'tr') {
        rows.add(child);
      } else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName)) {
        final sectionRows = child.children.where((r) => r.localName == 'tr');
        if (child.localName == 'thead' && rows.isEmpty) {
          headerInThead = sectionRows.isNotEmpty;
        }
        rows.addAll(sectionRows);
      }
    }

    final grid = [
      for (final row in rows)
        [
          for (final cell in row.children)
            if (cell.localName == 'td' || cell.localName == 'th') cell,
        ],
    ];
    final contents = [
      for (final row in grid)
        [for (final cell in row) (_Writer()..visitAll(cell.nodes)).blocks],
    ];

    final simple =
        table.querySelector('table') == null &&
        grid.every(
          (row) => row.every(
            (cell) =>
                (int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1) <= 1,
          ),
        ) &&
        contents.every(
          (row) => row.every(
            (cell) =>
                cell.length <= 1 && !(cell.firstOrNull ?? '').contains('\n'),
          ),
        );

    if (!simple) {
      // Aplanada: el texto de cada celda, en orden de lectura.
      for (final row in contents) {
        for (final cell in row) {
          blocks.addAll(cell);
        }
      }
      return blocks;
    }

    final cells = [
      for (var r = 0; r < grid.length; r++)
        [
          for (var c = 0; c < grid[r].length; c++) ...[
            (contents[r][c].firstOrNull ?? '').replaceAll('|', r'\|'),
            // Una celda que ocupa varias columnas deja las que ocupa
            // vacías: Markdown no sabe unirlas, y así nada se corre de
            // columna.
            for (
              var extra = 1;
              extra <
                  (int.tryParse(grid[r][c].attributes['colspan'] ?? '') ?? 1);
              extra++
            )
              '',
          ],
        ],
    ];
    if (cells.isEmpty) return blocks;

    final columns = cells.fold(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columns == 0) return blocks;

    // Markdown exige una fila de encabezado. Si la tabla no tiene una —una
    // primera fila hecha de `<th>` o dentro de `<thead>`—, va vacía: tomar
    // la primera fila de datos como encabezado le cambiaría el sentido.
    final firstIsHeader =
        headerInThead ||
        (grid.first.isNotEmpty &&
            grid.first.every((cell) => cell.localName == 'th'));
    final header = firstIsHeader ? cells.first : <String>[];
    final body = firstIsHeader ? cells.skip(1) : cells;

    String line(List<String> row) {
      final padded = [...row, ...List.filled(columns - row.length, '')];
      return '| ${padded.join(' | ')} |';
    }

    blocks.add(
      [
        line(header),
        line(List.filled(columns, '---')),
        for (final row in body) line(row),
      ].join('\n'),
    );
    return blocks;
  }
}

/// ¿Hay algún bloque adentro de [element]?
bool _containsBlock(dom.Element element) => element.children.any(
  (child) =>
      _blockTags.contains(child.localName) ||
      (!_ignored.contains(child.localName) && _containsBlock(child)),
);

/// El número de un ítem escrito como lo escribe la lista: `3`, `c`, `C`,
/// `iii` o `III`.
String _ordinal(int number, String type) {
  if (number < 1) return '$number';
  return switch (type) {
    'a' => _alphabetic(number),
    'A' => _alphabetic(number).toUpperCase(),
    'i' => _roman(number),
    'I' => _roman(number).toUpperCase(),
    _ => '$number',
  };
}

String _alphabetic(int number) {
  final letters = StringBuffer();
  var n = number;
  while (n > 0) {
    n--;
    letters.write(String.fromCharCode(0x61 + n % 26));
    n ~/= 26;
  }
  return letters.toString().split('').reversed.join();
}

String _roman(int number) {
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = [
    'm',
    'cm',
    'd',
    'cd',
    'c',
    'xc',
    'l',
    'xl',
    'x',
    'ix',
    'v',
    'iv',
    'i',
  ];
  final roman = StringBuffer();
  var n = number;
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      roman.write(symbols[i]);
      n -= values[i];
    }
  }
  return roman.toString();
}
