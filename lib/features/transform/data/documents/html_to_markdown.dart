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
///   que el libro numeró. Lo que sigue dentro de un ítem —un segundo
///   párrafo, una lista anidada— va indentado al ancho de su marcador ("1. "
///   son tres columnas), y un párrafo más va separado por una línea en
///   blanco: sin ella, CommonMark lo pegaría al anterior o a la sublista.
/// - Negrita con `**`, cursiva con `*` —no con `_`: el visor de la app y
///   CommonMark aceptan `*` en medio de una palabra, "pala*bra*"— y tachado
///   con `~~`: un precio tachado es otro precio, y sin la marca "100 80 €"
///   dice otra cosa.
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
/// - Tablas simples como tablas de Markdown, con el encabezado (`<thead>`)
///   primero y el pie (`<tfoot>`) al final, donde se ven, aunque el archivo
///   los escriba en otro orden. Adentro de una celda, y solo ahí, `|` se
///   escribe `\|`: sin eso partiría la celda en dos y el texto quedaría en la
///   columna equivocada. Es la misma convención que usa el lector de Word.
///   Una tabla que Markdown no puede representar —con otra tabla adentro,
///   celdas que ocupan varias filas o con más de una línea— se aplana: el
///   contenido de cada celda, en orden de lectura, como bloques sueltos. Se
///   pierde la grilla, nunca el texto.
/// - Las fórmulas en MathML como se leen: `x<sup>2</sup>`, `1/2`, `√(x)`, y
///   sin las anotaciones —el LaTeX o el MathML de contenido que algunos
///   libros agregan para las máquinas—, que repetían la fórmula.
///
/// Una marca que en el original cruza un `<br>` —una negrita de dos
/// líneas, un enlace partido— se cierra y se vuelve a abrir en cada línea:
/// el visor de la app lee línea por línea, y un `**` que abre en una y
/// cierra en otra no se reconoce en ninguna.
///
/// **Lo que no se escapa.** Un "*" o un "[1]" que el texto trae de verdad se
/// guarda tal cual, aunque un visor de Markdown pueda interpretarlo como
/// marcado. Es el costo de no alterar el original, y se resuelve al
/// mostrarlo, no al guardarlo. Donde el marcado de Markdown no puede
/// encerrar el texto sin escaparlo —un enlace cuyo texto tiene un corchete
/// sin pareja, una dirección con `<` o `>`— se usa la etiqueta de HTML en
/// línea (`<a href="…">…</a>`), que CommonMark admite tal cual.
///
/// **Los espacios de formato del HTML sí se colapsan.** En HTML, una serie de
/// espacios, tabulaciones o saltos de línea del código fuente se ve como un
/// solo espacio: no es contenido, es cómo quedó indentado el archivo.
/// Colapsarlos es leer el HTML como lo lee un navegador, no alterar el texto.
/// El espacio duro (`&nbsp;`) sí es contenido y se conserva, igual que todo
/// dentro de `<pre>` y las direcciones de los enlaces. Las entidades
/// (`&#233;`, `&amp;`…) llegan ya traducidas por el parser.
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
/// Los saltos de línea de Windows se leen como uno solo, como manda XML:
/// sin eso, dentro de un `<pre>` quedaba cada `\r` guardado como texto. Las
/// entidades con nombre de HTML (`&nbsp;`, `&eacute;`) se reconocen aunque
/// el XML no las declare, porque los libros las usan igual, y las que el
/// capítulo sí declara en su `<!DOCTYPE>` se expanden a su texto.
///
/// Si el capítulo no es XML válido —pasa con libros mal armados: un `<br>`
/// sin cerrar alcanza—, se lee como HTML en vez de perderlo. Antes de eso,
/// cada etiqueta autocerrada que no es vacía en HTML —`<title/>`,
/// `<script src="…"/>`, `<textarea/>`, `<a id="p12"/>`— se escribe abierta
/// y cerrada, que es lo que significa en XHTML: el parser de HTML no
/// entiende la barra, y el capítulo entero quedaba adentro del título (se
/// perdía sin aviso) o adentro de un `<textarea>` (salía como marcado
/// crudo) (F22).
String xhtmlToMarkdown(String xhtml) {
  final source = xhtml.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      source,
      entityMapping: _DeclaredEntityMapping(_declaredEntities(source)),
    );
  } on XmlException {
    return htmlToMarkdown(_openSelfClosingTags(source));
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
// Lo que el XHTML necesita antes de leerlo
// ---------------------------------------------------------------------

/// Las entidades que declara el `<!DOCTYPE>` del capítulo, con su texto.
///
/// Solo las simples: un texto literal, sin otra entidad ni marcado adentro.
/// Las que arman marcado o se apoyan en otras —raras en un libro— se dejan
/// sin expandir, como `&nombre;`: el texto no se pierde, se ve la
/// referencia.
Map<String, String> _declaredEntities(String source) {
  final subset = _internalSubset.firstMatch(source)?[1];
  if (subset == null) return const {};
  return {
    for (final entity in _entityDeclaration.allMatches(subset))
      if (!(entity[2] ?? entity[3]!).contains(RegExp('[&<%]')))
        entity[1]!: entity[2] ?? entity[3]!,
  };
}

final _internalSubset = RegExp(r'<!DOCTYPE[^\[>]*\[([\s\S]*?)\]\s*>');
final _entityDeclaration = RegExp(
  r'''<!ENTITY\s+([A-Za-z_:][\w.:-]*)\s+(?:"([^"]*)"|'([^']*)')\s*>''',
);

/// Las entidades de HTML, más las que declara el capítulo.
class _DeclaredEntityMapping extends XmlDefaultEntityMapping {
  const _DeclaredEntityMapping(this.declared) : super.html5();

  final Map<String, String> declared;

  @override
  String? decodeEntity(String input) =>
      declared[input] ?? super.decodeEntity(input);
}

/// Las etiquetas que en HTML no tienen contenido: para ellas, y solo para
/// ellas, la barra de `<br/>` no cambia nada.
const _voidTags = {
  'area',
  'base',
  'basefont',
  'bgsound',
  'br',
  'col',
  'embed',
  'frame',
  'hr',
  'img',
  'input',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

final _selfClosingTag = RegExp(
  r'''<([A-Za-z][\w:.-]*)((?:\s(?:[^>"']|"[^"]*"|'[^']*')*?)?)\s*/>''',
);

/// `<x …/>` como `<x …></x>`, salvo las etiquetas vacías de HTML.
String _openSelfClosingTags(String source) =>
    source.replaceAllMapped(_selfClosingTag, (tag) {
      final name = tag[1]!;
      final local = name.substring(name.indexOf(':') + 1).toLowerCase();
      if (_voidTags.contains(local)) return tag[0]!;
      return '<$name${tag[2]}></$name>';
    });

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
    // Solo los atributos sin prefijo. Uno de otro espacio de nombres
    // —`epub:type`, `xml:lang`— tiene el mismo nombre local que uno de
    // XHTML, y pisaba al de verdad: `epub:type="footnote"` dejaba una
    // lista con `type="footnote"` en vez del `type="a"` que tenía (F22).
    if (attribute.name.prefix != null) continue;
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

/// Lo que no es texto del documento. Las anotaciones de una fórmula son
/// la misma fórmula escrita para las máquinas —LaTeX, MathML de
/// contenido—, y `<mphantom>` es un hueco invisible.
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
  'annotation',
  'annotation-xml',
  'mphantom',
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

/// La marca de cada etiqueta de énfasis.
const _emphasisMarks = {
  'strong': '**',
  'b': '**',
  'em': '*',
  'i': '*',
  'del': '~~',
  's': '~~',
  'strike': '~~',
};

final _formattingWhitespace = RegExp(r'[ \t\n\r\f]+');
final _leadingSpaces = RegExp('^ +');
final _trailingSpaces = RegExp(r' +$');
final _edgeWhitespace = RegExp(r'^[ \n]+|[ \n]+$');
final _spacesAroundBreak = RegExp(r' *\n *');
// `\s` incluye el espacio duro: `**&nbsp;hola**` tampoco es negrita.
final _edges = RegExp(r'^(\s*)(.*?)(\s*)$', dotAll: true);
final _leadingPunctuation = RegExp(r'^[\s\p{P}\p{S}]+', unicode: true);
final _trailingPunctuation = RegExp(r'[\s\p{P}\p{S}]+$', unicode: true);
final _wordCharacter = RegExp(r'^[\p{L}\p{N}\p{M}]', unicode: true);
final _backtickRun = RegExp('`+');

/// Arma los bloques de una lista de nodos.
///
/// El texto en línea se va juntando en [_pieces] y se cierra como un bloque
/// cuando aparece una etiqueta de bloque o se termina el contenido. Así un
/// `<div>` con texto suelto y párrafos adentro —HTML de verdad, no el de un
/// ejemplo prolijo— sale con cada cosa en su bloque y sin perder nada.
class _Writer {
  final _blocks = <String>[];

  /// Cuáles de [_blocks] son listas: dentro de un ítem, una sublista va
  /// pegada a lo anterior y un párrafo va separado.
  final _listBlocks = <int>{};

  /// Lo juntado en línea, en los trozos en que llegó: se une una sola vez,
  /// al cerrar el bloque, y mientras tanto el último trozo se puede
  /// retocar.
  final _pieces = <String>[];

  /// La marca con la que termina el último trozo, si es un énfasis que
  /// todavía se puede continuar: ver [_writeEmphasis].
  String? _openMark;

  /// El nodo que sigue al que se está visitando, para saber qué letra viene
  /// después de un énfasis.
  dom.Node? _following;

  List<String> get blocks {
    _flush();
    return _blocks;
  }

  /// Los bloques como el contenido de un ítem de lista: un párrafo más va
  /// separado por una línea en blanco —si no, CommonMark lo pega a la
  /// sublista de arriba—, y una sublista va pegada a lo que la precede,
  /// como se escribe una lista anidada.
  String get itemContent {
    final all = blocks;
    final content = StringBuffer();
    for (var i = 0; i < all.length; i++) {
      if (i > 0) content.write(_listBlocks.contains(i) ? '\n' : '\n\n');
      content.write(all[i]);
    }
    return content.toString();
  }

  /// Lo juntado en línea, sin cerrarlo como bloque: el contenido de una
  /// etiqueta en línea, que después se envuelve en su marcado.
  String get inline => _pieces.join();

  void visitAll(Iterable<dom.Node> nodes) {
    final list = nodes.toList();
    for (var i = 0; i < list.length; i++) {
      _following = i + 1 < list.length ? list[i + 1] : null;
      visit(list[i]);
    }
    _following = null;
  }

  void visit(dom.Node node) {
    final following = _following;
    if (node is dom.Text) {
      _write(node.data.replaceAll(_formattingWhitespace, ' '));
      return;
    }
    if (node is! dom.Element) return;

    final tag = node.localName ?? '';
    if (_ignored.contains(tag)) return;

    switch (tag) {
      case 'br':
        _write('\n');
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _flush();
        _add(_heading(node, int.parse(tag.substring(1))));
      case 'ul' || 'ol' || 'menu':
        _flush();
        _add(_list(node), list: true);
      case 'li':
        // Un ítem fuera de una lista: HTML mal armado, pero el texto está.
        _flush();
        _add(_listItem('- ', node), list: true);
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
      case 'math' when node.attributes['display'] == 'block':
        _flush();
        _write(_inlineElement(node, tag));
        _flush();
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
        } else if (_emphasisMarks[tag] case final mark?) {
          _writeEmphasis(node, mark, following);
        } else {
          _write(_inlineElement(node, tag));
        }
    }
  }

  void _add(String block, {bool list = false}) {
    if (block.isEmpty) return;
    if (list) _listBlocks.add(_blocks.length);
    _blocks.add(block);
  }

  /// Suma [text] a lo juntado en línea.
  ///
  /// Los espacios de formato se colapsan al juntar, como en un navegador:
  /// un espacio que sigue a otro espacio o a un salto de línea no se ve, y
  /// uno que queda justo antes de un salto de línea tampoco. Se hace acá, al
  /// juntar, y no sobre el bloque terminado, para no tocar los espacios que
  /// son contenido: los de una dirección (`notas/la  nota.html`) o los de un
  /// código en línea. Nunca se toca un espacio duro: no es espacio de
  /// formato.
  void _write(String text) {
    var piece = text;
    if (piece.startsWith(' ') && (_endsWith(' ') || _endsWith('\n'))) {
      piece = piece.replaceFirst(_leadingSpaces, '');
    }
    if (piece.isEmpty) return;
    if (piece.startsWith('\n')) _trimTrailingSpaces();
    _pieces.add(piece);
    _openMark = null;
  }

  bool _endsWith(String character) =>
      _pieces.isNotEmpty && _pieces.last.endsWith(character);

  void _trimTrailingSpaces() {
    while (_pieces.isNotEmpty) {
      final trimmed = _pieces.last.replaceFirst(_trailingSpaces, '');
      if (trimmed.isNotEmpty) {
        _pieces.last = trimmed;
        return;
      }
      _pieces.removeLast();
    }
  }

  /// La última letra juntada, o `null` si no hay ninguna.
  String? get _lastCharacter {
    if (_pieces.isEmpty) return null;
    final last = _pieces.last;
    return last.substring(_characterStart(last, last.length - 1));
  }

  /// Cierra el texto en línea juntado como un bloque.
  void _flush() {
    final text = _pieces.join().replaceAll(_edgeWhitespace, '');
    _pieces.clear();
    _openMark = null;
    _add(text);
  }

  // -------------------------------------------------------------------
  // En línea
  // -------------------------------------------------------------------

  /// Una negrita, una cursiva o un tachado.
  ///
  /// Dos marcas iguales seguidas —`<i>pala</i><i>bra</i>`, que los
  /// conversores de Word dejan a cada rato— se escriben como una sola:
  /// "*pala**bra*" no es cursiva para ningún visor, y "*palabra*" es lo que
  /// se veía.
  void _writeEmphasis(dom.Element element, String mark, dom.Node? following) {
    final content = (_Writer()..visitAll(element.nodes)).inline;
    var marked = _emphasis(
      content,
      mark,
      before: _lastCharacter,
      after: _firstCharacter(following),
    );
    if (_openMark == mark && marked.startsWith(mark)) {
      final last = _pieces.last;
      _pieces.last = last.substring(0, last.length - mark.length);
      marked = marked.substring(mark.length);
    }
    _write(marked);
    if (marked.endsWith(mark)) _openMark = mark;
  }

  /// Envuelve [content] en [mark], línea por línea, con los espacios de los
  /// bordes afuera: `** hola **` no es negrita para ningún visor, y el
  /// espacio tiene que seguir estando entre las palabras.
  ///
  /// La puntuación de un borde también queda afuera, pero solo cuando está
  /// pegada a una letra de afuera: "*hola,*mundo" o "palabra**¡hola**" no
  /// son énfasis para CommonMark —la marca queda entre un signo y una
  /// letra—, y "*hola*,mundo" sí. Con un espacio de por medio el signo se
  /// queda adentro, con su formato.
  String _emphasis(
    String content,
    String mark, {
    required String? before,
    required String? after,
  }) {
    final lines = content.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        _emphasizeLine(
          lines[i],
          mark,
          before: i == 0 ? before : null,
          after: i == lines.length - 1 ? after : null,
        ),
    ].join('\n');
  }

  String _emphasizeLine(
    String line,
    String mark, {
    required String? before,
    required String? after,
  }) {
    final match = _edges.firstMatch(line)!;
    var lead = match[1]!;
    var core = match[2]!;
    var trail = match[3]!;
    if (lead.isEmpty && before != null && _wordCharacter.hasMatch(before)) {
      final outside = _leadingPunctuation.firstMatch(core)?[0] ?? '';
      lead = outside;
      core = core.substring(outside.length);
    }
    if (trail.isEmpty && after != null && _wordCharacter.hasMatch(after)) {
      final outside = _trailingPunctuation.firstMatch(core)?[0] ?? '';
      trail = outside;
      core = core.substring(0, core.length - outside.length);
    }
    if (core.isEmpty) return line;
    return '$lead$mark$core$mark$trail';
  }

  String _inlineElement(dom.Element element, String tag) {
    switch (tag) {
      case 'img':
        return _image(element);
      case 'wbr':
        return '';
      case 'input':
        return _input(element);
      case 'select':
        return _select(element);
      case 'code' || 'kbd' || 'samp' || 'tt':
        return _code(element);
      case 'semantics':
        // La fórmula es el primer hijo; lo demás son anotaciones.
        final formula = element.children.firstOrNull;
        return formula == null ? '' : (_Writer()..visit(formula)).inline;
      case 'msup' || 'msub' || 'msubsup' || 'mfrac' || 'msqrt' || 'mroot':
        return _mathLayout(element, tag);
    }

    final content = (_Writer()..visitAll(element.nodes)).inline;
    return switch (tag) {
      'sup' => _wrap(content, '<sup>', '</sup>'),
      'sub' => _wrap(content, '<sub>', '</sub>'),
      'a' => _link(content, element.attributes['href']),
      'rt' => _rubyText(element, content),
      _ => content,
    };
  }

  /// Envuelve [content] en su marcado, línea por línea, con los espacios de
  /// los bordes afuera. Sin contenido visible no hay nada que marcar.
  String _wrap(String content, String open, String close) => content
      .split('\n')
      .map((line) => _wrapLine(line, open, close))
      .join('\n');

  String _wrapLine(String line, String open, String close) {
    final match = _edges.firstMatch(line)!;
    final core = match[2]!;
    if (core.isEmpty) return line;
    return '${match[1]}$open$core$close${match[3]}';
  }

  /// Un enlace sin dirección —el ancla de una nota, un `<a id>` de los que
  /// los libros usan para marcar páginas— es solo su texto.
  ///
  /// Un texto con un corchete sin pareja —"ver [1"— cerraría el enlace
  /// antes de tiempo, y una dirección con `<` o `>` no entra ni entre `<>`:
  /// los dos van como `<a href="…">…</a>`, sin escapar el texto.
  String _link(String content, String? href) {
    final target = _url(href);
    if (target.isEmpty) return content;
    final destination = _destination(target);
    return content
        .split('\n')
        .map((line) {
          if (destination != null && _balancedBrackets(line)) {
            return _wrapLine(line, '[', ']($destination)');
          }
          return _wrapLine(line, '<a href="${_attribute(target)}">', '</a>');
        })
        .join('\n');
  }

  /// Una imagen sin dirección es su texto alternativo: es lo que la
  /// reemplaza cuando no se puede ver.
  String _image(dom.Element element) {
    final alt = (element.attributes['alt'] ?? '')
        .replaceAll(_formattingWhitespace, ' ')
        .trim();
    final src = _url(element.attributes['src']);
    if (src.isEmpty) return alt;
    final destination = _destination(src);
    if (destination == null || !_balancedBrackets(alt)) {
      return '<img src="${_attribute(src)}" alt="${_attribute(alt)}">';
    }
    return '![$alt]($destination)';
  }

  /// Un campo de formulario se ve con lo que tiene escrito; los que no
  /// muestran texto —ocultos, casillas, archivos, contraseñas— no aportan
  /// nada.
  String _input(dom.Element element) {
    final type = (element.attributes['type'] ?? 'text').trim().toLowerCase();
    if (type == 'image') return _image(element);
    const silent = {
      'hidden',
      'checkbox',
      'radio',
      'file',
      'password',
      'range',
      'color',
    };
    if (silent.contains(type)) return '';
    return (element.attributes['value'] ?? '').replaceAll(
      _formattingWhitespace,
      ' ',
    );
  }

  /// Las opciones de una lista desplegable, una por línea: juntas se leían
  /// como una sola palabra ("UnoDos").
  String _select(dom.Element element) => element
      .querySelectorAll('option')
      .map(
        (option) => option.text.replaceAll(_formattingWhitespace, ' ').trim(),
      )
      .where((text) => text.isNotEmpty)
      .join('\n');

  /// La lectura de un `<ruby>` va entre paréntesis si el libro no los puso
  /// con `<rp>`: es lo que muestra un lector que no dibuja el texto arriba,
  /// y sin ellos "漢kan" parecía una sola palabra.
  String _rubyText(dom.Element element, String content) {
    if (content.trim().isEmpty) return content;
    if (element.previousElementSibling?.localName == 'rp') return content;
    return '($content)';
  }

  /// La dirección tal cual, sin los espacios de los bordes ni los saltos de
  /// línea y tabulaciones que un navegador también descarta.
  String _url(String? value) =>
      (value ?? '').replaceAll(RegExp('[\t\n\r]'), '').trim();

  /// Una dirección con espacios o paréntesis va entre `<>`: es la forma que
  /// tiene Markdown de aceptarla entera sin cambiarle ni un carácter. Una
  /// con `<` o `>` no entra de ninguna de las dos formas: `null`.
  String? _destination(String url) {
    if (url.contains(RegExp('[<>]'))) return null;
    return url.contains(RegExp(r'[\s()]')) ? '<$url>' : url;
  }

  /// El valor de un atributo de HTML en línea.
  String _attribute(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

  /// El código en línea, con una cerca de comillas invertidas más larga que
  /// cualquiera que el texto traiga adentro: así el texto va tal cual.
  ///
  /// Un `<br>` adentro es un salto de línea también acá —antes el código se
  /// leía con el texto de sus nodos y "linea1⏎linea2" quedaba
  /// "linea1linea2"—, y como un código en línea no puede cruzar líneas,
  /// cada una lleva el suyo.
  String _code(dom.Element element) => _inlineRawText(
    element,
  ).replaceAll(_spacesAroundBreak, '\n').split('\n').map(_codeSpan).join('\n');

  String _codeSpan(String text) {
    if (text.trim().isEmpty) return text;
    final longest = _backtickRun
        .allMatches(text)
        .fold(0, (max, m) => m[0]!.length > max ? m[0]!.length : max);
    final fence = '`' * (longest + 1);
    final pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
    return '$fence$pad$text$pad$fence';
  }

  /// El texto de un elemento en línea sin su marcado: los espacios de
  /// formato colapsados, y los `<br>` como saltos de línea.
  String _inlineRawText(dom.Node node) {
    if (node is dom.Text) {
      return node.data.replaceAll(_formattingWhitespace, ' ');
    }
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    if (_ignored.contains(tag)) return '';
    if (tag == 'br') return '\n';
    if (tag == 'img') return node.attributes['alt'] ?? '';
    return node.nodes.map(_inlineRawText).join();
  }

  // -------------------------------------------------------------------
  // Fórmulas (MathML)
  // -------------------------------------------------------------------

  /// Las formas de MathML que ubican una parte respecto de otra, escritas
  /// como se leen: antes se juntaba el texto de todas y `x²` quedaba "x2",
  /// un medio "12".
  String _mathLayout(dom.Element element, String tag) {
    final parts = element.children;
    String part(int index) => index < parts.length
        ? (_Writer()..visit(parts[index])).inline.trim()
        : '';
    String grouped(int index) {
      final text = part(index);
      final child = index < parts.length ? parts[index] : null;
      final compound =
          child != null &&
          (child.localName == 'mfrac' ||
              (child.localName == 'mrow' && child.children.length > 1));
      return compound ? '($text)' : text;
    }

    return switch (tag) {
      'msup' => '${part(0)}${_wrap(part(1), '<sup>', '</sup>')}',
      'msub' => '${part(0)}${_wrap(part(1), '<sub>', '</sub>')}',
      'msubsup' =>
        '${part(0)}${_wrap(part(1), '<sub>', '</sub>')}'
            '${_wrap(part(2), '<sup>', '</sup>')}',
      'mfrac' => '${grouped(0)}/${grouped(1)}',
      'mroot' => '${_wrap(part(1), '<sup>', '</sup>')}√(${part(0)})',
      // `<msqrt>` lleva la fórmula entera adentro, no una parte.
      _ => '√(${(_Writer()..visitAll(element.nodes)).inline.trim()})',
    };
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
    var indent = 2;
    for (final child in list.nodes) {
      if (child is dom.Element && child.localName == 'li') {
        number =
            int.tryParse(child.attributes['value']?.trim() ?? '') ?? number;
        final marker = ordered ? '${_ordinal(number, type)}. ' : '- ';
        lines.add(_listItem(marker, child));
        indent = marker.length;
        number += reversed ? -1 : 1;
      } else {
        // Lo que no es un ítem —una lista anidada puesta directo adentro de
        // otra, texto suelto— es HTML mal armado, pero es contenido: va
        // indentado bajo el ítem anterior, al ancho de su marcador.
        final stray = (_Writer()..visit(child)).itemContent;
        if (stray.isNotEmpty) lines.add(_indent(stray, ' ' * indent));
      }
    }
    return lines.join('\n');
  }

  /// Un ítem con su marcador en la primera línea y el resto indentado a la
  /// misma altura, que es lo que hace que una lista anidada o un segundo
  /// párrafo sigan dentro del ítem.
  String _listItem(String marker, dom.Element item) {
    final content = (_Writer()..visitAll(item.nodes)).itemContent;
    if (content.isEmpty) return marker.trimRight();

    final newline = content.indexOf('\n');
    if (newline == -1) return '$marker$content';
    final rest = _indent(content.substring(newline + 1), ' ' * marker.length);
    return '$marker${content.substring(0, newline)}\n$rest';
  }

  /// Las líneas en blanco quedan vacías: para CommonMark una línea en
  /// blanco no corta el ítem si lo que sigue está indentado, y unos
  /// espacios sueltos serían caracteres invisibles de más en el texto.
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

  /// El texto tal cual, con los `<br>` como saltos de línea y cada imagen
  /// como su texto alternativo: dentro de un `<pre>` no se colapsa nada.
  String _rawText(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is! dom.Element) return '';
    final tag = node.localName ?? '';
    if (_ignored.contains(tag)) return '';
    if (tag == 'br') return '\n';
    if (tag == 'img') return node.attributes['alt'] ?? '';
    return node.nodes.map(_rawText).join();
  }

  // -------------------------------------------------------------------
  // Tablas
  // -------------------------------------------------------------------

  List<String> _table(dom.Element table) {
    final blocks = <String>[];

    // Las filas de esta tabla, no las de una tabla anidada, repartidas como
    // se ven: el encabezado arriba y el pie abajo, aunque el archivo los
    // escriba en otro orden —XHTML 1.1 exige el `<tfoot>` antes del
    // `<tbody>`, y el total quedaba como primera fila—.
    final head = <List<dom.Element>>[];
    final body = <List<dom.Element>>[];
    final foot = <List<dom.Element>>[];
    // Lo que no puede ir dentro de una tabla —texto o un párrafo sueltos
    // entre las filas— sale antes de ella, como lo saca un navegador. El
    // parser de HTML ya lo hace; el XHTML de un libro, leído como XML, lo
    // traía adentro, y se perdía.
    final fostered = <dom.Node>[];
    dom.Element? caption;

    void collect(Iterable<dom.Node> nodes, List<List<dom.Element>> into) {
      // Celdas sueltas, sin su `<tr>`: forman una fila, como en HTML.
      List<dom.Element>? implicitRow;
      for (final node in nodes) {
        final name = node is dom.Element ? node.localName : null;
        if (name == 'tr') {
          implicitRow = null;
          into.add(_cells(node as dom.Element, fostered));
        } else if (name == 'td' || name == 'th') {
          if (implicitRow == null) into.add(implicitRow = []);
          implicitRow.add(node as dom.Element);
        } else if (!_isBlank(node)) {
          fostered.add(node);
        }
      }
    }

    final loose = <dom.Node>[];
    void collectLoose() {
      collect(loose, body);
      loose.clear();
    }

    for (final node in table.nodes) {
      final name = node is dom.Element ? node.localName : null;
      switch (name) {
        case 'caption':
          caption ??= node as dom.Element;
        case 'colgroup' || 'col':
          break;
        case 'thead':
          collectLoose();
          collect(node.nodes, head);
        case 'tbody':
          collectLoose();
          collect(node.nodes, body);
        case 'tfoot':
          collectLoose();
          collect(node.nodes, foot);
        default:
          loose.add(node);
      }
    }
    collectLoose();

    if (fostered.isNotEmpty) {
      blocks.addAll((_Writer()..visitAll(fostered)).blocks);
    }
    if (caption != null) {
      blocks.addAll((_Writer()..visitAll(caption.nodes)).blocks);
    }

    final grid = [...head, ...body, ...foot];
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
        head.isNotEmpty ||
        (grid.first.isNotEmpty &&
            grid.first.every((cell) => cell.localName == 'th'));
    final header = firstIsHeader ? cells.first : <String>[];
    final rows = firstIsHeader ? cells.skip(1) : cells;

    String line(List<String> row) {
      final padded = [...row, ...List.filled(columns - row.length, '')];
      return '| ${padded.join(' | ')} |';
    }

    blocks.add(
      [
        line(header),
        line(List.filled(columns, '---')),
        for (final row in rows) line(row),
      ].join('\n'),
    );
    return blocks;
  }

  /// Las celdas de una fila. Lo que no es una celda sale antes de la tabla.
  List<dom.Element> _cells(dom.Element row, List<dom.Node> fostered) {
    final cells = <dom.Element>[];
    for (final node in row.nodes) {
      if (node is dom.Element &&
          (node.localName == 'td' || node.localName == 'th')) {
        cells.add(node);
      } else if (!_isBlank(node)) {
        fostered.add(node);
      }
    }
    return cells;
  }
}

