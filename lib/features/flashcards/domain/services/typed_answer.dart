/// «Escribí la respuesta» (F31): compara lo que la persona tipeó con la
/// respuesta correcta y devuelve un veredicto con la diferencia lista para
/// mostrar.
///
/// Puro: texto adentro, resultado afuera. La pantalla decide qué hacer con el
/// veredicto —un «casi» no tiene por qué contar como acierto: lo que muestra
/// es la diferencia, y la persona califica—.
///
/// **Qué se ignora** (`normalizeForComparison`): mayúsculas, acentos
/// (`está` = `esta`, pero `ñ` NO es `n`: `año` y `ano` son palabras
/// distintas), puntuación, espacios de más, un artículo al principio
/// (`el imperio` = `imperio`) y las comillas simples (`don't` = `dont`).
/// **Qué NO se ignora**: los números. `1492` y `1493` son respuestas
/// distintas aunque difieran en un dígito; `3,14` y `3.14` son el mismo
/// número, y `1.000` y `1000` también. Tampoco el signo menos, ni `%`, `$`,
/// `€`, `£`, `°`, `+` y `#` (`C++` no es `C`).
///
/// **Cuánto error se tolera** (distancia de edición con transposiciones, sobre
/// el texto ya normalizado): hasta 5 caracteres, ninguno (`pato` no es
/// `gato`, `perro` no es `pero`); de 6 en adelante, el 15 % del largo, al
/// menos 1 y a lo sumo 8. Medido con ejemplos reales de tarjetas: `mitocondria`
/// (11) tolera 1, `revolución francesa` (19) tolera 2, `segunda guerra
/// mundial` (22) tolera 3 —pero le faltan dos palabras: 8 de distancia, no
/// pasa—. Además, una palabra corta (hasta 3 letras) que sobra, falta o
/// cambia nunca es un descuido: `Juan Carlos I` no es `Juan Carlos II` y
/// `caída de la Bastilla` no es `caída Bastilla`.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Qué tan bien coincide lo escrito con lo correcto.
enum TypedAnswerVerdict {
  /// Es lo mismo, salvo mayúsculas, acentos, puntuación o un artículo.
  match,

  /// Con un descuido de tipeo: mostrale la diferencia y que decida.
  close,

  /// No es la respuesta.
  mismatch,
}

/// Qué es un trozo de la diferencia.
enum TypedAnswerSegmentKind {
  /// Lo que coincide (o lo que no cuenta: puntuación, un artículo de más).
  same,

  /// Está en la respuesta correcta y la persona no lo escribió.
  missing,

  /// La persona lo escribió y no está en la respuesta correcta.
  extra,
}

/// Un trozo de la diferencia. [expectedText] es la parte que le toca a la
/// respuesta correcta y [typedText] la que le toca a lo escrito: en un
/// [TypedAnswerSegmentKind.same] pueden diferir en mayúsculas, acentos o
/// puntuación (`Roma` / `roma`), o una de las dos puede estar vacía (un
/// artículo que solo está de un lado); un `missing` no tiene [typedText] y
/// un `extra` no tiene [expectedText].
@immutable
class TypedAnswerSegment {
  const TypedAnswerSegment(
    this.kind, {
    this.expectedText = '',
    this.typedText = '',
  });

  final TypedAnswerSegmentKind kind;
  final String expectedText;
  final String typedText;

  @override
  bool operator ==(Object other) =>
      other is TypedAnswerSegment &&
      other.kind == kind &&
      other.expectedText == expectedText &&
      other.typedText == typedText;

  @override
  int get hashCode => Object.hash(kind, expectedText, typedText);

  @override
  String toString() =>
      'TypedAnswerSegment($kind, esperado: "$expectedText", escrito: '
      '"$typedText")';
}

/// El resultado de comparar.
class TypedAnswerResult {
  const TypedAnswerResult({
    required this.verdict,
    required this.segments,
    required this.distance,
    required this.similarity,
    required this.isBlank,
  });

  final TypedAnswerVerdict verdict;

  /// La diferencia, en orden, como una sola lista. Para pintar lo escrito,
  /// [typedSegments]; para pintar lo correcto, [expectedSegments].
  final List<TypedAnswerSegment> segments;

  /// Ediciones de carácter entre los dos textos ya normalizados (0 si
  /// coinciden). En un texto de miles de caracteres que difiere en casi todo
  /// el medio es solo una cota: «más de lo que se tolera».
  final int distance;

