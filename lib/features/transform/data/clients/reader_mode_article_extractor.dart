import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:reader_mode/reader_mode.dart' as reader;
import 'package:sinapsis/features/transform/data/clients/page_urls.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// Lo que una página marca como control suyo y no como parte del artículo:
/// el `[editar]` de cada título de una wiki (MediaWiki, la de Wikipedia).
/// Es la misma marca que descarta la vista de la página archivada
/// (`archived_page_mobile.dart`).
const _pageControls = '.mw-editsection';

/// [ArticleExtractor] sobre `reader_mode`, un port en Dart del algoritmo
/// Readability de Mozilla — el mismo que usa el modo lectura de Firefox.
///
/// Se eligió después de probarlo contra una página armada como las de
/// verdad: navegación, banner de publicidad, barra lateral con "lo más
/// leído", formulario de boletín, comentarios y pie de página alrededor del
/// artículo. Conservó los cuatro párrafos del texto y descartó los cinco
/// bloques de ruido, además de sacar el autor de la metaetiqueta.
///
/// Esa prueba importó porque el paquete es joven y casi sin adopción: su
/// puntaje perfecto en pub.dev mide que esté bien empaquetado —documentado,
/// con tests, sin código obsoleto— y no que funcione con sitios reales. Por
/// eso también queda detrás de [ArticleExtractor]: si falla con alguna clase
/// de páginas, se cambia acá y nada más se entera.
///
/// **Un artículo corto se guarda igual (F22).** Antes, por debajo de 250
/// caracteres se decía que no había artículo, y el transformador lanzaba
/// antes de archivar: de un aviso breve, una nota de dos párrafos o una
/// página de definiciones no quedaba ni el texto ni la página. Ahora todo
/// texto que el algoritmo encuentre se devuelve; `null` queda solo para una
/// página sin una letra.
///
/// **El límite que queda, y que es del algoritmo.** Readability, en un
/// artículo largo, limpia "condicionalmente" tablas, listas y `<div>` que
/// parecen navegación —muchos enlaces, pocas comas, más ítems que
/// párrafos—, y saca el `<h1>` que repite el título (que igual queda como
/// título del elemento). Casi siempre acierta, pero una lista de
/// referencias o una tabla con enlaces puede caer. No se reescribe acá: el
/// paquete no deja apagar esa limpieza, y el resguardo ya existe, porque la
/// página entera queda archivada como el archivo original de la fuente. En
/// un artículo de menos de 500 caracteres, en cambio, el algoritmo vuelve a
/// intentar sin esa limpieza, así que lo corto sale con sus tablas y listas.

class ReaderModeArticleExtractor implements ArticleExtractor {
  const ReaderModeArticleExtractor();

