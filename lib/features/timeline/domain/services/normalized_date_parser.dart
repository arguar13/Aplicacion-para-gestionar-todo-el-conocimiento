import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/historical_date_order.dart';
import 'package:sinapsis/features/timeline/domain/services/roman_numerals.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_readings.dart';

/// Una fecha o un rango ya leído: el inicio y, si duró, el fin (F40).
typedef DateSpan = ({HistoricalDate start, HistoricalDate? end});

/// Lee la fecha **normalizada** que devuelve el modelo (F40), con un
/// analizador estricto: `null` ante lo que no sea una fecha exacta del
/// formato, ambiguo o inexistente. Nunca corrige ni adivina: una fecha que no
/// se puede leer se descarta, y un hecho sin fecha no entra en la línea.
///
/// El formato, que es el que se le pide al modelo:
///
/// - un año: `1859`, `44 a.C.` (o `44 BC`, `476 d.C.`, `AD 476`);
/// - un mes o un día: `1809-02` y `1809-02-12`, con la era si es a.C.;
/// - un siglo: `s. XIX`, `s. V a.C.` (o `siglo XIX`);
/// - una década: `década 1920` (o `1920s`), solo de la era común;
/// - aproximada: `c. 1500` (o `ca.`, `circa`) antes de cualquiera de las
///   anteriores;
/// - un rango: `1914..1918`, cada extremo con su propia era si hace falta.
///
/// **No se lee** un año con signo (`-43`): no dice si cuenta como año
/// astronómico —44 a.C.— o como «43 antes de Cristo», un año de diferencia en
/// una fecha que el modelo casi seguro escribió mal. Tampoco un rango al
/// revés o de un solo punto (`1918..1914`, `1914..1914`), ni la década de un
/// año a.C.
DateSpan? parseNormalizedDate(String text) {
  final halves = text.split(_rangeSeparator);
  if (halves.length > 2) return null;
  final start = _parseSingle(halves[0]);
  if (start == null) return null;
  if (halves.length == 1) return (start: start, end: null);
  final end = _parseSingle(halves[1]);
  if (end == null || end.compareStart(start) <= 0) return null;
  return (start: start, end: end);
}

/// Los dos puntos que separan los extremos de un rango. Si hay más seguidos
/// —el punto final de «a.C.» y los dos del rango—, son los últimos.
final _rangeSeparator = RegExp(r'\.\.(?!\.)');

HistoricalDate? _parseSingle(String raw) {
  var text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final circaMatch = _circaPrefix.firstMatch(text);
  final circa = circaMatch != null;
  if (circa) text = text.substring(circaMatch.end);

  final century = _century.firstMatch(text);
  if (century != null) {
    final marker = century.namedGroup('era');
    final bce = marker == null ? false : isBceMarker(marker);
    final number = parseRoman(century.namedGroup('roman')!);
    // «s.» es una abreviatura y se escribe en mayúsculas; en minúsculas, una
    // inicial suelta («s. v») no pasa por siglo.
    final roman = century.namedGroup('roman')!;
    final lowercaseInitial =
        century.namedGroup('word')!.toLowerCase() == 's.' &&
        roman != roman.toUpperCase();
    if (bce == null || number == null || lowercaseInitial) return null;
    return readCentury(number, bce: bce, circa: circa);
  }

  final decade = _decade.firstMatch(text);
  if (decade != null) {
    final year = decade.namedGroup('year') ?? decade.namedGroup('year2')!;
    return readDecade(int.parse(year), circa: circa);
  }

  final prefixed = _eraPrefixedYear.firstMatch(text);
  if (prefixed != null) {
    return readYear(int.parse(prefixed.namedGroup('year')!), circa: circa);
  }

  final numeric = _numericDate.firstMatch(text);
  if (numeric == null) return null;
  final marker = numeric.namedGroup('era');
  final bce = marker == null ? false : isBceMarker(marker);
  if (bce == null) return null;
  final year = int.parse(numeric.namedGroup('year')!);
  final monthText = numeric.namedGroup('month');
  if (monthText == null) return readYear(year, bce: bce, circa: circa);
  final dayText = numeric.namedGroup('day');
  return readDate(
    year,
    month: int.parse(monthText),
    day: dayText == null ? null : int.parse(dayText),
    bce: bce,
    circa: circa,
  );
}

final _circaPrefix = RegExp(r'^(?:circa|ca\.|c\.)\s*', caseSensitive: false);

/// `s. XIX`, `siglo XIX`, con la era si es a.C.
final _century = RegExp(
  r'^(?<word>s\.|siglo)\s*(?<roman>[IVXLCDMivxlcdm]+)'
  '(?: (?<era>$eraMarkerPattern))?\$',
  caseSensitive: false,
);

/// `década 1920`, `década de 1920` y `1920s`.
final _decade = RegExp(
  r'^(?:d[eé]cada(?: de(?:l)?)? (?<year>\d{2,4})|(?<year2>\d{2,4})s)$',
  caseSensitive: false,
);

/// `AD 476`, `A.D. 476`.
final _eraPrefixedYear = RegExp(r'^A\.?D\.? (?<year>\d{1,4})$');

/// `1859`, `44 a.C.`, `1809-02`, `1809-02-12`.
final _numericDate = RegExp(
  r'^(?<year>\d{1,4})(?:-(?<month>\d{1,2})(?:-(?<day>\d{1,2}))?)?'
  '(?: ?(?<era>$eraMarkerPattern))?\$',
);
