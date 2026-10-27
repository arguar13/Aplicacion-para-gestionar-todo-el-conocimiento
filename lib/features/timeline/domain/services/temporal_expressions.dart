import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/historical_date_order.dart';
import 'package:sinapsis/features/timeline/domain/services/roman_numerals.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_readings.dart';

/// Una expresión de tiempo encontrada en un texto, ya leída (F40): el tramo
/// `[start, end)` donde está escrita y la fecha —o el rango— que dice.
@immutable
class TemporalExpression {
  const TemporalExpression({
    required this.start,
    required this.end,
    required this.date,
    this.endDate,
  });

  final int start;
  final int end;

  /// La fecha, o el comienzo del rango si [endDate] no es `null`.
  final HistoricalDate date;

  /// El fin de un rango —«de 1914 a 1918»—; `null` si es una sola fecha.
  final HistoricalDate? endDate;

  @override
  bool operator ==(Object other) =>
      other is TemporalExpression &&
      other.start == start &&
      other.end == end &&
      other.date == date &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(start, end, date, endDate);

  @override
  String toString() =>
      'TemporalExpression([$start, $end), ${date.label}'
      '${endDate == null ? '' : ' – ${endDate!.label}'})';
}

/// Las expresiones de tiempo de [text], en castellano y en inglés, en orden y
/// sin pisarse (F40): el primer tiempo del detector de fechas, rápido y sin IA.
/// Marca dónde puede haber un hecho fechado; qué pasó ahí lo cuenta el modelo.
///
/// Lo que se reconoce, con su lectura:
///
/// - **años**: «en 1859», «año 476», «1859», «476 d.C.», «44 a.C.»,
///   «44 BC», «AD 476»;
/// - **meses y días**: «12 de febrero de 1809», «February 12, 1809»,
///   «12th of February 1809», «febrero de 1809», «March 1809»;
/// - **siglos**: «siglo XIX», «s. XV», «siglo V a.C.», «19th century»,
///   «nineteenth century», «XIX century»;
/// - **décadas**: «la década de 1920», «los años 1920», «1920s» y, con un año
///   cerca que diga el siglo, «los años 20», «los años veinte»,
///   «the twenties»;
/// - **aproximadas**: «hacia 1500», «c. 1500», «circa», «alrededor de»,
///   «around», «about»;
/// - **rangos**: «1914–1918», «1914-18», «de 1914 a 1918», «entre 1914 y
///   1918», «from 1914 to 1918», «siglos XV–XVII».
///
/// **Sin año, no se toma** (decisión D): «el 12 de febrero», «el martes
/// siguiente». Y se cuida de no tomar por año lo que es otro número: las
/// cantidades («1500 soldados», «3.000»), las páginas y capítulos, los
/// teléfonos y los ISBN, las horas, los porcentajes y las fechas numéricas
/// («12/02/1809»). Un número de tres cifras solo es un año si lo dice la
/// palabra de al lado —«en 476», «año 476»— o su era; uno de cuatro, entre
/// 1000 y 2099.
///
/// Si dos lecturas se pisan, gana la más larga: «de 1914 a 1918» es un rango,
/// no tres fechas.
List<TemporalExpression> findTemporalExpressions(String text) {
  final candidates = <_Candidate>[
    ..._eraYears(text),
    ..._prefixedEraYears(text),
    ..._namedYears(text),
    ..._bareYears(text),
    ..._spanishFullDates(text),
    ..._englishMonthDayYears(text),
    ..._englishDayMonthYears(text),
    ..._monthYears(text),
    ..._spanishCenturies(text),
    ..._englishCenturies(text),
    ..._decades(text),
    ..._yearRanges(text),
  ];

  final picked = _pickLongest(candidates);
  final resolved = _resolveShortDecades(picked);
  return _withApproximation(text, resolved);
}

// ---------------------------------------------------------------------------
// Los patrones
// ---------------------------------------------------------------------------

const _era = eraMarkerPattern;

/// Entre letras o números no empieza ni termina nada.
const _left = r'(?<![\p{L}\p{N}])';
const _right = r'(?![\p{L}\p{N}])';

/// Para un número suelto: no pegado a letras ni a otro número por un
/// separador —`1.500`, `10:30`, `12/02`, un ISBN con guiones, un decimal—, ni
/// detrás de una moneda o un `#`; ni delante de un `%`.
const _numLeft =
    r'(?<![\p{L}\p{N}])(?<!\p{N}[.,:/\u2010-\u2015\u2212-])(?<![$€£#№])';
