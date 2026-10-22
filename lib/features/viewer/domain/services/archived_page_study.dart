import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/transform/domain/archive/page_images.dart';

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
String showableArchivedPage(String html, {ArchivedPageStudy? study}) {
  final document = html_parser.parse(html);
  showArchivedImages(document);
  if (study != null) {
    _neutralize(document);
    final body = document.body;
    if (body != null) _PageMarker(body, study.content).mark(study.sentences);
    _inject(document, study.colors);
  }
  return document.outerHtml;
}

/// Lo que se le pide a la página para mostrar lo que se eligió: el resumen o
/// la síntesis —[layer], `null` ninguno—, si se ven las palabras clave
/// [keywords] —las que empiezan en [keywordOffsets]— y si tocar una palabra
/// la elige ([picking]).
String archivedPageStateScript({
  required StudyMarkKind? layer,
  required bool keywords,
  required bool picking,
  required Iterable<int> keywordOffsets,
}) {
  final state = jsonEncode({
    'layer': switch (layer) {
      StudyMarkKind.summary => 'summary',
      StudyMarkKind.synthesis => 'synthesis',
      _ => null,
    },
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
    for (var n = 0; n < _texts.length; n++) {
      final data = _texts[n].data;
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

  const keywords = [
    'html.sn-kw.sn-l-summary mark.sn-summary.sn-k',
    'html.sn-kw.sn-l-synthesis mark.sn-synthesis.sn-k',
    'html.sn-kw:not(.sn-l-summary):not(.sn-l-synthesis) mark.sn-k',
  ];
  return [
    'mark.sn-m{background:transparent;color:inherit;padding:0}',
    'html.sn-l-summary mark.sn-summary${paint(colors.summary)}',
    'html.sn-l-synthesis mark.sn-synthesis${paint(colors.synthesis)}',
    '${keywords.join(', ')}${paint(colors.keyword, bold: true)}',
    'html.sn-pick mark.sn-w{cursor:pointer}',
  ].join('\n');
}

/// El programa de la app en la página: cambia las clases que prenden cada
/// color y, eligiendo palabras clave, avisa la posición de la palabra tocada.
const _script = '''
(function () {
  var root = document.documentElement;
  var picking = false;
  window.sinapsis = {
    set: function (state) {
      root.classList.toggle('sn-l-summary', state.layer === 'summary');
      root.classList.toggle('sn-l-synthesis', state.layer === 'synthesis');
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
})();
''';