  /// De 0 a 1: 1 es idéntico tras normalizar.
  final double similarity;

  /// Si la persona no escribió nada (o solo blancos y signos).
  final bool isBlank;

  bool get isMatch => verdict == TypedAnswerVerdict.match;

  /// Lo escrito, con lo que sobra marcado: los trozos que tienen texto de
  /// ese lado, en el orden en que se escribió.
  List<TypedAnswerSegment> get typedSegments => [
    for (final s in segments)
      if (s.typedText.isNotEmpty) s,
  ];

  /// La respuesta correcta, con lo que faltó marcado.
  List<TypedAnswerSegment> get expectedSegments => [
    for (final s in segments)
      if (s.expectedText.isNotEmpty) s,
  ];
}

/// Compara [typed] con [correct].
///
/// [alternatives] son otras respuestas que también valen (`Roma` y `Roma
/// antigua`). Un paréntesis de la respuesta es opcional: `Mitocondria
/// (orgánulo)` también acepta `mitocondria`. Se elige la que más se acerca.
TypedAnswerResult compareTypedAnswer({
  required String typed,
  required String correct,
  List<String> alternatives = const [],
}) {
  final typedSide = _Side(typed);
  if (typedSide.words.isEmpty) {
    return TypedAnswerResult(
      verdict: TypedAnswerVerdict.mismatch,
      segments: _wholeSide(correct, expected: true),
      distance: _Side(correct).joined.length,
      similarity: 0,
      isBlank: true,
    );
  }

  _Evaluation? best;
  for (final candidate in _variantsOf([correct, ...alternatives])) {
    final evaluation = _evaluate(typedSide, candidate);
    if (best == null || evaluation._betterThan(best)) best = evaluation;
  }
  // `_variantsOf` siempre devuelve al menos la respuesta correcta.
  final chosen = best!;
  return TypedAnswerResult(
    verdict: chosen.verdict,
    segments: _diff(typedSide, chosen.expected),
    distance: chosen.distance,
    similarity: chosen.similarity,
    isBlank: false,
  );
}

/// El texto reducido a lo que se compara: minúsculas, sin acentos (salvo la
/// ñ), sin puntuación, con un solo espacio entre palabras y sin artículo al
/// principio si queda algo después. Ver el comentario de la biblioteca.
String normalizeForComparison(String text) => _Side(text).joined;

// --- Normalización -----------------------------------------------------------

const _decimalMark = '\u0001';
const _minusMark = '\u0002';

/// Símbolos que cambian el significado y por eso no son «puntuación».
const _keptSymbols = r'%$€£°+#';

const _articles = {
  'el', 'la', 'los', 'las', 'lo', 'un', 'una', 'unos', 'unas', //
  'the', 'an',
};

const _foldTable = <String, String>{
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', //
  'ă': 'a', 'ą': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e',
  'ě': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o', 'ő': 'o',
  'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ś': 's', 'š': 's', 'ș': 's', 'ş': 's',
  'ź': 'z', 'ž': 'z', 'ż': 'z', 'ń': 'n', 'ň': 'n', 'ł': 'l', 'đ': 'd',
  'ď': 'd', 'ř': 'r', 'ť': 't', 'ț': 't', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
  // La ñ se conserva a propósito: `año` y `ano` no son lo mismo.
};

final _combiningMarks = RegExp('[\u0300-\u036F]');
final _thousands = RegExp(r'(?<![\d.,])\d{1,3}(?:[.,]\d{3})+(?![\d])');
final _decimal = RegExp(r'(?<=\d)[.,](?=\d)');
final _leadingMinus = RegExp(r'^[-−–](?=\d)');
final _dropped = RegExp(
  '[^\\p{L}\\p{N}${RegExp.escape(_keptSymbols)}$_decimalMark$_minusMark]',
  unicode: true,
);
final _numberToken = RegExp('$_minusMark?\\d+(?:$_decimalMark\\d+)?');

/// Una palabra con su forma original y la que se compara.
class _Word {
  const _Word(this.display, this.norm, {this.article = false});

  /// Como se escribió, con su puntuación pegada.
  final String display;

  /// Como se compara; nunca vacía.
  final String norm;

  /// Si es el artículo opcional del principio.
  final bool article;

  _Word asArticle() => _Word(display, norm, article: true);
}