const _numRight =
    r'(?![\p{L}\p{N}])(?![.,:/\u2010-\u2015\u2212-]\p{N})(?!\s?[%‰])';

/// Los guiones y rayas: `-`, `‐`, `‑`, `‒`, `–`, `—`, `―` y el signo menos.
const _dash = r'[\u2010-\u2015\u2212-]';

/// Arma una expresión regular con Unicode (`\p{L}`) de sus [parts].
RegExp _regex(List<String> parts, {bool caseSensitive = true}) =>
    RegExp(parts.join(), unicode: true, caseSensitive: caseSensitive);

/// Una era opcional detrás de un número, en el grupo [name].
String _optionalEra(String name) => '(?:\\s*(?<$name>$_era))?';

// ---------------------------------------------------------------------------
// Candidatos
// ---------------------------------------------------------------------------

class _Candidate {
  _Candidate(this.start, this.end, {this.date, this.endDate, this.shortDecade});

  final int start;
  final int end;

  /// `null` solo en una década de dos cifras que espera su siglo.
  final HistoricalDate? date;
  final HistoricalDate? endDate;

  /// «los años 20»: el 20, a la espera de un año cerca que diga el siglo.
  final int? shortDecade;

  int get length => end - start;
}

_Candidate? _of(Match m, HistoricalDate? date, [HistoricalDate? endDate]) =>
    date == null
    ? null
    : _Candidate(m.start, m.end, date: date, endDate: endDate);

// --- Años ------------------------------------------------------------------

/// `44 a.C.`, `476 d.C.`, `44 BC`, `476 AD`: con la era, cualquier número de
/// una a cuatro cifras es un año.
final _eraYear = _regex([
  _numLeft,
  r'(?<n>\d{1,4})\s*(?<era>',
  _era,
  ')',
  _numRight,
]);

Iterable<_Candidate> _eraYears(String text) sync* {
  for (final m in _eraYear.allMatches(text)) {
    final bce = isBceMarker(m.namedGroup('era')!);
    if (bce == null) continue;
    final candidate = _of(m, readYear(int.parse(m.namedGroup('n')!), bce: bce));
    if (candidate != null) yield candidate;
  }
}

/// `AD 476`, `A.D. 476`.
final _prefixedEraYear = _regex([
  _left,
  r'A\.?D\.?\s+(?<n>\d{1,4})',
  _numRight,
]);

Iterable<_Candidate> _prefixedEraYears(String text) sync* {
  for (final m in _prefixedEraYear.allMatches(text)) {
    final candidate = _of(m, readYear(int.parse(m.namedGroup('n')!)));
    if (candidate != null) yield candidate;
  }
}

/// `año 476`, `en el año 1000`, `in the year 476`, `year 44 BC`: la palabra
/// dice que es un año.
final _namedYear = _regex([
  _left,
  r'(?:[Aa]ño|[Yy]ear)\s+(?<n>\d{1,4})',
  _optionalEra('era'),
  _numRight,
]);

Iterable<_Candidate> _namedYears(String text) sync* {
  for (final m in _namedYear.allMatches(text)) {
    final digits = m.namedGroup('n')!;
    final marker = m.namedGroup('era');
    final bce = marker == null ? false : isBceMarker(marker);
    if (bce == null) continue;
    // Sin era, «año 3» no es un año: «el año 3 de su reinado» o «el año 20
    // del plan». Con tres cifras o más sí.
    if (marker == null &&
        (digits.length < 3 || _isQuantity(text, m.end, countedThings: false))) {
      continue;
    }
    final candidate = _of(m, readYear(int.parse(digits), bce: bce));
    if (candidate != null) yield candidate;
  }
}

/// Un número suelto de tres o cuatro cifras.
final _bareNumber = _regex([_numLeft, r'(?<n>\d{3,4})', _numRight]);

Iterable<_Candidate> _bareYears(String text) sync* {
  for (final m in _bareNumber.allMatches(text)) {
    final digits = m.namedGroup('n')!;
    final value = int.parse(digits);
    final afterPreposition = _timePrepositions.contains(
      _wordBefore(text, m.start),
    );
    final plausible = digits.length == 4
        ? value >= 1000 && value <= 2099
        : afterPreposition;
    if (!plausible) continue;
    // Después de «en» o «in», el año gana a lo contado: «In 1914 people…».
    if (_isQuantity(text, m.end, countedThings: !afterPreposition) ||
        _isNotAYearBefore(text, m.start)) {
      continue;
    }
    final candidate = _of(m, readYear(value));
    if (candidate != null) yield candidate;
  }
}

