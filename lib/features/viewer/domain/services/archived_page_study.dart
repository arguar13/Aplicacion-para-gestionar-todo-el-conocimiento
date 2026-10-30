import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_fidelity.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_mobile.dart';

/// Los colores de resaltador, como `0xAARRGGBB`, y la línea del resumen
/// debajo de una oración que también es de la síntesis (F43, paso 15).
typedef ArchivedPageColors = ({
  int summary,
  int synthesis,
  int keyword,
  int summaryLine,
});

/// El canal por el que la página avisa qué palabra se tocó.
const archivedPageChannel = 'SinapsisStudy';

/// El texto extraído de una página web, para estudiar y resaltar sobre ella
/// (F36, F38), y los colores de lo estudiado.
typedef ArchivedPageStudy = ({String content, ArchivedPageColors colors});

/// La copia de la página web archivada [html] que se muestra: con sus fotos
/// listas —ver `showArchivedImages`— y, con [study], lista para estudiar sobre
/// ella (decisión E).
///
/// La copia no lleva nada estudiado adentro (F39): lleva el programa de la
/// app, que lo pinta mientras la página está abierta —ver
/// [archivedPageStudyScript]—, así que elegir a mano una oración o una palabra
/// no vuelve a cargar la página ni la mueve de lugar, y la página queda como
/// el original, sin un `<mark>` por palabra. Dónde va cada cosa lo dice cómo
/// se corresponde el texto de la página con el extraído (ver
/// [ArchivedPageAlignment]), que se cuenta acá.
///
/// Con [study], la página se ve como hasta ahora, que se mostraba con
/// JavaScript apagado: se le sacan sus programas —`<script>`, los atributos
/// `on…`, los enlaces `javascript:`—, lo que estaba en `<noscript>` queda a la
/// vista, y el único programa es el chico de la app. El archivo guardado no
/// se toca: esto es una copia para mostrar.
String showableArchivedPage(String html, {ArchivedPageStudy? study}) =>
    showArchivedPage(html, study: study).html;

/// La copia que se muestra de [html] —ver [showableArchivedPage]— y, con
/// [study], cómo se corresponde su texto con el extraído (F38): de ahí salen
/// los tramos de lo que se selecciona en la página y dónde pintar los
/// resaltados de la persona.
///
/// Con [mobile], además, como en un navegador del teléfono —ver
/// `makeArchivedPageMobile`—: lo de Procesado (F45, paso 4).
({String html, ArchivedPageAlignment? alignment}) showArchivedPage(
  String html, {
  ArchivedPageStudy? study,
  bool mobile = false,
}) {
  final document = html_parser.parse(html);
  showArchivedImages(document);
  restoreScriptState(document);
  if (mobile) makeArchivedPageMobile(document);
  ArchivedPageAlignment? alignment;
  if (study != null) {
    _neutralize(document);
    final body = document.body;
    if (body != null) alignment = _PageCounter(body, study.content).alignment();
    _inject(document, study.colors);
  }
  return (html: document.outerHtml, alignment: alignment);
}

/// Cómo se corresponden el texto de [html] y el extraído [content] (F38),
/// sin armar la copia que se muestra.
ArchivedPageAlignment? alignArchivedPage(String html, String content) =>
    showArchivedPage(
      html,
      study: (
        content: content,
        colors: (summary: 0, synthesis: 0, keyword: 0, summaryLine: 0),
      ),
    ).alignment;

/// El canal por el que la página avisa lo que la persona selecciona en ella y
/// el resaltado suyo que toca (F38): ver [parseArchivedPageEvent].
const archivedPageMarksChannel = 'SinapsisMarks';

/// Un resaltado de la persona listo para pintar en la página (F38): sus
/// `ranges` en el texto corrido de la página —ver [ArchivedPageAlignment]—,
/// el `color` (`0xAARRGGBB`) del fondo o, con `underline`, de la línea de
/// abajo.
typedef ArchivedPageMark = ({
  String id,
  List<PageRange> ranges,
  int color,
  bool underline,
});

/// Lo que se le pide a la página para pintar los resaltados de la persona
/// [marks], de abajo hacia arriba: donde dos se pisan, queda a la vista el
/// último. Reemplaza lo que había.
String archivedPageMarksScript(List<ArchivedPageMark> marks) {
  final items = jsonEncode([
    for (final mark in marks)
      {
        'id': mark.id,
        'ranges': [
          for (final range in mark.ranges) [range.start, range.end],
        ],
        'color': _hex(mark.color),
        'underline': mark.underline,
      },
  ]);
  return 'window.sinapsis && window.sinapsis.marks($items);';
}

/// Lo que la página avisa por [archivedPageMarksChannel] (F38).
sealed class ArchivedPageEvent {
  const ArchivedPageEvent();
}