/// ¿[node] no aporta nada visible? Un comentario, o texto que es solo
/// espacio de formato.
bool _isBlank(dom.Node node) =>
    node is! dom.Element &&
    (node is! dom.Text ||
        node.data.replaceAll(_formattingWhitespace, '') == '');

/// ¿Hay algún bloque adentro de [element]?
bool _containsBlock(dom.Element element) => element.children.any(
  (child) =>
      _blockTags.contains(child.localName) ||
      (!_ignored.contains(child.localName) && _containsBlock(child)),
);

/// Los brackets de [text] se cierran en orden: `[1]` sí, `ver [1` no.
bool _balancedBrackets(String text) {
  var depth = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0x5B) depth++;
    if (unit == 0x5D && --depth < 0) return false;
  }
  return depth == 0;
}

/// Dónde empieza el carácter que ocupa la posición [index] de [text]: un
/// carácter fuera del plano básico —un emoji, una letra rara— ocupa dos.
int _characterStart(String text, int index) {
  final unit = text.codeUnitAt(index);
  final isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
  return isLowSurrogate && index > 0 ? index - 1 : index;
}

/// La primera letra de [node], si es texto; `null` si no se sabe.
String? _firstCharacter(dom.Node? node) {
  if (node is! dom.Text || node.data.isEmpty) return null;
  final data = node.data;
  final unit = data.codeUnitAt(0);
  final isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
  return data.substring(0, isHighSurrogate && data.length > 1 ? 2 : 1);
}

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
