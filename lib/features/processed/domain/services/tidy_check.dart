import 'package:flutter/foundation.dart';

/// Por qué no se queda lo que ordenó la IA (F45, decisión B): lo que la
/// comprobación encontró, de lo más grave a lo menos.
enum TidyProblem {
  /// Casi ninguna palabra es de la extracción: lo reescribió o lo tradujo.
  rewritten,

  /// Puso palabras que la extracción no tiene —o repitió alguna—.
  invented,

  /// Dejó afuera palabras de la extracción: la resumió o la recortó.
  missing,

  /// Las palabras son las mismas, pero en otro orden.
  reordered,
}

/// Lo que dio comprobar un texto ordenado contra su extracción: fiel, o con
/// su [problem].
@immutable
class TidyCheck {
  const TidyCheck._(this.problem);

  /// Con [problem]: se queda la extracción tal cual.
  const TidyCheck.rejected(TidyProblem this.problem);

  /// Cada palabra está, en su orden, y no hay ninguna de más.
  static const faithful = TidyCheck._(null);

  final TidyProblem? problem;

  bool get isFaithful => problem == null;

  @override
  bool operator ==(Object other) =>
      other is TidyCheck && other.problem == problem;

  @override
  int get hashCode => problem.hashCode;

  @override
  String toString() =>
      isFaithful ? 'TidyCheck.faithful' : 'TidyCheck($problem)';
}

/// Los renglones de un texto extraído que son encabezados, pies o números de
/// página (F45, decisión B): lo único que la IA puede sacar al ordenarlo.
///
/// Se arma con el texto **entero** del documento ([TidyMargins.of]), no con
/// el pedazo que se ordena: un encabezado se reconoce porque se repite página
/// tras página, y en un pedazo puede estar una sola vez.
///
/// Un renglón es de los márgenes si:
///
/// - es un número de página, solo o como se escribe —«12», «- 12 -», «Página
///   12 de 300», «xii»—;
/// - o se repite **igual** al menos [minRepeats] veces —«Introducción» arriba
///   de cada página—;
/// - o se repite igual salvo un número en una punta —«Historia de Roma 13»,
///   «14 Historia de Roma»—, y lo que queda tiene al menos dos palabras: así
///   «Capítulo 3» y «Capítulo 4», que son títulos y no encabezados, no
///   cuentan.
///
/// Nunca un renglón largo: un encabezado tiene pocas palabras, como mucho
/// [maxWords].
@immutable
class TidyMargins {
  const TidyMargins._(this._exact, this._numbered);

  /// Los márgenes de [text], el texto entero del documento.
  factory TidyMargins.of(String text) {
    final exact = <String, int>{};
    final numbered = <String, int>{};
    for (final line in text.split('\n')) {
      final key = _marginKey(line);
      if (key == null) continue;
      exact[key] = (exact[key] ?? 0) + 1;
      if (_withoutEdgeNumber(key) case final rest?) {
        numbered[rest] = (numbered[rest] ?? 0) + 1;
      }
    }
    return TidyMargins._(
      {
        for (final MapEntry(:key, :value) in exact.entries)
          if (value >= minRepeats) key,
      },
      {
        for (final MapEntry(:key, :value) in numbered.entries)
          if (value >= minRepeats) key,
      },
    );
  }

  /// Lo contrario de [toLists].
  factory TidyMargins.fromLists(
    ({List<String> exact, List<String> numbered}) lists,
  ) => TidyMargins._(lists.exact.toSet(), lists.numbered.toSet());

  /// Sin márgenes: ningún renglón se puede sacar.
  static const none = TidyMargins._({}, {});

  /// Cuántas veces tiene que repetirse un renglón para ser un encabezado.
  static const minRepeats = 3;

  /// Cuántas palabras tiene, como mucho, un encabezado o un pie.
  static const maxWords = 12;

  /// Los renglones que se repiten igual, ya normalizados.
  final Set<String> _exact;