// --- Meses y días ----------------------------------------------------------

/// `12 de febrero de 1809`, `1º de mayo de 1886`, `15 de marzo de 44 a.C.`.
final _spanishFullDate = _regex([
  _left,
  r'(?<day>\d{1,2})(?:\.?[º°])?\s+[Dd]e\s+(?<month>',
  monthNamesPattern,
  r')(?:\s*,\s*|\s+[Dd]el?\s+)(?<year>\d{1,4})',
  _optionalEra('era'),
  _numRight,
]);

Iterable<_Candidate> _spanishFullDates(String text) sync* {
  for (final m in _spanishFullDate.allMatches(text)) {
    final candidate = _fullDate(m);
    if (candidate != null) yield candidate;
  }
}

/// `February 12, 1809`, `March 15 44 BC`.
final _monthDayYear = _regex([
  _left,
  '(?<month>$monthNamesPattern)',
  r'\s+(?<day>\d{1,2})(?:st|nd|rd|th)?(?:,\s*|\s+)(?<year>\d{1,4})',
  _optionalEra('era'),
  _numRight,
]);

Iterable<_Candidate> _englishMonthDayYears(String text) sync* {
  for (final m in _monthDayYear.allMatches(text)) {
    final candidate = _fullDate(m);
    if (candidate != null) yield candidate;
  }
}

/// `12 February 1809`, `12th of February, 1809`.
final _dayMonthYear = _regex([
  _left,
  r'(?<day>\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?',
  '(?<month>$monthNamesPattern)',
  r'(?:,\s*|\s+)(?<year>\d{1,4})',
  _optionalEra('era'),
  _numRight,
]);

Iterable<_Candidate> _englishDayMonthYears(String text) sync* {
  for (final m in _dayMonthYear.allMatches(text)) {
    final candidate = _fullDate(m);
    if (candidate != null) yield candidate;
  }
}

/// Un día con mes y año ya separados en [m]. El año tiene que ser un año:
/// con era cualquiera; sin ella, de tres o cuatro cifras.
_Candidate? _fullDate(RegExpMatch m) {
  final year = _yearOfMonthContext(m, minDigitsWithoutEra: 3);
  if (year == null) return null;
  final month = monthOfName(m.namedGroup('month')!);
  if (month == null) return null;
  return _of(
    m,
    readDate(
      year.value,
      month: month,
      day: int.parse(m.namedGroup('day')!),
      bce: year.bce,
    ),
  );
}

/// `febrero de 1809`, `March 1809`, `en mayo del 44 a.C.`, `May of 1809`.
final _monthYear = _regex([
  _left,
  '(?<month>$monthNamesPattern)',
  r'(?:\s+(?<de>[Dd]el?|of)\s+|\s*,\s*|\s+)(?<year>\d{1,4})',
  _optionalEra('era'),
  _numRight,
]);

Iterable<_Candidate> _monthYears(String text) sync* {
  for (final m in _monthYear.allMatches(text)) {
    // Sin «de», «May 100» son un mes y una cantidad: hace falta un año de
    // cuatro cifras.
    final year = _yearOfMonthContext(
      m,
      minDigitsWithoutEra: m.namedGroup('de') == null ? 4 : 3,
    );
    if (year == null) continue;
    if (m.namedGroup('era') == null && _isQuantity(text, m.end)) continue;
    final month = monthOfName(m.namedGroup('month')!);
    if (month == null) continue;
    final candidate = _of(m, readDate(year.value, month: month, bce: year.bce));
    if (candidate != null) yield candidate;
  }
}

/// El año de [m] (grupos `year` y `era`) cuando ya hay un mes al lado, que
/// lo vuelve creíble: con era, de una a cuatro cifras; sin ella, de
/// [minDigitsWithoutEra] a cuatro.
({int value, bool bce})? _yearOfMonthContext(
  RegExpMatch m, {
  required int minDigitsWithoutEra,
}) {
  final digits = m.namedGroup('year')!;
  final marker = m.namedGroup('era');
  final bce = marker == null ? false : isBceMarker(marker);
  if (bce == null) return null;
  if (marker == null && digits.length < minDigitsWithoutEra) return null;
  return (value: int.parse(digits), bce: bce);
}