/// La persona seleccionó `[start, end)` del texto corrido de la página
/// —que se ve como [text]— y la selección está en [bounds], en píxeles de la
/// página (`viewWidth` de ancho): para poner la barra junto a ella.
class ArchivedPageSelected extends ArchivedPageEvent {
  const ArchivedPageSelected({
    required this.start,
    required this.end,
    required this.text,
    required this.bounds,
    required this.viewWidth,
  });

  final int start;
  final int end;
  final String text;
  final ({double left, double top, double right, double bottom}) bounds;
  final double viewWidth;
}

/// Ya no hay nada seleccionado.
class ArchivedPageDeselected extends ArchivedPageEvent {
  const ArchivedPageDeselected();
}

/// La persona tocó el resaltado suyo [id].
class ArchivedPageMarkTapped extends ArchivedPageEvent {
  const ArchivedPageMarkTapped(this.id);

  final String id;
}

/// La persona empezó a mover la página con el dedo —o la rueda del ratón—:
/// un visor que seguía lo que se lee en voz alta la deja tranquila.
class ArchivedPageMoved extends ArchivedPageEvent {
  const ArchivedPageMoved();
}

/// Lo que se lee en voz alta entró solo en la parte cómoda de lo que se ve
/// (ver [archivedPageReadingScript], con `report`).
class ArchivedPageReadingSeen extends ArchivedPageEvent {
  const ArchivedPageReadingSeen();
}

/// La persona dejó la página quieta, y lo primero que se ve arriba está en
/// [position] del texto corrido de la página: por dónde va la vista.
class ArchivedPageViewed extends ArchivedPageEvent {
  const ArchivedPageViewed(this.position);

  final int position;
}