/// El texto de un lado, ya partido en palabras.
class _Side {
  factory _Side(String text) {
    final words = <_Word>[];
    for (final token in _tokens(text)) {
      final norm = _foldToken(token);
      if (norm.isEmpty) {
        // Puntuación suelta (`-`, `—`): se pega a la palabra anterior para que
        // se vea, y no cuenta.
        if (words.isNotEmpty) {
          final last = words.removeLast();
          words.add(_Word('${last.display} $token', last.norm));
        }
        continue;
      }
      words.add(_Word(token, norm));
    }
    if (words.length > 1 && _articles.contains(words.first.norm)) {
      words[0] = words.first.asArticle();
    }
    return _Side._(words);
  }

  _Side._(this.words)
    : joined = words.where((w) => !w.article).map((w) => w.norm).join(' ');

  final List<_Word> words;

  /// Lo que se compara: las palabras sin el artículo opcional, con un
  /// espacio entre cada una.
  final String joined;

  /// Las palabras que se alinean (sin el artículo opcional).
  List<_Word> get core => [
    for (final w in words)
      if (!w.article) w,
  ];
}

/// Parte [text] en palabras por los blancos y después de un guion o una barra
/// entre dos letras o números (`bien-estar` → `bien-`, `estar`).
List<String> _tokens(String text) {
  final tokens = <String>[];
  for (final chunk in text.split(RegExp(r'\s+'))) {
    if (chunk.isEmpty) continue;
    final start = StringBuffer();
    final runes = chunk.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      start.writeCharCode(runes[i]);
      final isSplit =
          (runes[i] == 0x2D || runes[i] == 0x2F) &&
          i > 0 &&
          i + 1 < runes.length &&
          _isWordChar(runes[i - 1]) &&
          _isWordChar(runes[i + 1]);
      if (isSplit) {
        tokens.add(start.toString());
        start.clear();
      }
    }
    if (start.isNotEmpty) tokens.add(start.toString());
  }
  return tokens;
}

bool _isWordChar(int rune) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(String.fromCharCode(rune));

/// Una palabra en su forma comparable. Vacía si era solo puntuación.
String _foldToken(String token) {
  var t = token
      .replaceAll('n\u0303', 'ñ')
      .replaceAll('N\u0303', 'Ñ')
      .replaceAll(_combiningMarks, '');
  // Los números, antes de que la puntuación se lleve sus separadores.
  t = t.replaceAllMapped(
    _thousands,
    (m) => m[0]!.replaceAll(RegExp('[.,]'), ''),
  );
  t = t.replaceAll(_decimal, _decimalMark);
  t = t.replaceFirst(_leadingMinus, _minusMark);
  t = t.toLowerCase().replaceAll(RegExp("['’`´]"), '');
  final folded = StringBuffer();
  for (final rune in t.runes) {
    final ch = String.fromCharCode(rune);
    folded.write(_foldTable[ch] ?? ch);
  }
  return folded.toString().replaceAll(_dropped, '');
}

/// Cómo se compara un solo carácter: `''` si no cuenta (puntuación).
String _charKey(int rune) {
  final ch = String.fromCharCode(rune);
  if (_combiningMarks.hasMatch(ch)) return '';
  final lower = ch.toLowerCase();
  final folded = _foldTable[lower] ?? lower;
  return _dropped.hasMatch(folded) ? '' : folded;
}

// --- Evaluación --------------------------------------------------------------

/// Las respuestas que valen: cada una, y cada una sin sus paréntesis.
List<String> _variantsOf(List<String> answers) {
  final out = <String>[];
  final paren = RegExp(r'\s*[\(\[][^\)\]]*[\)\]]');
  for (final answer in answers) {
    out.add(answer);
    final stripped = answer.replaceAll(paren, '').trim();
    if (stripped.isNotEmpty && stripped != answer.trim()) out.add(stripped);
  }
  return out;
}

class _Evaluation {
  _Evaluation(this.expected, this.verdict, this.distance, this.similarity);

  final _Side expected;
  final TypedAnswerVerdict verdict;
  final int distance;
  final double similarity;

  bool _betterThan(_Evaluation other) {
    if (verdict != other.verdict) return verdict.index < other.verdict.index;
    return distance < other.distance;
  }
}