// --- Siglos ----------------------------------------------------------------

const _roman = '[IVXLivxl]+';

/// `siglo XIX`, `s. XV`, `siglo V a.C.`.
final _spanishCentury = _regex([
  _left,
  r'(?<word>[Ss]iglos?|[Ss]\.)\s*(?<roman>',
  _roman,
  ')',
  _optionalEra('era'),
  _right,
]);

/// `siglos XV-XVII`, `del siglo XV al XVII`, `siglos V a III a.C.`.
final _spanishCenturyRange = _regex([
  _left,
  r'[Ss]iglos?\s+(?<r1>',
  _roman,
  r')(?:\s*',
  _dash,
  r'\s*|\s+(?:al|a)\s+)(?<r2>',
  _roman,
  ')',
  _optionalEra('era'),
  _right,
]);

Iterable<_Candidate> _spanishCenturies(String text) sync* {
  for (final m in _spanishCentury.allMatches(text)) {
    final roman = m.namedGroup('roman')!;
    // La abreviatura se escribe en mayúsculas: «s. v» no es un siglo.
    if (m.namedGroup('word')!.endsWith('.') && roman != roman.toUpperCase()) {
      continue;
    }
    final candidate = _centuryOf(m, parseRoman(roman));
    if (candidate != null) yield candidate;
  }
  for (final m in _spanishCenturyRange.allMatches(text)) {
    final candidate = _centuryRange(
      m,
      parseRoman(m.namedGroup('r1')!),
      parseRoman(m.namedGroup('r2')!),
    );
    if (candidate != null) yield candidate;
  }
}

/// `19th century`, `5th century BC`.
final _englishCenturyNumber = _regex([
  _left,
  r'(?<n>\d{1,2})(?:st|nd|rd|th)[\s-]+[Cc]entury',
  _optionalEra('era'),
  _right,
]);

/// `nineteenth century`, `Fifth century`.
final _englishCenturyWord = _regex([
  _left,
  '(?<word>$ordinalWordsPattern)',
  r'[\s-]+[Cc]entury',
  _optionalEra('era'),
  _right,
]);

/// `XIX century`.
final _englishCenturyRoman = _regex([
  _left,
  r'(?<roman>[IVXL]{2,})\s+[Cc]entury',
  _optionalEra('era'),
  _right,
]);

/// `15th-17th centuries`, `15th to 17th century`.
final _englishCenturyRange = _regex([
  _left,
  r'(?<n1>\d{1,2})(?:st|nd|rd|th)(?:\s*',
  _dash,
  r'\s*|\s+to\s+)(?<n2>\d{1,2})(?:st|nd|rd|th)[\s-]+[Cc]entur(?:y|ies)',
  _optionalEra('era'),
  _right,
]);

Iterable<_Candidate> _englishCenturies(String text) sync* {
  for (final m in _englishCenturyNumber.allMatches(text)) {
    final candidate = _centuryOf(m, int.parse(m.namedGroup('n')!));
    if (candidate != null) yield candidate;
  }
  for (final m in _englishCenturyWord.allMatches(text)) {
    final candidate = _centuryOf(
      m,
      centuryOfOrdinalWord(m.namedGroup('word')!),
    );
    if (candidate != null) yield candidate;
  }
  for (final m in _englishCenturyRoman.allMatches(text)) {
    final candidate = _centuryOf(m, parseRoman(m.namedGroup('roman')!));
    if (candidate != null) yield candidate;
  }
  for (final m in _englishCenturyRange.allMatches(text)) {
    final candidate = _centuryRange(
      m,
      int.parse(m.namedGroup('n1')!),
      int.parse(m.namedGroup('n2')!),
    );
    if (candidate != null) yield candidate;
  }
}

_Candidate? _centuryOf(RegExpMatch m, int? number) {
  final marker = m.namedGroup('era');
  final bce = marker == null ? false : isBceMarker(marker);
  if (bce == null || number == null) return null;
  return _of(m, readCentury(number, bce: bce));
}

/// Un rango de siglos con su era compartida: «siglos V–III a.C.».
_Candidate? _centuryRange(RegExpMatch m, int? first, int? last) {
  final marker = m.namedGroup('era');
  final bce = marker == null ? false : isBceMarker(marker);
  if (bce == null || first == null || last == null) return null;
  final start = readCentury(first, bce: bce);
  final end = readCentury(last, bce: bce);
  if (start == null || end == null || end.compareStart(start) <= 0) {
    return null;
  }
  return _of(m, start, end);
}