  /// Los que se repiten salvo el número de una punta, sin él.
  final Set<String> _numbered;

  /// Si [line], un renglón de la extracción, es de los márgenes.
  bool contains(String line) {
    if (isPageNumberLine(line)) return true;
    final key = _marginKey(line);
    if (key == null) return false;
    if (_exact.contains(key)) return true;
    final rest = _withoutEdgeNumber(key);
    return rest != null && _numbered.contains(rest);
  }

  /// Para pasarlos a otro hilo y de vuelta: los dos conjuntos.
  ({List<String> exact, List<String> numbered}) toLists() =>
      (exact: _exact.toList(), numbered: _numbered.toList());
}

/// Lo que se compara de un renglón para saber si se repite: en minúsculas,
/// sin espacios de más; `null` si no tiene ninguna palabra o es demasiado
/// largo para ser un encabezado.
String? _marginKey(String line) {
  final key = line.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (key.isEmpty) return null;
  final words = _wordPattern.allMatches(key).length;
  if (words == 0 || words > TidyMargins.maxWords) return null;
  return key;
}

/// [key] sin el número de una de sus puntas —«historia de roma 13» →
/// «historia de roma»—, si queda algo de al menos dos palabras; si no,
/// `null`.
String? _withoutEdgeNumber(String key) {
  final rest = key
      .replaceFirst(RegExp(r'^\d{1,4}\s+'), '')
      .replaceFirst(RegExp(r'\s+\d{1,4}$'), '')
      .trim();
  if (rest == key) return null;
  return _wordPattern.allMatches(rest).length >= 2 ? rest : null;
}

final _pageNumberLine = RegExp(
  r'^[\s\-–—·•|()\[\]]*'
  r'((p[áa]g(ina)?|p|page)\.?\s*)?'
  r'(\d{1,4}|[ivxlc]{1,7})'
  r'(\s*(de|/|of)\s*\d{1,4})?'
  r'[\s\-–—·•|()\[\]]*$',
  caseSensitive: false,
);

/// Si [line] es solo un número de página: «12», «- 12 -», «Página 12 de
/// 300», «p. 7», «xii».
bool isPageNumberLine(String line) =>
    line.trim().isNotEmpty && _pageNumberLine.hasMatch(line);

/// Las palabras: tramos de letras, números y sus acentos sueltos.
final _wordPattern = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);

/// Los guiones con que se parte una palabra al final de un renglón. El guion
/// blando (U+00AD) no está: se saca antes de comparar, porque no se ve.
const _breakHyphens = {'-', '\u2010', '\u2011', '\u00AC'};

/// Comprueba [tidied] —lo que devolvió la IA al ordenar— contra [extracted],
/// la extracción de siempre (F45, decisión B): **cada palabra** de la
/// extracción tiene que estar, en el mismo orden, y no puede haber ninguna de
/// más.
///
/// Lo único que la IA puede cambiar, y por eso no se cuenta:
///
/// - los espacios, los renglones y los párrafos —unir los renglones de una
///   columna, separar un título—;
/// - la puntuación y las marcas de formato, que no son palabras;
/// - las mayúsculas —un título en mayúsculas—;
/// - una palabra partida con un guion al final del renglón —«pala-» y
///   «bra»—, que puede quedar entera —«palabra»— o igual que estaba;
/// - los renglones de los márgenes ([margins]): un encabezado, un pie o un
///   número de página, enteros, se pueden sacar.
///
/// Lo que se compara de cada palabra es como se lee: un acento escrito como
/// letra y marca aparte (lo que deja a veces un PDF) es el mismo que el
/// compuesto, y una ligadura —«ﬁ»— es sus dos letras.
///
/// Si no es fiel, dice por qué ([TidyProblem]): la reescribió o la tradujo,
/// inventó, recortó o cambió el orden.
///
/// Es lineal en la práctica: se recorre la extracción una vez, con las pocas
/// formas de alinearla que abren los márgenes. Si un texto patológico abriera
/// demasiadas ([maxStates]), no se da por fiel.
TidyCheck checkTidiedText(
  String extracted,
  String tidied, {
  TidyMargins margins = TidyMargins.none,
  int maxStates = 2000000,
}) {
  final source = _sourceWords(extracted, margins);
  final target = [
    for (final match in _wordPattern.allMatches(_withoutSoftHyphens(tidied)))
      _canonical(match.group(0)!),
  ];
  if (_aligns(source, target, maxStates)) return TidyCheck.faithful;
  return TidyCheck.rejected(_problemOf(source, target));
}