  @override
  ExtractedArticle? extract(String html, {required Uri baseUri}) {
    // `reader_mode` trae dos parsers: `ParserType.jsdom` (el default), un
    // parser de HTML escrito a mano para este paquete, y `ParserType.html`,
    // que delega en `package:html` —el parser HTML5 estándar de Dart, el
    // mismo que ya usa `WebPageAdapter` en el resto del proyecto—. El
    // primero no tolera el HTML real de páginas grandes y con muchos años
    // de historia como Wikipedia: revienta con errores del estilo
    // "expected '</main>' and got '</div>'" apenas encuentra una etiqueta
    // que no cierra exactamente como él espera, y `parse()` devuelve
    // `null` en vez de un artículo. Un parser HTML5 de verdad —que
    // entiende elementos vacíos y cierre implícito de etiquetas, igual que
    // un navegador— no tiene ese problema.
    //
    // **Las direcciones se completan antes de leer (F30).** Con
    // `ParserType.html`, el adaptador del paquete no sabe en qué dirección
    // está la página —devuelve `''` como dirección base—, así que el paso de
    // Readability que vuelve absolutas las direcciones las dejaba como
    // venían: `//upload.wikimedia.org/…` sin esquema, `/wiki/Roma` sin
    // sitio, y un `../img/a.png` hasta perdía su `../`. El Markdown quedaba
    // con imágenes y enlaces que no llevaban a ningún lado. Por eso la página
    // se lee acá, se le completan las direcciones contra la de la página
    // —o la de su `<base href>`, si la declara— y recién entonces se le pasa
    // a Readability, que con direcciones completas no tiene nada que
    // adivinar. Se lee una sola vez: es el mismo parser que el paquete
    // usaría por dentro.
    final document = html_parser.parse(html);
    // **Los controles de la página no son su texto (F46).** El `[editar]`
    // de cada título de una wiki es un enlace que la página marca como
    // control (`.mw-editsection`), y Readability lo conservaba: quedaba un
    // renglón «[editar]» bajo cada capítulo, en el texto y en lo que se
    // escucha. Se sacan antes de leer, por su marca y no por su texto: un
    // `[editar]` escrito en el artículo mismo se queda.
    //
    // Y no es solo un renglón de más: con el control adentro, el `<div>` que
    // envuelve cada título de MediaWiki (`.mw-heading`) tiene más texto de
    // enlace que de título —«[editar código · editar]» al lado de
    // «Etimología»—, y la limpieza condicional de Readability lo descarta
    // como si fuera navegación, con el título adentro. Así se perdían casi
    // todos los capítulos de un artículo de Wikipedia (Fotosíntesis: los 30;
    // Imperio romano: 50 de 57): solo quedaban los títulos largos, que
    // diluían el enlace, con su «[editar]» debajo.
    for (final control in document.querySelectorAll(_pageControls)) {
      control.remove();
    }
    unweightTitleAnchors(document);
    absolutizePageUrls(document, documentBaseUri(document, baseUri));
    final article = reader.Readability(
      reader.HtmlDomDocument(document),
      const reader.ReadabilityOptions(),
    ).parse();
    if (article == null) return null;

    final text = article.textContent.trim();
    if (text.isEmpty) return null;

    final content = article.content.trim();
    if (content.isEmpty) return null;

    return ExtractedArticle(
      contentHtml: content,
      textContent: text,
      title: article.title.trim(),
      byline: article.byline?.trim(),
      siteName: article.siteName?.trim(),
    );
  }
}

/// Saca de cada título de [document] —y de lo que lleva adentro— el `id` que
/// no es más que el ancla de su propio texto (F46, paso 5b).
///
/// **Por qué.** Readability juzga un elemento por las palabras de su `class`
/// y de su `id`: descarta todo `<h1>`/`<h2>` con «peso» negativo
/// (`_cleanHeaders`) y, antes de puntuar, todo elemento cuyo nombre suene a
/// lo que no es artículo (`unlikelyCandidates`). Busca esas palabras como
/// pedazos —«media», «meta», «share», «tags», «social», «extra»…—, porque
/// las piensa para nombres que la página les pone a sus partes:
/// `comments`, `site-footer`, `related-posts`. Pero MediaWiki, y con él los
/// generadores de índices y GitHub, le ponen a cada título de `id` su mismo
/// texto escrito como dirección, para que se lo pueda enlazar:
/// «Alta_Edad_Media_(siglos_V_al_X)», «Dinamismo_interno:_económico,_social,…».
/// Ese `id` es el título otra vez, no un nombre de estructura, y sus
/// palabras son las del artículo: en Edad Media se iban los cinco capítulos
/// que dicen «Media» y los dos subtítulos que dicen «social» (8 de 61).
///
/// **La regla.** Un `id` es el ancla del título cuando, quitados los
/// separadores y los acentos y en minúscula, dice lo mismo que su texto
/// —también en la forma vieja de MediaWiki (`.C3.B3` por «ó»), en la de una
/// dirección (`%C3%B3`) y con el número que se agrega a un título repetido
/// (`Historia_2`)—. Ese `id` se quita antes de leer: el título se juzga como
/// uno sin `id`, que Readability deja siempre. Un `id` que no es el texto
/// (`<h2 id="comments">3 comentarios</h2>`) se queda y sigue pesando, igual
/// que la `class`, que no se toca.
///
/// **El caso dudoso se deja como estaba.** Un título que es justo una de las
/// palabras con que Readability reconoce lo que no es artículo
/// (`<h2 id="comments">Comments</h2>`, «Related», «Share», «Tags») conserva
/// su `id`: su ancla y el nombre de la estructura se escriben igual, y no
/// hay cómo saber cuál es. Un título de varias palabras escrito como ancla
/// es texto.
///
/// Pública solo para probar la regla sola; la usa [ReaderModeArticleExtractor].
void unweightTitleAnchors(dom.Document document) {
  for (final heading in document.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    final title = _anchorKey(heading.text);
    if (title.isEmpty || _structureWord.hasMatch(title)) continue;
    for (final element in [heading, ...heading.querySelectorAll('[id]')]) {
      final id = element.attributes['id'];
      if (id != null && _isAnchorOf(id, title)) element.attributes.remove('id');
    }
  }
}