// --- Décadas ---------------------------------------------------------------

/// `1920s`, `1920's`: una década de cuatro cifras. Las de siglo entero
/// —`1900s`, `1500s`— se pueden leer como década o como siglo, y no se
/// toman.
final _decadeWithS = _regex([_numLeft, r"(?<n>\d{4})['’]?s", _right]);

/// `la década de 1920`, `década del 90`, `década de los 1920`.
final _spanishDecade = _regex([
  _left,
  r'(?:[Ll]a\s+)?[Dd][eé]cada\s+(?:de(?:l)?\s+)?(?:los\s+)?(?<n>\d{2,4})s?',
  _numRight,
]);

/// `los años 1920`, `los años 20`, `los años '20`.
final _spanishYears = _regex([
  _left,
  r"[Ll]os\s+años\s+['’]?(?<n>\d{2}|\d{4})s?",
  _numRight,
]);

/// `los años veinte`.
final _spanishDecadeWord = _regex([
  _left,
  r'[Ll]os\s+años\s+(?<word>veinte|treinta|cuarenta|cincuenta|sesenta|',
  'setenta|ochenta|noventa)',
  _right,
]);

/// `the 20s`, `the '20s`.
final _englishDecadeShort = _regex([
  _left,
  r"[Tt]he\s+['’]?(?<n>\d{2})s",
  _right,
]);

/// `the twenties`.
final _englishDecadeWord = _regex([
  _left,
  r'[Tt]he\s+(?<word>twenties|thirties|forties|fifties|sixties|',
  'seventies|eighties|nineties)',
  _right,
]);

const _decadeWords = {
  'veinte': 20,
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'sesenta': 60,
  'setenta': 70,
  'ochenta': 80,
  'noventa': 90,
  'twenties': 20,
  'thirties': 30,
  'forties': 40,
  'fifties': 50,
  'sixties': 60,
  'seventies': 70,
  'eighties': 80,
  'nineties': 90,
};

Iterable<_Candidate> _decades(String text) sync* {
  for (final m in _decadeWithS.allMatches(text)) {
    final year = int.parse(m.namedGroup('n')!);
    if (year % 100 == 0) continue;
    final candidate = _of(m, readDecade(year));
    if (candidate != null) yield candidate;
  }
  for (final pattern in [_spanishDecade, _spanishYears]) {
    for (final m in pattern.allMatches(text)) {
      final digits = m.namedGroup('n')!;
      final value = int.parse(digits);
      if (digits.length == 4) {
        final candidate = _of(m, readDecade(value));
        if (candidate != null) yield candidate;
      } else if (digits.length == 2) {
        final short = _shortDecade(m, value);
        if (short != null) yield short;
      }
    }
  }
  for (final pattern in [_spanishDecadeWord, _englishDecadeWord]) {
    for (final m in pattern.allMatches(text)) {
      final short = _shortDecade(m, _decadeWords[m.namedGroup('word')!]!);
      if (short != null) yield short;
    }
  }
  for (final m in _englishDecadeShort.allMatches(text)) {
    final short = _shortDecade(m, int.parse(m.namedGroup('n')!));
    if (short != null) yield short;
  }
}

/// «Los años 20», sin su siglo. Que sea una década —de diez en diez— lo
/// comprueba `readDecade` al ponerle el siglo; el 0 («los años 00») no se
/// toma, porque con el siglo puesto sería una década válida que nadie dijo.
_Candidate? _shortDecade(Match m, int value) =>
    value > 0 ? _Candidate(m.start, m.end, shortDecade: value) : null;

/// Hasta qué distancia, en caracteres, un año dice el siglo de «los años 20».
const _centuryContextChars = 1500;

