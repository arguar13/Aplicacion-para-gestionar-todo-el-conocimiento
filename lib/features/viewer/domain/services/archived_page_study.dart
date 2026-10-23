import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_fidelity.dart';

/// Una oración marcada para estudiar (F36): su tramo del texto extraído y si
/// es del resumen o de la síntesis.
typedef ArchivedPageSentence = ({int start, int end, StudyMarkKind kind});

/// Los colores de resaltador, como `0xAARRGGBB`.
typedef ArchivedPageColors = ({int summary, int synthesis, int keyword});

/// El canal por el que la página avisa qué palabra se tocó.
const archivedPageChannel = 'SinapsisStudy';

/// Lo estudiado del texto extraído de una página web, para mostrarlo sobre
/// ella (F36): el texto, sus oraciones marcadas y los colores.
typedef ArchivedPageStudy = ({
  String content,
  List<ArchivedPageSentence> sentences,
  ArchivedPageColors colors,
});

/// La copia de la página web archivada [html] que se muestra: con sus fotos
/// listas —ver `showArchivedImages`— y, con [study], lo estudiado listo para
/// verse (decisión E).
///
/// Cada oración se ubica en la página comparando solo letras y números, sin
/// mayúsculas ni acentos: el texto extraído es el artículo en Markdown y la
/// página tiene además su menú, sus etiquetas y sus espacios. Una oración que
/// no está en la página se saltea. Lo encontrado se envuelve en `<mark>` con
/// la clase de su oración y, cada palabra, con su posición en el texto
/// (`data-o`): desde la app se prende el resumen o la síntesis y se marcan las
/// palabras clave cambiando clases, sin volver a cargar la página (ver
/// [archivedPageStateScript]), y tocar una palabra devuelve su posición.
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
({String html, ArchivedPageAlignment? alignment}) showArchivedPage(
  String html, {
  ArchivedPageStudy? study,
}) {
  final document = html_parser.parse(html);
  showArchivedImages(document);
  restoreScriptState(document);
  ArchivedPageAlignment? alignment;
  if (study != null) {
    _neutralize(document);
    final body = document.body;
    if (body != null) {
      final marker = _PageMarker(body, study.content);
      alignment = marker.alignment();
      marker.mark(study.sentences);
    }
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
        sentences: const [],
        colors: (summary: 0, synthesis: 0, keyword: 0),
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
/// encima (F39)— y las palabras clave [keywords] —las que empiezan en
/// [keywordOffsets]—, y si tocar una palabra la elige ([picking]).
String archivedPageStateScript({
  required bool summary,
  required bool synthesis,
  required bool keywords,
  required bool picking,
  required Iterable<int> keywordOffsets,
}) {
  final state = jsonEncode({
    'summary': summary,
    'synthesis': synthesis,
    'keywords': keywords,
    'picking': picking,
    'kw': keywordOffsets.toList(),
  });
  return 'window.sinapsis && window.sinapsis.set($state);';
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

class _PageMarker {
  _PageMarker(Element body, this.content) {
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

  /// Por texto de la página, de cada letra: de qué oraciones es (1 resumen,
  /// 2 síntesis) y de qué palabra (su posición en [content], o -1).
  final _kinds = <int, List<int>>{};
  final _words = <int, List<int>>{};

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
  /// (F38): ver [ArchivedPageAlignment]. Va antes de [mark], que parte los
  /// textos en pedazos.
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

  void mark(List<ArchivedPageSentence> sentences) {
    // Una oración que es del resumen y de la síntesis se ubica una vez.
    final bits = <(int, int), int>{};
    for (final s in sentences) {
      final bit = s.kind == StudyMarkKind.synthesis ? 2 : 1;
      bits.update((s.start, s.end), (b) => b | bit, ifAbsent: () => bit);
    }
    final ordered = bits.keys.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = 0;
    for (final range in ordered) {
      final sentence = (start: range.$1, end: range.$2);
      final from = _lowerBound(sentence.start);
      final to = _lowerBound(sentence.end);
      if (to <= from) continue;
      final needle = _content.substring(from, to);
      var at = _page.indexOf(needle, cursor);
      if (at < 0) at = _page.indexOf(needle);
      if (at < 0) continue;
      cursor = at + needle.length;

      final bit = bits[range]!;
      _fill(
        at,
        at + needle.length,
        (n, i) => _kindsOf(n)[i] |= bit,
        withClosing: true,
      );
      for (final word in studyWordsIn(content, sentence.start, sentence.end)) {
        final first = _lowerBound(word.start) - from + at;
        final last = _lowerBound(word.end) - from + at;
        if (last <= first) continue;
        _fill(first, last, (n, i) => _wordsOf(n)[i] = word.start);
      }
    }
    for (final n in {..._kinds.keys, ..._words.keys}) {
      _rebuild(n);
    }
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

  /// Recorre los lugares de la página de la letra [first] hasta antes de
  /// [last], con lo que hay entre medio —espacios, signos—. Con
  /// [withClosing], también los signos que cierran la oración pegados a su
  /// última letra: el punto, las comillas.
  void _fill(
    int first,
    int last,
    void Function(int node, int offset) visit, {
    bool withClosing = false,
  }) {
    final startNode = _pageNode[first];
    final endNode = _pageNode[last - 1];
    var endOffset = _pageOffset[last - 1] + 1;
    if (withClosing) {
      final data = _texts[endNode].data;
      while (endOffset < data.length &&
          !_isSpace(data.codeUnitAt(endOffset)) &&
          foldWordChar(data.codeUnitAt(endOffset)) == null) {
        endOffset++;
      }
    }
    for (var n = startNode; n <= endNode; n++) {
      final from = n == startNode ? _pageOffset[first] : 0;
      final to = n == endNode ? endOffset : _texts[n].data.length;
      for (var i = from; i < to; i++) {
        visit(n, i);
      }
    }
  }

  List<int> _kindsOf(int n) =>
      _kinds[n] ??= List<int>.filled(_texts[n].data.length, 0);

  List<int> _wordsOf(int n) =>
      _words[n] ??= List<int>.filled(_texts[n].data.length, -1);

  /// Cambia el texto [n] por sus tramos, cada uno con lo que lleva. Un texto
  /// de solo espacios queda como está: entre las filas de una tabla o los
  /// ítems de una lista, un `<mark>` movería cosas de lugar.
  void _rebuild(int n) {
    final text = _texts[n];
    final parent = text.parentNode;
    final data = text.data;
    if (parent == null || data.trim().isEmpty) return;
    final kinds = _kinds[n];
    final words = _words[n];
    int kindAt(int i) => kinds?[i] ?? 0;
    int wordAt(int i) => words?[i] ?? -1;

    final pieces = <Node>[];
    var start = 0;
    while (start < data.length) {
      final kind = kindAt(start);
      final word = wordAt(start);
      var end = start + 1;
      while (end < data.length && kindAt(end) == kind && wordAt(end) == word) {
        end++;
      }
      final piece = data.substring(start, end);
      if (kind == 0) {
        pieces.add(Text(piece));
      } else {
        pieces.add(_markOf(piece, kind, word));
      }
      start = end;
    }

    final index = parent.nodes.indexOf(text);
    text.remove();
    parent.nodes.insertAll(index, pieces);
  }

  Element _markOf(String piece, int kind, int word) {
    final classes = [
      'sn-m',
      if (kind & 1 != 0) 'sn-summary',
      if (kind & 2 != 0) 'sn-synthesis',
      if (word >= 0) 'sn-w',
    ];
    final mark = Element.tag('mark')
      ..attributes['class'] = classes.join(' ')
      ..append(Text(piece));
    if (word >= 0) mark.attributes['data-o'] = '$word';
    return mark;
  }
}

bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

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

  // Las palabras clave, todas, estén o no en una oración resaltada (F39).
  const keywords = 'html.sn-kw mark.sn-k';
  return [
    // Sin nada de lo que la página le ponga a `mark` —margen, borde, peso,
    // `display`—: envolver una palabra no puede mover ni una letra (F39).
    'mark.sn-m{all:unset}',
    // La síntesis después: con las dos prendidas, va encima del resumen.
    'html.sn-l-summary mark.sn-summary${paint(colors.summary)}',
    'html.sn-l-synthesis mark.sn-synthesis${paint(colors.synthesis)}',
    '$keywords${paint(colors.keyword, bold: true)}',
    'html.sn-pick mark.sn-w{cursor:pointer}',
    // Los resaltados a mano (F38) van adentro del texto, así que encima de
    // las oraciones; una palabra clave que se ve los tapa. Subrayados no: una
    // línea debajo de las letras no tapa nada.
    '.sn-hf{color:#000!important}',
    '$keywords .sn-hf{background:transparent!important}',
  ].join('\n');
}

/// El programa de la app en la página: cambia las clases que prenden cada
/// color y, eligiendo palabras clave, avisa la posición de la palabra tocada.
const _script = '''
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

  // Los resaltados de la persona: un <span> por tramo, adentro del texto.
  function unwrap() {
    var spans = document.querySelectorAll('span.sn-h');
    for (var i = spans.length - 1; i >= 0; i--) {
      var span = spans[i];
      var parent = span.parentNode;
      if (!parent) continue;
      while (span.firstChild) parent.insertBefore(span.firstChild, span);
      parent.removeChild(span);
    }
    document.body.normalize();
  }
  function spanOf(item) {
    var span = document.createElement('span');
    span.className = 'sn-h ' + (item.underline ? 'sn-hu' : 'sn-hf');
    span.setAttribute('data-h', item.id);
    if (item.underline) {
      span.style.cssText = 'text-decoration:underline;text-decoration-color:' +
        item.color + ';text-decoration-thickness:2px;text-underline-offset:2px';
    } else {
      span.style.background = item.color;
    }
    return span;
  }
  function wrapText(node, parts, items) {
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
        var span = spanOf(items[covering[c]]);
        span.appendChild(top);
        top = span;
      }
      fragment.appendChild(top);
    }
    node.parentNode.replaceChild(fragment, node);
  }

  window.sinapsis = {
    marks: function (items) {
      unwrap();
      if (!items || !items.length) return;
      var texts = textNodes();
      var starts = [];
      var total = 0;
      for (var i = 0; i < texts.length; i++) {
        starts.push(total);
        total += texts[i].data.length;
      }
      var perNode = {};
      items.forEach(function (item, k) {
        item.ranges.forEach(function (range) {
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
            if (to > from) (perNode[n] = perNode[n] || []).push({from: from, to: to, k: k});
          }
        });
      });
      Object.keys(perNode).forEach(function (n) {
        wrapText(texts[n], perNode[n], items);
      });
    },
    clearSelection: function () {
      var selection = window.getSelection();
      if (selection) selection.removeAllRanges();
    },
    set: function (state) {
      root.classList.toggle('sn-l-summary', !!state.summary);
      root.classList.toggle('sn-l-synthesis', !!state.synthesis);
      root.classList.toggle('sn-kw', !!state.keywords);
      root.classList.toggle('sn-pick', !!state.picking);
      picking = !!state.picking;
      var chosen = {};
      (state.kw || []).forEach(function (o) { chosen[String(o)] = true; });
      var words = document.querySelectorAll('mark.sn-w');
      for (var i = 0; i < words.length; i++) {
        var word = words[i];
        word.classList.toggle('sn-k', chosen[word.getAttribute('data-o')] === true);
      }
    }
  };
  document.addEventListener('click', function (event) {
    if (!picking) return;
    var node = event.target;
    while (node && node.nodeType === 1 && !node.classList.contains('sn-w')) {
      node = node.parentNode;
    }
    if (!node || node.nodeType !== 1) return;
    event.preventDefault();
    event.stopPropagation();
    if (window.SinapsisStudy) window.SinapsisStudy.postMessage(node.getAttribute('data-o'));
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