/// Si [id] es el ancla de un título cuya clave (`_anchorKey`) es [title].
bool _isAnchorOf(String id, String title) {
  for (final form in _decodedForms(id)) {
    if (_anchorKey(form) == title) return true;
    final repeated = _repeatSuffix.firstMatch(form);
    if (repeated != null &&
        _anchorKey(form.substring(0, repeated.start)) == title) {
      return true;
    }
  }
  return false;
}

/// [id] tal cual y, si los tiene, con sus bytes escritos como `%C3%B3` o, a
/// la manera vieja de MediaWiki, como `.C3.B3` vueltos letras.
Iterable<String> _decodedForms(String id) sync* {
  yield id;
  if (id.contains('%')) {
    final decoded = _decodeOrNull(id);
    if (decoded != null) yield decoded;
  }
  if (_legacyByte.hasMatch(id)) {
    final decoded = _decodeOrNull(
      id.replaceAllMapped(_legacyByte, (m) => '%${m[1]}'),
    );
    if (decoded != null) yield decoded;
  }
}

/// [encoded] con sus `%XX` vueltos letras, o `null` si no es una dirección
/// bien escrita: un `%` sin sus dos cifras, o bytes que no son UTF-8.
String? _decodeOrNull(String encoded) {
  if (!_wellEncoded.hasMatch(encoded)) return null;
  try {
    return Uri.decodeComponent(encoded);
  } on FormatException {
    return null;
  }
}

/// Cada `%` con sus dos cifras: lo que `Uri.decodeComponent` sabe leer.
final _wellEncoded = RegExp(r'^(?:[^%]|%[0-9A-Fa-f]{2})*$');

/// Lo que queda de [text] para comparar un título con su ancla: sus letras y
/// sus cifras, en minúscula y sin acentos. Las reglas de ancla de siempre
/// —MediaWiki, GitHub, los índices de WordPress— cambian los espacios por
/// `_` o `-`, quitan o conservan la puntuación y a veces los acentos; las
/// letras y las cifras quedan en todas.
String _anchorKey(String text) {
  final key = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _accentFolds[char] ?? char;
    if (_letterOrDigit.hasMatch(folded)) key.write(folded);
  }
  return key.toString();
}

final _letterOrDigit = RegExp(r'^[\p{L}\p{N}]+$', unicode: true);

/// Un byte escrito a la manera vieja de MediaWiki (`.C3`).
final _legacyByte = RegExp(r'\.([0-9A-F]{2})');

/// El número que se le agrega al ancla de un título repetido.
final _repeatSuffix = RegExp(r'[_-]\d+$');

/// Las palabras con que Readability reconoce lo que no es el artículo —las
/// de su peso negativo y las de `unlikelyCandidates`, sin sus guiones—,
/// solas o en plural: la clave de un título que es solo eso.
final _structureWord = RegExp(
  '^(?:ad|adbreak|agegate|ai2html|banner|breadcrumbs|combx|comment|'
  'community|contact|coverwrap|disqus|extra|footer|gdpr|header|hid|hidden|'
  'legends|masthead|media|menu|meta|outbrain|pager|pagination|popup|promo|'
  'related|remark|replies|rss|scroll|share|shopping|shoutbox|sidebar|'
  r'skyscraper|social|sponsor|supplemental|tags|widget|yomremote)s?$',
);

/// Las letras con acento que se escriben sin él en un ancla.
const _accentFolds = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y', //
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
};