/// Pone el siglo a «los años 20» con el año más cercano del texto, entre los
/// de 1000 a 1999 —con uno del 2000 en adelante, «los años 90» casi siempre
/// son los del siglo anterior—. Sin un año cerca no se sabe de qué siglo, y
/// no se toma.
///
/// `picked` viene en orden y sin solapes, así que los años más cercanos a una
/// década son a lo sumo dos: el último que termina antes y el primero que
/// empieza después. Se recorre una sola vez —un libro que nombra miles de
/// décadas no compara cada una con todos sus años—; a igual distancia gana el
/// de antes.
List<_Candidate> _resolveShortDecades(List<_Candidate> picked) {
  final anchors = [
    for (final c in picked)
      if (c.shortDecade == null &&
          c.date != null &&
          !c.date!.isBce &&
          c.date!.year >= 1000 &&
          c.date!.year < 2000)
        c,
  ];
  final resolved = <_Candidate>[];
  var after = 0;
  for (final c in picked) {
    final short = c.shortDecade;
    if (short == null) {
      resolved.add(c);
      continue;
    }
    while (after < anchors.length && anchors[after].start < c.end) {
      after++;
    }
    _Candidate? nearest;
    var nearestDistance = _centuryContextChars + 1;
    if (after > 0) {
      nearest = anchors[after - 1];
      nearestDistance = c.start - nearest.end;
    }
    if (after < anchors.length &&
        anchors[after].start - c.end < nearestDistance) {
      nearest = anchors[after];
      nearestDistance = nearest.start - c.end;
    }
    if (nearest == null || nearestDistance > _centuryContextChars) continue;
    final century = nearest.date!.year ~/ 100 * 100;
    final date = readDecade(century + short);
    if (date != null) {
      resolved.add(_Candidate(c.start, c.end, date: date));
    }
  }
  return resolved;
}

// --- Rangos de años --------------------------------------------------------

/// `1914–1918`, `1914-18`, `(1809-1882)`, `490-479 a.C.`.
final _dashRange = _regex([
  _numLeft,
  r'(?<s>\d{1,4})',
  _optionalEra('se'),
  r'\s*',
  _dash,
  r'\s*(?<e>\d{1,4})',
  _optionalEra('ee'),
  _numRight,
]);

/// `de 1914 a 1918`, `desde 1914 hasta 1918`, `del año 44 al 14 a.C.`,
/// `from 1914 to 1918`.
final _wordRange = _regex([
  _left,
  r'(?:[Dd]esde|[Dd]el|[Dd]e|[Ff]rom)\s+(?:el\s+)?(?:año\s+|years?\s+)?',
  r'(?<s>\d{1,4})',
  _optionalEra('se'),
  r'\s+(?:hasta\s+el\s+año|hasta\s+el|hasta|al|a|to|until|till|through)\s+',
  r'(?:el\s+)?(?:año\s+)?(?<e>\d{1,4})',
  _optionalEra('ee'),
  _numRight,
]);

/// `entre 1914 y 1918`, `entre los años 1914 y 1918`, `between 1914 and 1918`.
final _betweenRange = _regex([
  _left,
  r'(?:[Ee]ntre|[Bb]etween)\s+(?:los\s+años\s+|the\s+years\s+)?(?<s>\d{1,4})',
  _optionalEra('se'),
  r'\s+(?:y|and)\s+(?<e>\d{1,4})',
  _optionalEra('ee'),
  _numRight,
]);

Iterable<_Candidate> _yearRanges(String text) sync* {
  for (final m in _dashRange.allMatches(text)) {
    if (_isNotAYearBefore(text, m.start)) continue;
    final candidate = _yearRange(m, text, allowShortEnd: true);
    if (candidate != null) yield candidate;
  }
  for (final pattern in [_wordRange, _betweenRange]) {
    for (final m in pattern.allMatches(text)) {
      final candidate = _yearRange(m, text, allowShortEnd: false);
      if (candidate != null) yield candidate;
    }
  }
}

/// Un rango de años de [m] (grupos `s`, `e`, `se` y `ee`).
///
/// La era de un extremo vale para el otro si éste no trae la suya —«de 490 a
/// 479 a.C.»—. Sin era en ninguno, los dos tienen que ser años creíbles de
/// cuatro cifras (1000–2099), y el fin puede abreviarse a dos —«1939–45»—.
/// El fin siempre es posterior al inicio.
_Candidate? _yearRange(
  RegExpMatch m,
  String text, {
  required bool allowShortEnd,
}) {
  final startDigits = m.namedGroup('s')!;
  final endDigits = m.namedGroup('e')!;
  final startMarker = m.namedGroup('se');
  final endMarker = m.namedGroup('ee');
  final startBce = startMarker == null ? null : isBceMarker(startMarker);
  final endBce = endMarker == null ? null : isBceMarker(endMarker);
  if ((startMarker != null && startBce == null) ||
      (endMarker != null && endBce == null)) {
    return null;
  }

  final startValue = int.parse(startDigits);
  var endValue = int.parse(endDigits);
  if (startBce == null && endBce == null) {
    if (allowShortEnd && startDigits.length == 4 && endDigits.length == 2) {
      endValue = startValue ~/ 100 * 100 + endValue;
    } else if (endDigits.length != 4) {
      return null;
    }
    if (startDigits.length != 4) return null;
    if (startValue < 1000 || startValue > 2099) return null;
    if (endValue < 1000 || endValue > 2099) return null;
    if (_isQuantity(text, m.end)) return null;
  }

  final start = readYear(startValue, bce: startBce ?? endBce ?? false);
  final end = readYear(endValue, bce: endBce ?? startBce ?? false);
  if (start == null || end == null || end.compareStart(start) <= 0) {
    return null;
  }
  return _of(m, start, end);
}