/// [message], lo que llegó por [archivedPageMarksChannel], o `null` si no es
/// algo que se entienda.
ArchivedPageEvent? parseArchivedPageEvent(String message) {
  try {
    final data = jsonDecode(message);
    if (data is! Map<String, dynamic>) return null;
    switch (data['t']) {
      case 'sel':
        if (data['empty'] == true) return const ArchivedPageDeselected();
        final rect = (data['rect'] as List<dynamic>).cast<num>();
        return ArchivedPageSelected(
          start: data['a'] as int,
          end: data['b'] as int,
          text: data['text'] as String,
          bounds: (
            left: rect[0].toDouble(),
            top: rect[1].toDouble(),
            right: rect[2].toDouble(),
            bottom: rect[3].toDouble(),
          ),
          viewWidth: (data['vw'] as num).toDouble(),
        );
      case 'tap':
        return ArchivedPageMarkTapped(data['id'] as String);
      case 'moved':
        return const ArchivedPageMoved();
      case 'seen':
        return const ArchivedPageReadingSeen();
      case 'view':
        return ArchivedPageViewed(data['at'] as int);
    }
    return null;
    // Lo que manda una página es lo que dice el programa de la app, pero un
    // mensaje mal armado no tiene por qué tirar nada abajo.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// Lo que se le pide a la página para mostrar lo que se eligió: si se ven
/// el resumen ([summary]), la síntesis ([synthesis]) —juntos, la síntesis
/// encima (F39)— y las palabras clave ([keywords]), y si tocar la página
/// elige ([picking]). Solo cambia clases: lo pintado ya está (ver
/// [archivedPageStudyScript]).
String archivedPageStateScript({
  required bool summary,
  required bool synthesis,
  required bool keywords,
  required bool picking,
}) {
  final state = jsonEncode({
    'summary': summary,
    'synthesis': synthesis,
    'keywords': keywords,
    'picking': picking,
  });
  return 'window.sinapsis && window.sinapsis.set($state);';
}

/// Lo que se le pide a la página para pintar lo estudiado [marks] (F39): de
/// cada oración del resumen y de la síntesis y de cada palabra clave, sus
/// tramos en el texto corrido de la página —ver
/// [ArchivedPageAlignment.pageRangesOf]—. Se pinta todo, y lo que se ve lo
/// deciden las clases de [archivedPageStateScript]: prender o apagar no
/// vuelve a pintar nada.
///
/// Una oración se ubica letra a letra, así que la que en la página tiene una
/// nota al pie en el medio se pinta igual, en dos tramos; lo que la página no
/// tiene no se pinta. Reemplaza lo pintado antes.
String archivedPageStudyScript(
  ArchivedPageAlignment alignment,
  Iterable<StudyMark> marks,
) {
  final layers = {
    for (final kind in StudyMarkKind.values) kind.name: <List<int>>[],
  };
  for (final mark in marks) {
    for (final range in alignment.pageRangesOf(mark.start, mark.end)) {
      layers[mark.kind.name]!.add([range.start, range.end]);
    }
  }
  return 'window.sinapsis && window.sinapsis.study(${jsonEncode(layers)});';
}

/// Lo que se le pide a la página para pintar lo que se lee en voz alta: sus
/// [ranges] en el texto corrido de la página —ver
/// [ArchivedPageAlignment.pageRangesOf]—, ninguno si no se lee nada de ella,
/// en [color] (`0xAARRGGBB`), por encima de todo lo demás.
///
/// Con [follow], si lo que suena salió de la parte cómoda de lo que se ve —la
/// franja entre [bandTop] y [bandBottom], fracciones del alto—, la página se
/// desplaza para dejarlo a la altura de [landing]: con [smooth], de a poco;
/// sin él, de un salto (la persona apagó las animaciones). Con [report] y sin
/// [follow], la página avisa si lo que suena llegó solo a esa franja
/// ([ArchivedPageReadingSeen]), y además avisa cuando la persona la mueve
/// ([ArchivedPageMoved]) y por dónde va la vista cuando la deja quieta
/// ([ArchivedPageViewed]).
///
/// No toca lo pintado: lo que suena va en una capa aparte —un resaltado del
/// navegador, sin cambiar la página—, así que pasar de una línea a la otra no
/// vuelve a envolver nada.
String archivedPageReadingScript(
  List<PageRange> ranges, {
  required int color,
  required bool follow,
  required bool report,
  required bool smooth,
  required double bandTop,
  required double bandBottom,
  required double landing,
}) {
  final reading = jsonEncode({
    'ranges': [
      for (final range in ranges) [range.start, range.end],
    ],
    'color': _hex(color),
    'follow': follow,
    'report': report,
    'smooth': smooth,
    'top': bandTop,
    'bottom': bandBottom,
    'landing': landing,
  });
  return 'window.sinapsis && window.sinapsis.reading($reading);';
}

/// La posición en el texto extraído de lo que se tocó en la página (F39):
/// [message] es la posición en el texto corrido de la página que manda su
/// programa por [archivedPageChannel]. `null` si no se entiende o si lo
/// tocado no es del artículo —el menú, una etiqueta—.
int? archivedPageTappedOffset(ArchivedPageAlignment alignment, String message) {
  final position = int.tryParse(message);
  return position == null ? null : alignment.contentOffsetAt(position);
}

/// Lo que no se recorre buscando texto: no es texto que se lea, o no admite
/// un `<mark>` adentro.
const _opaque = {
  'script',
  'style',
  'noscript',
  'template',
  'textarea',
  'select',
  'option',
  'title',
  'svg',
  'math',
};

/// Un enlace de Markdown: la dirección no está en la página, solo el texto.
/// Una imagen entera tampoco —su texto alternativo es un atributo—.
final _markdownUrls = RegExp(r'!\[[^\]]*\]\([^)]*\)|\]\([^)]*\)');

/// Cuenta los textos de la página y los del extraído, letra a letra, para ver
/// cómo se corresponden: ver [alignment].
class _PageCounter {
  _PageCounter(Element body, this.content) {
    _collect(body);
    _buildPage();
    _buildContent();
  }

  final String content;

  final _texts = <Text>[];

  /// Las letras y números de la página, plegados, y de qué texto y en qué
  /// lugar de él sale cada uno.
  late final String _page;
  final _pageNode = <int>[];
  final _pageOffset = <int>[];

  /// Dónde empieza cada texto en el texto corrido de la página, que es
  /// todos juntos: ver [ArchivedPageAlignment].
  final _textStart = <int>[];
  late final String _pageText;

  /// Lo mismo del texto extraído: cada letra y su posición en [content].
  late final String _content;
  final _contentAt = <int>[];

  void _collect(Node node) {
    for (final child in node.nodes) {
      if (child is Text) {
        _texts.add(child);
      } else if (child is Element && !_opaque.contains(child.localName)) {
        _collect(child);
      }
    }
  }

  void _buildPage() {
    final page = StringBuffer();
    final pageText = StringBuffer();
    for (var n = 0; n < _texts.length; n++) {
      final data = _texts[n].data;
      _textStart.add(pageText.length);
      pageText.write(data);
      for (var i = 0; i < data.length; i++) {
        final folded = foldWordChar(data.codeUnitAt(i));
        if (folded == null) continue;
        for (var k = 0; k < folded.length; k++) {
          page.write(folded[k]);
          _pageNode.add(n);
          _pageOffset.add(i);
        }
      }
    }
    _page = page.toString();
    _pageText = pageText.toString();
  }

  void _buildContent() {
    final skipped = _markdownUrls
        .allMatches(content)
        .map(
          (m) => m.group(0)!.startsWith('!')
              ? (start: m.start, end: m.end)
              : (start: m.start + 1, end: m.end),
        );
    final skip = skipped.iterator;
    var hasSkip = skip.moveNext();
    final buffer = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      while (hasSkip && skip.current.end <= i) {
        hasSkip = skip.moveNext();
      }
      if (hasSkip && i >= skip.current.start) continue;
      final folded = foldWordChar(content.codeUnitAt(i));
      if (folded == null) continue;
      for (var k = 0; k < folded.length; k++) {
        buffer.write(folded[k]);
        _contentAt.add(i);
      }
    }
    _content = buffer.toString();
  }

  /// Cuántas letras tiene que tener un pedazo del extraído para buscarlo en la
  /// página, desde cuántas deja de ser "corto" —uno corto está en cualquier
  /// parte, y solo vale pegado a lo anterior— y cuánto puede haber entre un
  /// pedazo y el que sigue.
  static const _minPiece = 8;
  static const _shortPiece = 30;
  static const _shortGap = 300;
  static const _skip = 4;

  /// Cómo se corresponde letra a letra el texto de la página con el extraído
  /// (F38): ver [ArchivedPageAlignment].
  ///
  /// Se buscan en la página los renglones del extraído, en orden, cada uno
  /// desde donde terminó el anterior. Uno que no está entero —tiene una nota
  /// al pie que la página no tiene, o al revés— se encuentra por pedazos: el
  /// más largo con que empieza, y así con lo que sigue. Los renglones cortos
  /// —un título— están en cualquier parte, y se buscan al final, solo entre
  /// los largos que los rodean.
  ArchivedPageAlignment alignment() {
    final pageToContent = Int32List(_page.length)
      ..fillRange(0, _page.length, -1);
    final contentToPage = Int32List(_content.length)
      ..fillRange(0, _content.length, -1);
    var cursor = 0;

    /// El primer lugar de [needle] en la página, desde [from] y terminando
    /// antes de [limit], que no esté ocupado.
    int find(String needle, int from, int limit) {
      var at = _page.indexOf(needle, from);
      while (at >= 0) {
        if (at + needle.length > limit) return -1;
        var taken = false;
        for (var k = 0; k < needle.length && !taken; k++) {
          taken = pageToContent[at + k] >= 0;
        }
        if (!taken) return at;
        at = _page.indexOf(needle, at + 1);
      }
      return -1;
    }

    void put(int from, int length, int at) {
      for (var k = 0; k < length; k++) {
        pageToContent[at + k] = from + k;
        contentToPage[from + k] = at + k;
      }
    }

    /// Dónde está en la página `[from, from + length)` del extraído, o -1.
    int search(int from, int length) {
      final needle = _content.substring(from, from + length);
      var at = find(needle, cursor, _page.length);
      if (length < _shortPiece) {
        return at >= 0 && at - cursor <= _shortGap ? at : -1;
      }
      // El extraído no siempre sigue el orden de la página.
      if (at < 0) at = find(needle, 0, _page.length);
      return at;
    }

    /// Ubica `[from, to)` del extraído en la página, por pedazos.
    void place(int from, int to) {
      var position = from;
      while (to - position >= _minPiece) {
        var length = to - position;
        var at = search(position, length);
        if (at < 0) {
          // El pedazo más largo con que empieza: lo que se encuentra a un
          // largo se encuentra a uno menor.
          var low = _minPiece;
          var high = length - 1;
          length = 0;
          while (low <= high) {
            final middle = (low + high) >> 1;
            final found = search(position, middle);
            if (found >= 0) {
              length = middle;
              at = found;
              low = middle + 1;
            } else {
              high = middle - 1;
            }
          }
          if (length == 0) {
            // Nada empieza acá: se sigue unas letras más adelante, no de a
            // una —un párrafo que no está en la página sería interminable—.
            position += _skip;
            continue;
          }
        }
        put(position, length, at);
        cursor = max(cursor, at + length);
        position += length;
      }
    }

    final shorts = <PageRange>[];
    var lineStart = 0;
    while (lineStart <= content.length) {
      var lineEnd = content.indexOf('\n', lineStart);
      if (lineEnd < 0) lineEnd = content.length;
      final from = _lowerBound(lineStart);
      final to = _lowerBound(lineEnd);
      if (to - from < _shortPiece) {
        if (to - from >= _minPiece) shorts.add((start: from, end: to));
      } else {
        place(from, to);
      }
      lineStart = lineEnd + 1;
    }

    for (final piece in shorts) {
      // Entre lo que ya se ubicó antes y lo que se ubicó después.
      var before = piece.start - 1;
      while (before >= 0 && contentToPage[before] < 0) {
        before--;
      }
      var after = piece.end;
      while (after < _content.length && contentToPage[after] < 0) {
        after++;
      }
      final needle = _content.substring(piece.start, piece.end);
      final from = before < 0 ? 0 : contentToPage[before] + 1;
      final limit = after >= _content.length
          ? _page.length
          : contentToPage[after];
      var at = find(needle, from, limit);
      if (at < 0) {
        // Si el extraído está en otro orden, vale el único lugar que tiene.
        at = find(needle, 0, _page.length);
        if (at >= 0 && find(needle, at + 1, _page.length) >= 0) at = -1;
      }
      if (at >= 0) put(piece.start, needle.length, at);
    }

    return ArchivedPageAlignment(
      content: content,
      pageText: _pageText,
      letterPosition: Int32List.fromList([
        for (var j = 0; j < _page.length; j++)
          _textStart[_pageNode[j]] + _pageOffset[j],
      ]),
      pageToContent: pageToContent,
      contentToPage: contentToPage,
      contentPosition: Int32List.fromList(_contentAt),
    );
  }

  /// La primera letra del texto extraído que está en [offset] o después.
  int _lowerBound(int offset) {
    var low = 0;
    var high = _contentAt.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_contentAt[mid] < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

void _neutralize(Document document) {
  for (final script in document.querySelectorAll('script')) {
    script.remove();
  }
  // Con JavaScript apagado se veía lo de `<noscript>` —muchas veces, las
  // fotos de verdad de una página que las carga con un programa—: queda.
  for (final noscript in document.querySelectorAll('noscript')) {
    final parent = noscript.parentNode;
    if (parent == null) continue;
    final children = noscript.nodes.length == 1 && noscript.nodes.single is Text
        ? html_parser.parseFragment((noscript.nodes.single as Text).data).nodes
        : noscript.nodes;
    final moved = children.toList();
    final index = parent.nodes.indexOf(noscript);
    noscript.remove();
    parent.nodes.insertAll(index, moved);
  }
  for (final meta in document.querySelectorAll('meta')) {
    final httpEquiv = meta.attributes['http-equiv']?.trim().toLowerCase();
    if (httpEquiv == 'refresh' || httpEquiv == 'content-security-policy') {
      meta.remove();
    }
  }
  for (final element in document.querySelectorAll('*')) {
    final attributes = element.attributes;
    for (final name in attributes.keys.toList()) {
      final key = '$name'.toLowerCase();
      final value = attributes[name]?.trim().toLowerCase() ?? '';
      if (key.startsWith('on') || value.startsWith('javascript:')) {
        attributes.remove(name);
      }
    }
  }
}

void _inject(Document document, ArchivedPageColors colors) {
  final head = document.head;
  final style = Element.tag('style')
    ..attributes['id'] = 'sinapsis-study'
    ..append(Text(_css(colors)));
  if (head != null) head.append(style);
  document.body?.append(
    Element.tag('script')
      ..attributes['id'] = 'sinapsis-study-script'
      ..append(Text(_script)),
  );
}

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _css(ArchivedPageColors colors) {
  String paint(int color, {bool bold = false}) {
    final weight = bold ? 'font-weight:bold!important;' : '';
    return '{background:${_hex(color)}!important;color:#000!important;'
        '$weight}';
  }

  // Una oración que está en el resumen y en la síntesis, con los dos a la
  // vista: la marca de la síntesis queda adentro de la del resumen.
  const both =
      'html.sn-l-summary.sn-l-synthesis mark.sn-summary mark.sn-synthesis';
  final line = _hex(colors.summaryLine);
  return [
    // Sin nada de lo que la página le ponga a `mark` —margen, borde, peso,
    // `display`—: envolver una palabra no puede mover ni una letra (F39).
    'mark.sn-m{all:unset}',
    // Lo de adentro se ve encima (ver `repaint` en el programa): la síntesis
    // sobre el resumen, los resaltados a mano (F38) sobre las dos, y una
    // palabra clave que se ve sobre todo. Un subrayado es una línea debajo de
    // las letras: no tapa nada.
    'html.sn-l-summary mark.sn-summary${paint(colors.summary)}',
    'html.sn-l-synthesis mark.sn-synthesis${paint(colors.synthesis)}',
    // Una oración del resumen y de la síntesis a la vez: celeste, con la
    // línea verde del resumen debajo —las dos a la vista— (F43, paso 15).
    // También bajo sus palabras clave y lo resaltado a mano que caiga ahí.
    '$both,$both mark{box-shadow:inset 0 -0.2em 0 $line!important}',
    '.sn-hf{color:#000!important}',
    // Las palabras clave, todas, estén o no en una oración resaltada (F39).
    'html.sn-kw mark.sn-k${paint(colors.keyword, bold: true)}',
  ].join('\n');
}

/// El programa de la app en la página: pinta lo estudiado y los resaltados de
/// la persona, cambia las clases que prenden cada color, avisa lo que se
/// selecciona y, eligiendo a mano, la posición de lo que se toca.
const _script = r'''
(function () {
  var root = document.documentElement;
  var picking = false;

  // Los textos de la página, en el orden del documento y sin lo que no se lee:
  // lo mismo que cuenta la app (ver ArchivedPageAlignment).
  var OPAQUE = {script: 1, style: 1, noscript: 1, template: 1, textarea: 1,
    select: 1, option: 1, title: 1, svg: 1, math: 1};
  function textNodes() {
    var out = [];
    (function walk(node) {
      for (var child = node.firstChild; child; child = child.nextSibling) {
        if (child.nodeType === 3) out.push(child);
        else if (child.nodeType === 1 && !OPAQUE[child.localName]) walk(child);
      }
    })(document.body);
    return out;
  }
  function post(message) {
    if (window.SinapsisMarks) window.SinapsisMarks.postMessage(JSON.stringify(message));
  }

  // Cuántas letras hay en la página antes de un punto de la selección.
  function position(texts, container, offset) {
    var count = 0;
    var point = null;
    if (container.nodeType !== 3) {
      point = document.createRange();
      point.setStart(container, offset);
      point.collapse(true);
    }
    for (var i = 0; i < texts.length; i++) {
      var text = texts[i];
      if (text === container) return count + offset;
      var before = point
        ? point.comparePoint(text, text.data.length) < 0
        : !!(container.compareDocumentPosition(text) & Node.DOCUMENT_POSITION_PRECEDING);
      if (!before) return count;
      count += text.data.length;
    }
    return count;
  }

  function report() {
    var selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      post({t: 'sel', empty: true});
      return;
    }
    var range = selection.getRangeAt(0);
    var texts = textNodes();
    var box = range.getBoundingClientRect();
    post({
      t: 'sel',
      a: position(texts, range.startContainer, range.startOffset),
      b: position(texts, range.endContainer, range.endOffset),
      text: selection.toString(),
      rect: [box.left, box.top, box.right, box.bottom],
      vw: window.innerWidth
    });
  }
  var reportTimer = null;
  document.addEventListener('selectionchange', function () {
    clearTimeout(reportTimer);
    reportTimer = setTimeout(report, 180);
  });

  // Lo que pinta la app, adentro del texto: las oraciones del resumen y de la
  // síntesis, los resaltados de la persona y las palabras clave. Todo lleva
  // sn-p, para sacarlo y volver a pintar.
  var study = {summary: [], synthesis: [], keyword: []};
  var hand = [];

  function unwrap() {
    var painted = document.querySelectorAll('.sn-p');
    for (var i = painted.length - 1; i >= 0; i--) {
      var element = painted[i];
      var parent = element.parentNode;
      if (!parent) continue;
      while (element.firstChild) parent.insertBefore(element.firstChild, element);
      parent.removeChild(element);
    }
    document.body.normalize();
  }
  function markOf(kind) {
    return function () {
      var mark = document.createElement('mark');
      mark.className = 'sn-p sn-m sn-' + kind;
      return mark;
    };
  }
  function spanOf(item) {
    var span = document.createElement('span');
    span.className = 'sn-p sn-h ' + (item.underline ? 'sn-hu' : 'sn-hf');
    span.setAttribute('data-h', item.id);
    if (item.underline) {
      span.style.cssText = 'text-decoration:underline;text-decoration-color:' +
        item.color + ';text-decoration-thickness:2px;text-underline-offset:2px';
    } else {
      span.style.background = item.color;
    }
    return span;
  }
  function wrapText(node, parts, make) {
    var data = node.data;
    var cuts = [0, data.length];
    parts.forEach(function (part) { cuts.push(part.from, part.to); });
    cuts = cuts.sort(function (a, b) { return a - b; })
      .filter(function (cut, i, all) { return i === 0 || cut !== all[i - 1]; });
    var fragment = document.createDocumentFragment();
    for (var i = 0; i + 1 < cuts.length; i++) {
      var from = cuts[i];
      var to = cuts[i + 1];
      var covering = parts
        .filter(function (part) { return part.from <= from && part.to >= to; })
        .map(function (part) { return part.k; })
        .sort(function (a, b) { return a - b; });
      var top = document.createTextNode(data.substring(from, to));
      // El último de la lista, el de arriba, queda pegado al texto.
      for (var c = covering.length - 1; c >= 0; c--) {
        var element = make(covering[c]);
        element.appendChild(top);
        top = element;
      }
      fragment.appendChild(top);
    }
    node.parentNode.replaceChild(fragment, node);
  }
  // Envuelve con make(k) cada tramo [a, b) del texto corrido de la página de
  // [ranges], cada uno con su k.
  function paint(ranges, make) {
    if (!ranges.length) return;
    var texts = textNodes();
    var starts = [];
    var total = 0;
    for (var i = 0; i < texts.length; i++) {
      starts.push(total);
      total += texts[i].data.length;
    }
    var perNode = {};
    ranges.forEach(function (item) {
      var range = item.range;
      var low = 0;
      var high = texts.length;
      while (low < high) {
        var mid = (low + high) >> 1;
        if (starts[mid] + texts[mid].data.length <= range[0]) low = mid + 1;
        else high = mid;
      }
      for (var n = low; n < texts.length && starts[n] < range[1]; n++) {
        var from = Math.max(range[0], starts[n]) - starts[n];
        var to = Math.min(range[1], starts[n] + texts[n].data.length) - starts[n];
        // Un texto de solo espacios queda como está: entre las filas de una
        // tabla o los ítems de una lista, envolverlo movería cosas.
        if (to > from && /\S/.test(texts[n].data)) {
          (perNode[n] = perNode[n] || []).push({from: from, to: to, k: item.k});
        }
      }
    });
    Object.keys(perNode).forEach(function (n) {
      wrapText(texts[n], perNode[n], make);
    });
  }
  function each(ranges) {
    return ranges.map(function (range) { return {range: range, k: 0}; });
  }

  // Lo que se lee en voz alta: una capa aparte, por encima de todo. Donde el
  // navegador sabe resaltar sin tocar la página (CSS Custom Highlight), así;
  // si no, envolviendo cada tramo en una marca, la de más adentro.
  var reading = {ranges: [], report: false};
  var highlights = !!(window.CSS && CSS.highlights && window.Highlight);
  var readingColor = null;

  function setReadingColor(color) {
    if (color === readingColor) return;
    readingColor = color;
    var style = document.getElementById('sn-reading-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'sn-reading-style';
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent =
      '::highlight(sn-reading){background-color:' + color + ';color:#000}' +
      'mark.sn-r{background:' + color + '!important;color:#000!important}';
  }
  // Los tramos [a, b) del texto corrido de la página, como rangos del DOM.
  function domRanges(ranges) {
    var texts = textNodes();
    var starts = [];
    var total = 0;
    for (var i = 0; i < texts.length; i++) {
      starts.push(total);
      total += texts[i].data.length;
    }
    function at(position, end) {
      var low = 0;
      var high = texts.length - 1;
      while (low < high) {
        var mid = (low + high + 1) >> 1;
        if (starts[mid] < position || (!end && starts[mid] === position)) low = mid;
        else high = mid - 1;
      }
      var node = texts[low];
      if (!node) return null;
      return {node: node, offset: Math.max(0, Math.min(position - starts[low], node.data.length))};
    }
    var out = [];
    ranges.forEach(function (range) {
      var a = at(range[0], false);
      var b = at(range[1], true);
      if (!a || !b) return;
      var dom = document.createRange();
      dom.setStart(a.node, a.offset);
      dom.setEnd(b.node, b.offset);
      if (!dom.collapsed) out.push(dom);
    });
    return out;
  }
  function unwrapReading() {
    var painted = document.querySelectorAll('mark.sn-r');
    for (var i = painted.length - 1; i >= 0; i--) {
      var element = painted[i];
      var parent = element.parentNode;
      if (!parent) continue;
      while (element.firstChild) parent.insertBefore(element.firstChild, element);
      parent.removeChild(element);
      parent.normalize();
    }
  }
  // Pinta lo que suena y devuelve sus rangos del DOM.
  function paintReading() {
    if (highlights) {
      var found = domRanges(reading.ranges);
      if (found.length) {
        var highlight = new Highlight();
        found.forEach(function (range) { highlight.add(range); });
        CSS.highlights.set('sn-reading', highlight);
      } else {
        CSS.highlights.delete('sn-reading');
      }
      return found;
    }
    unwrapReading();
    paint(each(reading.ranges), markOf('r'));
    return domRanges(reading.ranges);
  }
  // Lo que se ve de la página: el visor visual, con zoom incluido.
  function viewBox() {
    var view = window.visualViewport;
    return view
      ? {top: view.offsetTop, height: view.height}
      : {top: 0, height: window.innerHeight};
  }
  function followReading(found) {
    if (!found.length) return;
    var box = found[0].getBoundingClientRect();
    if (!box.width && !box.height) return;
    var view = viewBox();
    var comfortable = box.top >= view.top + view.height * reading.top &&
      box.bottom <= view.top + view.height * reading.bottom;
    if (reading.follow) {
      if (comfortable) return;
      window.scrollBy({
        top: box.top - (view.top + view.height * reading.landing),
        left: 0,
        behavior: reading.smooth ? 'smooth' : 'auto'
      });
    } else if (reading.report && comfortable) {
      post({t: 'seen'});
    }
  }
  // Por dónde va la vista: la letra que está arriba, a la izquierda de lo
  // que se ve.
  function reportView() {
    if (!reading.report) return;
    var view = viewBox();
    var y = view.top + view.height * 0.1;
    for (var x = 24; x < window.innerWidth; x += 48) {
      var caret = caretAt(x, y);
      if (caret) {
        post({t: 'view', at: position(textNodes(), caret.node, caret.offset)});
        return;
      }
    }
  }
  // La persona mueve la página: se avisa una vez por gesto.
  var touching = false;
  var wheeling = null;
  function moved() {
    if (reading.report) post({t: 'moved'});
  }
  document.addEventListener('touchstart', function () { touching = true; }, {passive: true});
  document.addEventListener('touchmove', function () {
    if (!touching) return;
    touching = false;
    moved();
  }, {passive: true});
  window.addEventListener('wheel', function () {
    if (!wheeling) moved();
    clearTimeout(wheeling);
    wheeling = setTimeout(function () { wheeling = null; }, 400);
  }, {passive: true});
  var viewTimer = null;
  window.addEventListener('scroll', function () {
    clearTimeout(viewTimer);
    viewTimer = setTimeout(reportView, 250);
  }, {passive: true});
  // De afuera hacia adentro, y lo de adentro se ve encima: el resumen, la
  // síntesis, los resaltados de la persona —el último de la lista, arriba—
  // y las palabras clave.
  function repaint() {
    unwrap();
    paint(each(study.summary), markOf('summary'));
    paint(each(study.synthesis), markOf('synthesis'));
    var marked = [];
    hand.forEach(function (item, k) {
      item.ranges.forEach(function (range) { marked.push({range: range, k: k}); });
    });
    paint(marked, function (k) { return spanOf(hand[k]); });
    paint(each(study.keyword), markOf('k'));
    // Lo que suena va encima de todo; envuelto en una marca, se lo llevó
    // unwrap.
    paintReading();
  }

  // Dónde cae el cursor en (x, y): el texto y el lugar en él.
  function caretAt(x, y) {
    if (document.caretRangeFromPoint) {
      var range = document.caretRangeFromPoint(x, y);
      if (range && range.startContainer.nodeType === 3) {
        return {node: range.startContainer, offset: range.startOffset};
      }
    } else if (document.caretPositionFromPoint) {
      var caret = document.caretPositionFromPoint(x, y);
      if (caret && caret.offsetNode.nodeType === 3) {
        return {node: caret.offsetNode, offset: caret.offset};
      }
    }
    return null;
  }

  window.sinapsis = {
    marks: function (items) {
      hand = items || [];
      repaint();
    },
    study: function (layers) {
      study = {
        summary: layers.summary || [],
        synthesis: layers.synthesis || [],
        keyword: layers.keyword || []
      };
      repaint();
    },
    reading: function (state) {
      reading = {
        ranges: state.ranges || [],
        follow: !!state.follow,
        report: !!state.report,
        smooth: !!state.smooth,
        top: state.top,
        bottom: state.bottom,
        landing: state.landing
      };
      setReadingColor(state.color);
      followReading(paintReading());
      if (reading.report && !reading.ranges.length) reportView();
    },
    clearSelection: function () {
      var selection = window.getSelection();
      if (selection) selection.removeAllRanges();
    },
    selectAll: function () {
      var selection = window.getSelection();
      if (!selection) return;
      var range = document.createRange();
      range.selectNodeContents(document.body);
      selection.removeAllRanges();
      selection.addRange(range);
    },
    set: function (state) {
      root.classList.toggle('sn-l-summary', !!state.summary);
      root.classList.toggle('sn-l-synthesis', !!state.synthesis);
      root.classList.toggle('sn-kw', !!state.keywords);
      root.classList.toggle('sn-pick', !!state.picking);
      picking = !!state.picking;
    }
  };
  // Eligiendo a mano, cualquier palabra se toca (F39): se avisa la posición
  // del cursor en el texto corrido de la página, y la app la ubica en el
  // texto extraído. Un enlace no se sigue.
  document.addEventListener('click', function (event) {
    if (!picking) return;
    var caret = caretAt(event.clientX, event.clientY);
    if (!caret) return;
    event.preventDefault();
    event.stopPropagation();
    var at = position(textNodes(), caret.node, caret.offset);
    if (window.SinapsisStudy) window.SinapsisStudy.postMessage(String(at));
  }, true);
  // Tocar un resaltado de la persona avisa cuál, salvo que se esté
  // seleccionando o sea un enlace.
  document.addEventListener('click', function (event) {
    var selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    var node = event.target;
    while (node && node.nodeType === 1) {
      if (node.localName === 'a') return;
      if (node.classList.contains('sn-h')) {
        post({t: 'tap', id: node.getAttribute('data-h')});
        return;
      }
      node = node.parentNode;
    }
  });
})();
''';