_Evaluation _evaluate(_Side typed, String correct) {
  final expected = _Side(correct);
  final a = typed.joined;
  final b = expected.joined;
  if (a == b) {
    return _Evaluation(expected, TypedAnswerVerdict.match, 0, 1);
  }

  final length = a.runes.length > b.runes.length
      ? a.runes.length
      : b.runes.length;
  final allowed = tolerableEdits(length);
  final d = _distance(a, b, allowed);
  final similarity = length == 0 ? 0.0 : 1 - d / length;

  // Un número distinto es otra respuesta, por parecidos que sean los textos.
  final sameNumbers = _numbersOf(a).join(',') == _numbersOf(b).join(',');
  if (!sameNumbers) {
    return _Evaluation(expected, TypedAnswerVerdict.mismatch, d, similarity);
  }
  // Las mismas letras con los espacios en otro lado (`sanfrancisco`): un
  // descuido, por largo que sea el texto.
  if (a.replaceAll(' ', '') == b.replaceAll(' ', '')) {
    return _Evaluation(expected, TypedAnswerVerdict.close, d, similarity);
  }
  if (d > allowed || _shortWordDiffers(typed, expected)) {
    return _Evaluation(expected, TypedAnswerVerdict.mismatch, d, similarity);
  }
  return _Evaluation(expected, TypedAnswerVerdict.close, d, similarity);
}

/// Cuántas ediciones se toleran en un texto de [length] caracteres
/// normalizados. Ver el comentario de la biblioteca.
int tolerableEdits(int length) {
  if (length < 6) return 0;
  final byRatio = (length * 0.15).floor();
  return byRatio < 1 ? 1 : (byRatio > 8 ? 8 : byRatio);
}

List<String> _numbersOf(String normalized) =>
    _numberToken.allMatches(normalized).map((m) => m[0]!).toList();

/// Si una palabra de hasta 3 letras sobra, falta o cambia entre los dos
/// lados.
bool _shortWordDiffers(_Side typed, _Side expected) {
  final ops = _alignWords(typed.core, expected.core);
  if (ops == null) return false;
  for (final op in ops) {
    switch (op.kind) {
      case _OpKind.equal:
        break;
      case _OpKind.sub:
        if (_shorter(op.typed!.norm, op.expected!.norm) <= 3) return true;
      case _OpKind.del:
        if (op.typed!.norm.runes.length <= 3) return true;
      case _OpKind.ins:
        if (op.expected!.norm.runes.length <= 3) return true;
    }
  }
  return false;
}

int _shorter(String a, String b) {
  final la = a.runes.length;
  final lb = b.runes.length;
  return la < lb ? la : lb;
}

/// La distancia entre los dos textos. Exacta, salvo en textos de miles de
/// caracteres que además difieren en la mayor parte del medio: ahí solo se
/// sabe si pasa de [limit], y devuelve `limit + 1` si pasa.
int _distance(String a, String b, int limit) {
  final ra = a.runes.toList();
  final rb = b.runes.toList();
  // El principio y el final que coinciden no cambian la distancia: en un
  // texto largo con un descuido, lo que queda por comparar es chico.
  var head = 0;
  while (head < ra.length && head < rb.length && ra[head] == rb[head]) {
    head++;
  }
  var tail = 0;
  while (tail < ra.length - head &&
      tail < rb.length - head &&
      ra[ra.length - 1 - tail] == rb[rb.length - 1 - tail]) {
    tail++;
  }
  final ma = ra.sublist(head, ra.length - tail);
  final mb = rb.sublist(head, rb.length - tail);
  if (ma.length * mb.length <= _maxCells) return _osa(ma, mb);
  return _osaBounded(ma, mb, limit);
}

/// Hasta qué producto de largos se calcula la tabla entera (16 millones
/// de celdas); por encima, solo la franja que podría dar el límite
/// o menos (ver `_osaBounded`).
const _maxCells = 16 * 1000 * 1000;

/// Distancia de edición con transposiciones de dos vecinos (Damerau
/// restringida) entre dos textos, por puntos de código. Tres filas de memoria.
/// Público para las pruebas: la versión con franja se compara contra esta.
@visibleForTesting
int editDistance(String a, String b) =>
    _osa(a.runes.toList(), b.runes.toList());