// ---------------------------------------------------------------------------
// Elegir y completar
// ---------------------------------------------------------------------------

/// De las lecturas que se pisan, la más larga; a igual largo, la primera.
/// Devuelve las elegidas en orden de aparición.
///
/// Se resuelve por grupos de lecturas que se tocan entre sí: dentro de cada
/// uno, que casi siempre es de una o dos, se elige a la más larga. Así un
/// texto de un millón de caracteres no compara cada lectura con todas las
/// demás.
List<_Candidate> _pickLongest(List<_Candidate> candidates) {
  final ordered = [...candidates]
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.length.compareTo(a.length);
    });

  final picked = <_Candidate>[];
  var cluster = <_Candidate>[];
  var clusterEnd = 0;

  void closeCluster() {
    final byLength = [...cluster]
      ..sort((a, b) {
        final byLength = b.length.compareTo(a.length);
        return byLength != 0 ? byLength : a.start.compareTo(b.start);
      });
    final chosen = <_Candidate>[];
    for (final c in byLength) {
      if (chosen.every((p) => c.end <= p.start || c.start >= p.end)) {
        chosen.add(c);
      }
    }
    picked.addAll(chosen);
    cluster = [];
  }

  for (final c in ordered) {
    if (cluster.isNotEmpty && c.start >= clusterEnd) closeCluster();
    cluster.add(c);
    clusterEnd = math.max(clusterEnd, c.end);
  }
  closeCluster();
  return picked..sort((a, b) => a.start.compareTo(b.start));
}

/// Cuánto antes de una fecha se busca la palabra que la hace aproximada.
const _approximationLookback = 40;

/// «hacia», «c.», «circa», «alrededor de», «around», «about»…, y los
/// artículos que los separan de la fecha, pegados al final del texto que
/// precede a la expresión.
final _approximation = _regex([
  _left,
  r'(?:hacia|circa|c\.|ca\.|aprox\.|aproximadamente|alrededor\s+de(?:l)?|',
  r'cerca\s+de(?:l)?|en\s+torno\s+a(?:l)?|around|about|approximately|',
  r'approx\.|roughly)\s*(?:(?:el|la|los|las|the|año|year)\s+)*$',
], caseSensitive: false);

/// Convierte en aproximadas, y agranda hasta la palabra, las expresiones
/// precedidas de un «hacia» o un «circa».
List<TemporalExpression> _withApproximation(
  String text,
  List<_Candidate> candidates,
) {
  final expressions = <TemporalExpression>[];
  var previousEnd = 0;
  for (final c in candidates) {
    final from = math.max(previousEnd, c.start - _approximationLookback);
    final prefix = from < c.start
        ? _approximation.firstMatch(text.substring(from, c.start))
        : null;
    final end = c.endDate;
    expressions.add(
      TemporalExpression(
        start: prefix == null ? c.start : from + prefix.start,
        end: c.end,
        date: prefix == null ? c.date! : c.date!.copyWith(isCirca: true),
        endDate: prefix == null || end == null
            ? end
            : end.copyWith(isCirca: true),
      ),
    );
    previousEnd = c.end;
  }
  return expressions;
}

// ---------------------------------------------------------------------------
// Lo que no es un año
// ---------------------------------------------------------------------------

/// Las palabras de [text], separadas por espacios, como un conjunto.
Set<String> _words(String text) => text.split(' ').toSet();

/// Las preposiciones que hacen creíble un año de tres cifras: «en 476».
final Set<String> _timePrepositions = _words(
  'en desde hasta hacia circa ca c in since until around',
);

