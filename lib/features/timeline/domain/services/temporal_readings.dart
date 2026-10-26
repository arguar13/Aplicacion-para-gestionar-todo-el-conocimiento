/// Cómo se lee una fecha escrita en un texto o devuelta por el modelo (F40):
/// las reglas de qué es una fecha válida, en un solo lugar para que el
/// detector de expresiones y el analizador estricto no puedan discrepar.
///
/// Cada función devuelve `null` si lo que se le da no es una fecha que
/// exista —un mes 13, un 31 de febrero, el año 0, un siglo 0—, y nunca la
/// «arregla»: una fecha corregida en silencio sería una fecha inventada.
library;

import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';

/// El último año que se lee, de cuatro cifras.
const kMaxReadYear = 9999;

/// El siglo más grande que se lee: el XL. Más allá no hay documento que lo
/// diga, y un romano así de grande casi seguro es otra cosa.
const kMaxReadCentury = 40;

/// El año [year] de la era que diga [bce], o `null` si no existe: no hay
/// año 0, y pasar de [kMaxReadYear] es un número que no es un año.
HistoricalDate? readYear(int year, {bool bce = false, bool circa = false}) {
  if (year < 1 || year > kMaxReadYear) return null;
  return HistoricalDate(
    year: year,
    precision: DatePrecision.year,
    isBce: bce,
    isCirca: circa,
  );
}

/// El mes [month] (1–12) del año [year], o el día [day] de ese mes si se da:
/// `null` si el año, el mes o el día no existen. Los años bisiestos son los
/// del calendario gregoriano proléptico, como en el resto de la app.
HistoricalDate? readDate(
  int year, {
  required int month,
  int? day,
  bool bce = false,
  bool circa = false,
}) {
  if (readYear(year, bce: bce) == null) return null;
  if (month < 1 || month > 12) return null;
  final astronomical = bce ? 1 - year : year;
  if (day != null && (day < 1 || day > daysInMonth(astronomical, month))) {
    return null;
  }
  return HistoricalDate(
    year: year,
    precision: day == null ? DatePrecision.month : DatePrecision.day,
    month: month,
    day: day,
    isBce: bce,
    isCirca: circa,
  );
}

/// El siglo número [century] (el XIX es el 19), o `null` si es el 0 o pasa de
/// [kMaxReadCentury].
///
/// Con la convención de la app, el año de un siglo es su primer año: el siglo
/// XIX d.C. empieza en 1801 y el V a.C. —de 500 a 401 a.C.— en 500 a.C.
HistoricalDate? readCentury(
  int century, {
  bool bce = false,
  bool circa = false,
}) {
  if (century < 1 || century > kMaxReadCentury) return null;
  return HistoricalDate(
    year: bce ? century * 100 : (century - 1) * 100 + 1,
    precision: DatePrecision.century,
    isBce: bce,
    isCirca: circa,
  );
}

/// La década que empieza en [year] (1920 para 1920–1929), o `null` si no es
/// un año de comienzo de década. Solo de la era común: «los 340» a.C.
/// cuenta hacia atrás y se lee de dos maneras, así que no se lee.
HistoricalDate? readDecade(int year, {bool circa = false}) {
  if (year < 10 || year > kMaxReadYear || year % 10 != 0) return null;
  return HistoricalDate(
    year: year,
    precision: DatePrecision.decade,
    isCirca: circa,
  );
}

/// Si [marker] —lo que sigue a un año: «a.C.», «BC», «d. C.», «AD»— es de
/// antes de Cristo (`true`) o de después (`false`); `null` si no es ninguno
/// de los dos.
bool? isBceMarker(String marker) {
  final key = marker
      .toLowerCase()
      .replaceAll(RegExp(r'[.\s]'), '')
      .replaceAll('é', 'e');
  if (_bceMarkers.contains(key)) return true;
  if (_ceMarkers.contains(key)) return false;
  return null;
}

const _bceMarkers = {
  'ac',
  'adec',
  'ajc',
  'bc',
  'bce',
  'antesdecristo',
  'beforechrist',
};

const _ceMarkers = {'dc', 'ddec', 'djc', 'ad', 'ce', 'despuesdecristo'};

/// Cómo se escribe una era después de un año, para buscarla en un texto:
/// «a.C.», «a. C.», «a. de C.», «A.C.», «d.C.», «BC», «B.C.E.», «AD», «CE»,
/// «antes de Cristo». Sin grupos con nombre: quien lo usa le pone el suyo.
///
/// No se acepta «a C» sin punto: es una preposición y una inicial («de 1914 a
/// Churchill»). Y las siglas inglesas van con todos sus puntos o con ninguno
/// —«B.C.», «BC»—, nunca «BC.»: ese punto cierra la oración.
const eraMarkerPattern =
    r'(?:[aA]\.\s?(?:de\s+|J\.\s?)?C\.?|[dD]\.\s?(?:de\s+|J\.\s?)?C\.?'
    r'|aC|dC|B\.C\.E\.|B\.C\.|BCE|BC|A\.D\.|AD|C\.E\.|CE'
    r'|[Aa]ntes\s+de\s+Cristo|[Dd]espu[eé]s\s+de\s+Cristo|[Bb]efore\s+Christ)';

/// El mes (1–12) que nombra [name], en castellano o en inglés, o `null`.
int? monthOfName(String name) => _monthNumbers[name.toLowerCase()];

/// Los nombres de mes para buscar en un texto, con la primera letra en
/// mayúscula o minúscula —«Enero», «enero»—.
final String monthNamesPattern = caseFlexibleAlternation(_monthNumbers.keys);

/// Las palabras de [words] como una alternativa para una expresión regular,
/// con la primera letra de cada una en mayúscula o minúscula: «Fifth» al
/// empezar una oración, «fifth» en el medio. Sin pasar toda la expresión a
/// no distinguir mayúsculas, que dejaría leer «ad» como la era «AD». De las
/// más largas a las más cortas, para que «setiembre» no se corte en otra.
String caseFlexibleAlternation(Iterable<String> words) {
  final sorted = words.toList()..sort((a, b) => b.length.compareTo(a.length));
  final alternatives = [
    for (final word in sorted)
      '[${word[0].toUpperCase()}${word[0]}]${word.substring(1)}',
  ];
  return '(?:${alternatives.join('|')})';
}

const _monthNumbers = {
  'enero': 1,
  'febrero': 2,
  'marzo': 3,
  'abril': 4,
  'mayo': 5,
  'junio': 6,
  'julio': 7,
  'agosto': 8,
  'septiembre': 9,
  'setiembre': 9,
  'octubre': 10,
  'noviembre': 11,
  'diciembre': 12,
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

/// El número de siglo que dice la palabra inglesa [word] («fifth» → 5), o
/// `null`.
int? centuryOfOrdinalWord(String word) {
  final index = _ordinalWords.indexOf(word.toLowerCase());
  return index < 0 ? null : index + 1;
}

/// Las palabras de siglo en inglés, de «first» a «twenty-first», para buscar
/// en un texto.
final String ordinalWordsPattern = caseFlexibleAlternation(_ordinalWords);

const _ordinalWords = [
  'first',
  'second',
  'third',
  'fourth',
  'fifth',
  'sixth',
  'seventh',
  'eighth',
  'ninth',
  'tenth',
  'eleventh',
  'twelfth',
  'thirteenth',
  'fourteenth',
  'fifteenth',
  'sixteenth',
  'seventeenth',
  'eighteenth',
  'nineteenth',
  'twentieth',
  'twenty-first',
];