int _osa(List<int> a, List<int> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  var prev2 = Int32List(m + 1);
  var prev = Int32List(m + 1);
  var cur = Int32List(m + 1);
  for (var j = 0; j <= m; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = prev[j] + 1;
      final insert = cur[j - 1] + 1;
      if (insert < best) best = insert;
      final replace = prev[j - 1] + cost;
      if (replace < best) best = replace;
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final swap = prev2[j - 2] + 1;
        if (swap < best) best = swap;
      }
      cur[j] = best;
    }
    final tmp = prev2;
    prev2 = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[m];
}

/// Lo mismo que [editDistance], pero solo mira la franja de `2 * limit + 1`
/// celdas alrededor de la diagonal, que es donde puede estar una distancia de
/// [limit] o menos: costo proporcional al largo, no a su cuadrado. Devuelve la
/// exacta si es [limit] o menos y `limit + 1` si es mayor.
@visibleForTesting
int boundedEditDistance(String a, String b, int limit) =>
    _osaBounded(a.runes.toList(), b.runes.toList(), limit);

int _osaBounded(List<int> a, List<int> b, int limit) {
  final n = a.length;
  final m = b.length;
  final over = limit + 1;
  if ((n - m).abs() > limit) return over;
  if (n == 0) return m;
  if (m == 0) return n;

  // Un valor «infinito» que no desborda al sumarle uno.
  final inf = over + 1;
  var prev2 = Int32List(m + 1)..fillRange(0, m + 1, inf);
  var prev = Int32List(m + 1)..fillRange(0, m + 1, inf);
  var cur = Int32List(m + 1)..fillRange(0, m + 1, inf);
  for (var j = 0; j <= m && j <= limit; j++) {
    prev[j] = j;
  }
  for (var i = 1; i <= n; i++) {
    final low = i - limit < 1 ? 1 : i - limit;
    final high = i + limit > m ? m : i + limit;
    cur[0] = i <= limit ? i : inf;
    if (low > 1) cur[low - 1] = inf;
    var rowMin = cur[0];
    for (var j = low; j <= high; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = prev[j] + 1;
      final insert = cur[j - 1] + 1;
      if (insert < best) best = insert;
      final replace = prev[j - 1] + cost;
      if (replace < best) best = replace;
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final swap = prev2[j - 2] + 1;
        if (swap < best) best = swap;
      }
      if (best > inf) best = inf;
      cur[j] = best;
      if (best < rowMin) rowMin = best;
    }
    // Ninguna celda de la franja llega al límite: ya no baja.
    if (rowMin > limit) return over;
    final tmp = prev2;
    prev2 = prev;
    prev = cur;
    cur = tmp;
  }
  final result = prev[m];
  return result > limit ? over : result;
}

// --- Alineación de palabras --------------------------------------------------

enum _OpKind { equal, sub, del, ins }

class _WordOp {
  const _WordOp(this.kind, {this.typed, this.expected});
  final _OpKind kind;
  final _Word? typed;
  final _Word? expected;
}

/// Producto de palabras a partir del cual no se alinea de a una (el resto
/// se muestra como un bloque que sobra y otro que falta).
const _maxAlignCells = 250 * 1000;

/// Alinea las palabras de [typed] con las de [expected]: iguales, cambiadas
/// (con la diferencia de letras adentro), de más o de menos. `null` si son
/// tantas que no se alinean (después de quitar el principio y el final que
/// coinciden).
List<_WordOp>? _alignWords(List<_Word> typed, List<_Word> expected) {
  var head = 0;
  while (head < typed.length &&
      head < expected.length &&
      typed[head].norm == expected[head].norm) {
    head++;
  }
  var tail = 0;
  while (tail < typed.length - head &&
      tail < expected.length - head &&
      typed[typed.length - 1 - tail].norm ==
          expected[expected.length - 1 - tail].norm) {
    tail++;
  }

  final a = typed.sublist(head, typed.length - tail);
  final b = expected.sublist(head, expected.length - tail);
  final ops = <_WordOp>[
    for (var i = 0; i < head; i++)
      _WordOp(_OpKind.equal, typed: typed[i], expected: expected[i]),
  ];

  if (a.length * b.length > _maxAlignCells) return null;

  final n = a.length;
  final m = b.length;
  // costos[i][j]: lo que cuesta alinear a[i..] con b[j..].
  final cost = List.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = n - 1; i >= 0; i--) {
    cost[i][m] = cost[i + 1][m] + a[i].norm.runes.length;
  }
  for (var j = m - 1; j >= 0; j--) {
    cost[n][j] = cost[n][j + 1] + b[j].norm.runes.length;
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      final sub = a[i].norm == b[j].norm
          ? 0
          : _osa(a[i].norm.runes.toList(), b[j].norm.runes.toList());
      var best = cost[i + 1][j + 1] + sub;
      final del = cost[i + 1][j] + a[i].norm.runes.length;
      if (del < best) best = del;
      final ins = cost[i][j + 1] + b[j].norm.runes.length;
      if (ins < best) best = ins;
      cost[i][j] = best;
    }
  }

  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m) {
      final same = a[i].norm == b[j].norm;
      final sub = same
          ? 0
          : _osa(a[i].norm.runes.toList(), b[j].norm.runes.toList());
      if (cost[i][j] == cost[i + 1][j + 1] + sub) {
        ops.add(
          _WordOp(
            same ? _OpKind.equal : _OpKind.sub,
            typed: a[i],
            expected: b[j],
          ),
        );
        i++;
        j++;
        continue;
      }
    }
    if (i < n && cost[i][j] == cost[i + 1][j] + a[i].norm.runes.length) {
      ops.add(_WordOp(_OpKind.del, typed: a[i]));
      i++;
    } else {
      ops.add(_WordOp(_OpKind.ins, expected: b[j]));
      j++;
    }
  }

  for (var k = tail; k > 0; k--) {
    ops.add(
      _WordOp(
        _OpKind.equal,
        typed: typed[typed.length - k],
        expected: expected[expected.length - k],
      ),
    );
  }
  return ops;
}