/// Una palabra de la extracción.
class _SourceWord {
  _SourceWord(this.text, {required this.breaksAfter});

  /// Como se compara ([_canonical]).
  final String text;

  /// Si termina el renglón con un guion: puede seguir en la próxima.
  final bool breaksAfter;

  /// Si es la primera de un renglón de los márgenes, dónde termina ese
  /// renglón —el índice de la palabra que sigue—; si no, `-1`.
  int skipTo = -1;

  /// Si es de un renglón de los márgenes.
  bool removable = false;
}

List<_SourceWord> _sourceWords(String extracted, TidyMargins margins) {
  final text = _withoutSoftHyphens(extracted);
  final words = <_SourceWord>[];
  final lineOf = <int>[];
  final matches = _wordPattern.allMatches(text).toList();
  var line = 0;
  var scanned = 0;
  for (final (index, match) in matches.indexed) {
    line += '\n'.allMatches(text.substring(scanned, match.start)).length;
    scanned = match.start;
    final next = index + 1 < matches.length
        ? matches[index + 1].start
        : text.length;
    final gap = text.substring(match.end, next);
    words.add(
      _SourceWord(
        _canonical(match.group(0)!),
        breaksAfter:
            index + 1 < matches.length &&
            gap.isNotEmpty &&
            _breakHyphens.contains(gap[0]) &&
            gap.substring(1).trim().isEmpty &&
            gap.contains('\n'),
      ),
    );
    lineOf.add(line);
  }

  // Los renglones de los márgenes: cada uno, de su primera palabra a la
  // última, se puede saltear entero.
  final lines = text.split('\n');
  var start = 0;
  while (start < words.length) {
    var end = start;
    while (end < words.length && lineOf[end] == lineOf[start]) {
      end++;
    }
    if (margins.contains(lines[lineOf[start]])) {
      words[start].skipTo = end;
      for (var i = start; i < end; i++) {
        words[i].removable = true;
      }
    }
    start = end;
  }
  return words;
}

/// Si [target] es [source] con lo único que se permite cambiar: unir lo
/// partido con guion y saltear renglones de los márgenes enteros.
///
/// `reach[i]` son las posiciones de [target] a las que se llega habiendo
/// leído las primeras `i` palabras de la extracción. Cada paso avanza en la
/// extracción, así que alcanza con recorrerla una vez.
bool _aligns(List<_SourceWord> source, List<String> target, int maxStates) {
  final n = source.length;
  final m = target.length;
  final reach = List<Set<int>?>.filled(n + 1, null);
  reach[0] = {0};
  var states = 0;
  void add(int i, int j) => (reach[i] ??= <int>{}).add(j);

  for (var i = 0; i < n; i++) {
    final positions = reach[i];
    if (positions == null) continue;
    final word = source[i];
    for (final j in positions) {
      if (++states > maxStates) return false;
      if (j < m && word.text == target[j]) add(i + 1, j + 1);
      // «pala-» + «bra» = «palabra», y lo que siga partido.
      if (word.breaksAfter && j < m) {
        final joined = StringBuffer(word.text);
        for (var k = i; source[k].breaksAfter && k + 1 < n; k++) {
          joined.write(source[k + 1].text);
          final sofar = joined.toString();
          if (sofar == target[j]) {
            add(k + 2, j + 1);
            break;
          }
          if (!target[j].startsWith(sofar)) break;
        }
      }
      if (word.skipTo > i) add(word.skipTo, j);
    }
    reach[i] = null;
  }
  return reach[n]?.contains(m) ?? false;
}