/// La palabra que va pegada antes de [offset], sin acentos ni mayúsculas, o
/// `''`.
String _wordBefore(String text, int offset) => _wordsBefore(text, offset).last;

/// Las dos palabras anteriores a [offset], la última al final: `['', '']`
/// si lo que hay pegado antes no es una palabra.
List<String> _wordsBefore(String text, int offset) {
  final tail = text.substring(math.max(0, offset - 30), offset);
  final m = _lastWords.firstMatch(tail);
  if (m == null) return const ['', ''];
  return [_fold(m.group(1) ?? ''), _fold(m.group(2)!)];
}

final _lastWords = _regex([r'(?:(\p{L}+)[.\s]+)?(\p{L}+)[.\s]*$']);

/// Lo que va delante de un número que no es un año: una página, un capítulo,
/// una cantidad, un identificador.
final Set<String> _notAYearBefore = _words(
  'pag pags pagina paginas p pp cap capitulo vol volumen fig figura tabla '
  'table page pages chapter art articulo article num numero nro no n º ° isbn '
  'issn ley tel telefono phone ext codigo code id ref unos unas casi nearly '
  'almost over under',
);

const _notAYearAfterTwoWords = {
  'mas de',
  'menos de',
  'more than',
  'less than',
  'fewer than',
};

bool _isNotAYearBefore(String text, int offset) {
  final words = _wordsBefore(text, offset);
  return _notAYearBefore.contains(words.last) ||
      _notAYearAfterTwoWords.contains('${words.first} ${words.last}');
}

/// Si lo que sigue a [offset] es un sustantivo de cantidad —«1500
/// soldados», «2000 euros»—: entonces el número cuenta cosas, no años.
///
/// Una unidad —días, euros, metros— lo descarta siempre. Una cosa contada
/// —soldados, personas— solo si [countedThings]: después de un «en 1914» o un
/// «in 1914» el año gana («In 1914 people began to leave»).
///
/// También si es el primero de dos números que cuentan lo mismo —«entre 1000
/// y 2000 euros», «de 1000 a 1500 soldados»—.
bool _isQuantity(String text, int offset, {bool countedThings = true}) {
  final tail = text.substring(offset, math.min(text.length, offset + 40));
  for (final pattern in [_nextWord, _nextWordAfterRange]) {
    final m = pattern.firstMatch(tail);
    if (m == null) continue;
    final word = _fold(m.group(1)!);
    if (_unitWords.contains(word) ||
        (countedThings && _countedWords.contains(word))) {
      return true;
    }
  }
  return false;
}

/// La palabra que sigue a un número.
final _nextWord = _regex([r'^[ \t\u00a0\u202f]*(\p{L}+)']);

/// La palabra que sigue al segundo número de un rango: «- 1500 kg», «a 1500
/// soldados», «y 2000 euros».
final _nextWordAfterRange = _regex([
  r'^\s*(?:',
  _dash,
  r'|(?:a|al|y|hasta|to|and)\s)\s*\d{1,4}[ \t\u00a0\u202f]+(\p{L}+)',
]);

/// Lo que mide un número: tiempo, dinero, largo, peso, tamaño y escala. Nunca
/// sigue a un año.
final Set<String> _unitWords = {..._unitWordsEs, ..._unitWordsEn};

final Set<String> _unitWordsEs = _words(
  'dias anos meses semanas horas minutos segundos veces euros dolares pesos '
  'libras km kilometros metros kg kilos kilogramos gramos litros millas pies '
  'pulgadas toneladas caracteres bytes mb gb kb hz usd eur pixeles mil '
  'millones',
);

final Set<String> _unitWordsEn = _words(
  'days years months weeks hours minutes seconds times dollars pounds miles '
  'feet inches meters metres kilometers tons million thousand',
);

/// Lo que se cuenta: personas, votos, páginas. Después de un año a veces
/// sigue una oración («En 1914 soldados de toda Europa…»), así que solo
/// descarta cuando nada dice que el número es un año.
final Set<String> _countedWords = _words(
  'persona personas soldado soldados hombre hombres mujer mujeres habitantes '
  'muertos muertes casos votos palabras pagina paginas ejemplares copias '
  'unidades people men women soldiers inhabitants deaths cases votes words '
  'pages units copies',
);

/// [text] en minúscula y sin acentos, para compararlo con las listas.
String _fold(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_unaccented[char] ?? char);
  }
  return buffer.toString();
}

const _unaccented = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'ñ': 'n',
};