// --- Diferencia para mostrar -------------------------------------------------

List<TypedAnswerSegment> _wholeSide(String text, {required bool expected}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  return [
    TypedAnswerSegment(
      expected ? TypedAnswerSegmentKind.missing : TypedAnswerSegmentKind.extra,
      expectedText: expected ? trimmed : '',
      typedText: expected ? '' : trimmed,
    ),
  ];
}

List<TypedAnswerSegment> _diff(_Side typed, _Side expected) {
  final out = <TypedAnswerSegment>[];
  void add(TypedAnswerSegment s) {
    if (s.expectedText.isEmpty && s.typedText.isEmpty) return;
    if (out.isNotEmpty && out.last.kind == s.kind) {
      final last = out.removeLast();
      out.add(
        TypedAnswerSegment(
          s.kind,
          expectedText: last.expectedText + s.expectedText,
          typedText: last.typedText + s.typedText,
        ),
      );
    } else {
      out.add(s);
    }
  }

  // El artículo opcional del principio: nunca es un error.
  final typedArticle = typed.words.firstOrNull?.article ?? false;
  final expectedArticle = expected.words.firstOrNull?.article ?? false;
  if (typedArticle || expectedArticle) {
    add(
      TypedAnswerSegment(
        TypedAnswerSegmentKind.same,
        expectedText: expectedArticle ? '${expected.words.first.display} ' : '',
        typedText: typedArticle ? '${typed.words.first.display} ' : '',
      ),
    );
  }

  final ops = _alignWords(typed.core, expected.core);
  if (ops == null) {
    // Demasiado largo para ir palabra por palabra: dos bloques.
    add(
      TypedAnswerSegment(
        TypedAnswerSegmentKind.extra,
        typedText: typed.core.map((w) => w.display).join(' '),
      ),
    );
    add(
      TypedAnswerSegment(
        TypedAnswerSegmentKind.missing,
        expectedText: expected.core.map((w) => w.display).join(' '),
      ),
    );
  } else {
    const space = TypedAnswerSegment(
      TypedAnswerSegmentKind.same,
      expectedText: ' ',
      typedText: ' ',
    );
    for (final op in ops) {
      switch (op.kind) {
        case _OpKind.equal:
          add(
            TypedAnswerSegment(
              TypedAnswerSegmentKind.same,
              expectedText: op.expected!.display,
              typedText: op.typed!.display,
            ),
          );
          add(space);
        case _OpKind.sub:
          _charDiff(op.typed!.display, op.expected!.display).forEach(add);
          add(space);
        case _OpKind.del:
          add(
            TypedAnswerSegment(
              TypedAnswerSegmentKind.extra,
              typedText: '${op.typed!.display} ',
            ),
          );
        case _OpKind.ins:
          add(
            TypedAnswerSegment(
              TypedAnswerSegmentKind.missing,
              expectedText: '${op.expected!.display} ',
            ),
          );
      }
    }
  }
  return _trimEnds(out);
}