/// Por qué [target] no es fiel a [source]: se cuentan las palabras de más y
/// las que faltan, sin mirar el orden; si no sobra ni falta ninguna, es el
/// orden.
TidyProblem _problemOf(List<_SourceWord> source, List<String> target) {
  if (target.isEmpty) return TidyProblem.missing;

  // Lo que la extracción ofrece: cada palabra, y cada una partida con guion
  // también entera.
  final offered = <String, int>{};
  void offer(String word) => offered[word] = (offered[word] ?? 0) + 1;
  for (final (i, word) in source.indexed) {
    offer(word.text);
    if (word.breaksAfter && i + 1 < source.length) {
      offer(word.text + source[i + 1].text);
    }
  }
  final written = <String, int>{};
  var extra = 0;
  for (final word in target) {
    written[word] = (written[word] ?? 0) + 1;
    final left = offered[word] ?? 0;
    if (left == 0) {
      extra++;
    } else {
      offered[word] = left - 1;
    }
  }
  if (extra * 2 > target.length) return TidyProblem.rewritten;
  if (extra > 0) return TidyProblem.invented;

  // Lo que la IA tenía que dejar: todo menos los márgenes. Una palabra
  // partida está si está entera o en sus dos pedazos.
  var missing = 0;
  bool take(String word) {
    final left = written[word] ?? 0;
    if (left == 0) return false;
    written[word] = left - 1;
    return true;
  }

  for (var i = 0; i < source.length; i++) {
    final word = source[i];
    if (word.breaksAfter &&
        i + 1 < source.length &&
        take(word.text + source[i + 1].text)) {
      i++;
      continue;
    }
    if (!take(word.text) && !word.removable) missing++;
  }
  return missing > 0 ? TidyProblem.missing : TidyProblem.reordered;
}

String _withoutSoftHyphens(String text) => text.replaceAll('\u00AD', '');

/// Una palabra como se compara: en minúsculas, con cada acento compuesto con
/// su letra y cada ligadura en sus letras.
String _canonical(String word) {
  final lower = word.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    if (_ligatures[char] case final letters?) {
      out.write(letters);
      continue;
    }
    if (rune >= 0x300 && rune <= 0x36F) {
      final text = out.toString();
      if (text.isNotEmpty) {
        final composed = _composed[text[text.length - 1] + char];
        if (composed != null) {
          out
            ..clear()
            ..write(text.substring(0, text.length - 1))
            ..write(composed);
          continue;
        }
      }
    }
    out.write(char);
  }
  return out.toString();
}

const _ligatures = {
  '\uFB00': 'ff',
  '\uFB01': 'fi',
  '\uFB02': 'fl',
  '\uFB03': 'ffi',
  '\uFB04': 'ffl',
  '\uFB05': 'st',
  '\uFB06': 'st',
};

/// Las letras con acento del español, el portugués, el francés, el italiano,
/// el catalán y el alemán, en minúscula: la letra y su marca aparte → la
/// letra compuesta.
final Map<String, String> _composed = {
  for (final (mark, bases, composed) in const [
    ('\u0300', 'aeiou', 'àèìòù'),
    ('\u0301', 'aeiouy', 'áéíóúý'),
    ('\u0302', 'aeiou', 'âêîôû'),
    ('\u0303', 'ano', 'ãñõ'),
    ('\u0308', 'aeiouy', 'äëïöüÿ'),
    ('\u030A', 'a', 'å'),
    ('\u0327', 'c', 'ç'),
  ])
    for (var i = 0; i < bases.length; i++) bases[i] + mark: composed[i],
};