/// Saca el espacio que quedó al final de cada lado.
List<TypedAnswerSegment> _trimEnds(List<TypedAnswerSegment> segments) {
  final list = [...segments];
  var expectedDone = false;
  var typedDone = false;
  for (var i = list.length - 1; i >= 0 && !(expectedDone && typedDone); i--) {
    var s = list[i];
    var expectedText = s.expectedText;
    var typedText = s.typedText;
    if (!expectedDone && expectedText.isNotEmpty) {
      expectedText = expectedText.trimRight();
      if (expectedText.isNotEmpty) expectedDone = true;
    }
    if (!typedDone && typedText.isNotEmpty) {
      typedText = typedText.trimRight();
      if (typedText.isNotEmpty) typedDone = true;
    }
    s = TypedAnswerSegment(
      s.kind,
      expectedText: expectedText,
      typedText: typedText,
    );
    list[i] = s;
  }
  return [
    for (final s in list)
      if (s.expectedText.isNotEmpty || s.typedText.isNotEmpty) s,
  ];
}

/// Palabras de más de este producto de letras no se comparan carácter por
/// carácter: sobran o faltan enteras.
const _maxCharCells = 1000 * 1000;

/// La diferencia de letras entre dos palabras que se parecen. Los signos
/// (puntuación) nunca son un error: acompañan a su lado.
List<TypedAnswerSegment> _charDiff(String typed, String expected) {
  final a = typed.runes.toList();
  final b = expected.runes.toList();
  if (a.length * b.length > _maxCharCells) {
    return [
      TypedAnswerSegment(TypedAnswerSegmentKind.extra, typedText: typed),
      TypedAnswerSegment(
        TypedAnswerSegmentKind.missing,
        expectedText: expected,
      ),
    ];
  }
  final ka = [for (final r in a) _charKey(r)];
  final kb = [for (final r in b) _charKey(r)];
  final n = a.length;
  final m = b.length;

  int skip(String key) => key.isEmpty ? 0 : 1;
  final cost = List.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = n - 1; i >= 0; i--) {
    cost[i][m] = cost[i + 1][m] + skip(ka[i]);
  }
  for (var j = m - 1; j >= 0; j--) {
    cost[n][j] = cost[n][j + 1] + skip(kb[j]);
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      var best = cost[i + 1][j] + skip(ka[i]);
      final ins = cost[i][j + 1] + skip(kb[j]);
      if (ins < best) best = ins;
      if (ka[i].isNotEmpty && kb[j].isNotEmpty) {
        final sub = cost[i + 1][j + 1] + (ka[i] == kb[j] ? 0 : 2);
        if (sub < best) best = sub;
      }
      cost[i][j] = best;
    }
  }

  final out = <TypedAnswerSegment>[];
  void add(TypedAnswerSegmentKind kind, String expectedText, String typedText) {
    if (out.isNotEmpty && out.last.kind == kind) {
      final last = out.removeLast();
      out.add(
        TypedAnswerSegment(
          kind,
          expectedText: last.expectedText + expectedText,
          typedText: last.typedText + typedText,
        ),
      );
    } else {
      out.add(
        TypedAnswerSegment(
          kind,
          expectedText: expectedText,
          typedText: typedText,
        ),
      );
    }
  }

  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n &&
        j < m &&
        ka[i].isNotEmpty &&
        kb[j].isNotEmpty &&
        ka[i] == kb[j] &&
        cost[i][j] == cost[i + 1][j + 1]) {
      add(
        TypedAnswerSegmentKind.same,
        String.fromCharCode(b[j]),
        String.fromCharCode(a[i]),
      );
      i++;
      j++;
    } else if (i < n && cost[i][j] == cost[i + 1][j] + skip(ka[i])) {
      add(
        ka[i].isEmpty
            ? TypedAnswerSegmentKind.same
            : TypedAnswerSegmentKind.extra,
        '',
        String.fromCharCode(a[i]),
      );
      i++;
    } else if (j < m) {
      add(
        kb[j].isEmpty
            ? TypedAnswerSegmentKind.same
            : TypedAnswerSegmentKind.missing,
        String.fromCharCode(b[j]),
        '',
      );
      j++;
    } else {
      // Inalcanzable: los costos de arriba cubren todas las salidas. Se
      // avanza igual para no quedar en un bucle.
      i++;
    }
  }
  return out;
}
