import 'dart:math' as math;

import 'package:sinapsis/features/creations/infographic/domain/infographic_numbers.dart';

/// Cómo se leen los valores de una tabla para ordenarla (F43): los números
/// como números, las fechas como fechas y el texto como lo ordena un
/// diccionario.
abstract final class TableValues {
  /// El número de [cell] —«1.250,5», «40 %», «−12», «3 millones», «US$ 2,5
  /// mil»—, o `null` si no trae ninguno. El separador decimal se deduce como
  /// en las infografías (`InfographicNumbers.parse`): el último de los dos, o
  /// el único si no va seguido de exactamente tres cifras.
  static double? number(String cell) {
    final text = cell.trim().replaceAll('−', '-').replaceAll('–', '-');
    if (text.isEmpty) return null;
    final match = _numberAt.firstMatch(text);
    if (match == null) return null;
    final value = InfographicNumbers.parse(match.group(0));
    if (value == null) return null;
    final after = text.substring(match.end).trimLeft().toLowerCase();
    return value * _scaleOf(after);
  }

  static final _numberAt = RegExp(r'-?\d+(?:[.,]\d+|\s\d{3}(?!\d))*');

  /// La escala de lo que sigue al número: «mil», «millones», «billion».
  static double _scaleOf(String after) {
    final word = RegExp('^[a-záéíóúñ]+').firstMatch(after)?.group(0);
    if (word == null) return 1;
    // «mil millones» es un millar de millones.
    if (word == 'mil' && RegExp(r'^mil\s+mill(ó|o)n').hasMatch(after)) {
      return 1000000000;
    }
    return switch (word) {
      'mil' || 'k' || 'thousand' => 1e3,
      'millón' || 'millon' || 'millones' || 'million' || 'millions' => 1e6,
      'billion' || 'billions' => 1e9,
      'billón' || 'billon' || 'billones' => 1e12,
      _ => 1,
    };
  }

  /// La fecha de [cell] como un número que se ordena —el año, con el mes y el
  /// día como fracción—, o `null` si no es una fecha:
  ///
  /// - «2026-10-29», «29/10/2026», «29-10-2026» (día, mes y año, como se
  ///   escribe en castellano), «10/2026»;
  /// - «29 de octubre de 2026», «octubre de 2026», «October 29, 2026»;
  /// - un año solo, con su era: «1446», «1446 a. C.», «1446 BC», «30 d. C.»;
  /// - un siglo: «siglo XIII», «s. V a. C.».
  static double? date(String cell) {
    final text = cell.trim().toLowerCase();
    if (text.isEmpty) return null;
    final before = _before.hasMatch(text);
    double signed(double year) => before ? -year : year;

    final iso = _iso.firstMatch(text);
    if (iso != null) {
      return _compose(
        signed(double.parse(iso.group(1)!)),
        int.tryParse(iso.group(2) ?? ''),
        int.tryParse(iso.group(3) ?? ''),
      );
    }
    final dmy = _dmy.firstMatch(text);
    if (dmy != null) {
      var day = int.parse(dmy.group(1)!);
      var month = int.parse(dmy.group(2)!);
      // «10/29/2026», como en inglés: el mes primero.
      if (month > 12 && day <= 12) (day, month) = (month, day);
      return _compose(signed(double.parse(dmy.group(3)!)), month, day);
    }
    final my = _my.firstMatch(text);
    if (my != null) {
      return _compose(
        signed(double.parse(my.group(2)!)),
        int.parse(my.group(1)!),
        null,
      );
    }
    final century = _century.firstMatch(text);
    if (century != null) {
      final number =
          _roman(century.group(1)!) ?? int.tryParse(century.group(1)!);
      if (number != null && number > 0) {
        // El medio del siglo: el V a. C. va del 500 al 401.
        return signed((number - 1) * 100 + 50.0);
      }
    }
    final named = _named(text);
    if (named != null) {
      return _compose(signed(named.$1), named.$2, named.$3);
    }
    final year = _year.firstMatch(text);
    if (year != null) return signed(double.parse(year.group(1)!));
    return null;
  }

  static double? _compose(double year, int? month, int? day) {
    if (month != null && (month < 1 || month > 12)) return null;
    if (day != null && (day < 1 || day > 31)) return null;
    // El mes y el día, como fracción del año: también antes de Cristo el 1 de
    // enero va antes que el 31 de diciembre del mismo año.
    return year + ((month ?? 1) - 1) / 12 + ((day ?? 1) - 1) / 372;
  }

  static final _before = RegExp(
    r'\b(a\.?\s?c\.?|a\.?\s?n\.?\s?e\.?|bc|bce|b\.c\.)(?![a-z])',
  );
  static final _iso = RegExp(r'^(\d{3,4})-(\d{1,2})(?:-(\d{1,2}))?\b');
  static final _dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{3,4})\b');
  static final _my = RegExp(r'^(\d{1,2})[/.-](\d{3,4})\b');
  static final _century = RegExp(r'^(?:siglo|s\.)\s*([ivxlc]+|\d{1,2})\b');
  static final _year = RegExp(
    r'^(?:(?:año|year|c\.|ca\.|hacia)\s*)?(\d{1,4})'
    r'(?:\s*(?:a\.?\s?c\.?|d\.?\s?c\.?|a\.?\s?n\.?\s?e\.?|bc|bce|ad|ce|b\.c\.|a\.d\.))?$',
  );

  /// «29 de octubre de 2026», «octubre de 2026», «October 29, 2026»,
  /// «29 October 2026»: el año, el mes y el día.
  static (double, int, int?)? _named(String text) {
    for (final entry in _months.entries) {
      final at = text.indexOf(entry.key);
      if (at < 0) continue;
      final head = text.substring(0, at);
      final tail = text.substring(at + entry.key.length);
      final dayBefore = RegExp(r'(\d{1,2})\s*(?:de\s*)?$').firstMatch(head);
      final dayAfter = RegExp(r'^\s*(\d{1,2})\s*,').firstMatch(tail);
      final year = RegExp(r'(\d{3,4})').firstMatch(tail);
      if (year == null) return null;
      final day = int.tryParse(dayBefore?.group(1) ?? dayAfter?.group(1) ?? '');
      return (double.parse(year.group(1)!), entry.value, day);
    }
    return null;
  }

  static const _months = {
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

  static int? _roman(String text) {
    const values = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100};
    var total = 0;
    for (var i = 0; i < text.length; i++) {
      final value = values[text[i]];
      if (value == null) return null;
      final next = i + 1 < text.length ? values[text[i + 1]] ?? 0 : 0;
      total += value < next ? -value : value;
    }
    return total;
  }
}

/// Cómo ordena un diccionario el texto de una tabla en un idioma (F43): sin
/// mirar mayúsculas ni tildes primero —«ábaco» va con «abeja», no al final—,
/// con los números de adentro como números —«Capítulo 2» antes que
/// «Capítulo 10»— y, en castellano, la «ñ» después de la «n». Los signos no
/// cuentan para el orden (« "Éxodo" » va con «Éxodo»).
///
/// Si dos textos empatan así, va primero el sin tilde y después el que
/// tiene minúscula; y si todavía empatan, son iguales.
class TableCollator {
  TableCollator(String languageCode)
    : _ennie = _ennieLanguages.contains(
        languageCode.split(RegExp('[-_]')).first.toLowerCase(),
      );

  /// Los idiomas donde la «ñ» es una letra aparte, después de la «n».
  static const _ennieLanguages = {'es', 'gl', 'eu', 'ast'};

  final bool _ennie;

  int compare(String a, String b) {
    final primary = _compareKeys(_keys(a), _keys(b));
    if (primary != 0) return primary;
    final accents = _compareAccents(a, b);
    if (accents != 0) return accents;
    final caseOrder = _compareCase(a, b);
    if (caseOrder != 0) return caseOrder;
    return 0;
  }

  /// Lo que se compara primero: cada número de adentro, entero, y cada letra
  /// por su base.
  List<Object> _keys(String text) {
    final keys = <Object>[];
    final digits = StringBuffer();
    void flush() {
      if (digits.isEmpty) return;
      keys.add(BigInt.parse(digits.toString()));
      digits.clear();
    }

    for (final rune in text.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        digits.writeCharCode(rune);
        continue;
      }
      flush();
      final weight = _weight(rune);
      if (weight != null) keys.add(weight);
    }
    flush();
    return keys;
  }

  /// El peso de una letra: su base en minúscula, con la «ñ» justo después de
  /// la «n» si el idioma la tiene; `null` para un signo o un espacio.
  int? _weight(int rune) {
    final lower = String.fromCharCode(rune).toLowerCase();
    final code = lower.runes.first;
    if (code == 0xF1 && _ennie) return 0x6E * 2 + 1; // ñ
    if (code < 0x80) {
      return code >= 0x61 && code <= 0x7A ? code * 2 : null;
    }
    // Signos: los de Latin-1 («¿», «¡», ««»», «°»), la puntuación
    // tipográfica, las flechas y los símbolos, y la de los textos asiáticos.
    if (code < 0xC0 ||
        code == 0xD7 ||
        code == 0xF7 ||
        (code >= 0x2000 && code <= 0x2BFF) ||
        (code >= 0x3000 && code <= 0x303F)) {
      return null;
    }
    return (_bases[code] ?? code) * 2;
  }

  static int _compareKeys(List<Object> a, List<Object> b) {
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final x = a[i];
      final y = b[i];
      // Un número va antes que una letra, como en los diccionarios.
      if (x is BigInt && y is BigInt) {
        final c = x.compareTo(y);
        if (c != 0) return c;
      } else if (x is BigInt) {
        return -1;
      } else if (y is BigInt) {
        return 1;
      } else {
        final c = (x as int).compareTo(y as int);
        if (c != 0) return c;
      }
    }
    return a.length.compareTo(b.length);
  }

  /// Sin tilde antes que con tilde, letra por letra (sin contar los
  /// signos).
  int _compareAccents(String a, String b) {
    final x = _letters(a.toLowerCase());
    final y = _letters(b.toLowerCase());
    final n = math.min(x.length, y.length);
    for (var i = 0; i < n; i++) {
      final ax = _bases.containsKey(x[i]) ? 1 : 0;
      final ay = _bases.containsKey(y[i]) ? 1 : 0;
      if (ax != ay) return ax - ay;
    }
    return 0;
  }

  /// Minúscula antes que mayúscula, letra por letra (sin contar los signos).
  int _compareCase(String a, String b) {
    final x = _letters(a);
    final y = _letters(b);
    final n = math.min(x.length, y.length);
    for (var i = 0; i < n; i++) {
      final cx = String.fromCharCode(x[i]);
      final cy = String.fromCharCode(y[i]);
      final ux = cx != cx.toLowerCase() ? 1 : 0;
      final uy = cy != cy.toLowerCase() ? 1 : 0;
      if (ux != uy) return ux - uy;
    }
    return 0;
  }

  /// Las letras y las cifras de [text], sin los signos ni los espacios.
  List<int> _letters(String text) => [
    for (final rune in text.runes)
      if ((rune >= 0x30 && rune <= 0x39) || _weight(rune) != null) rune,
  ];

  /// Las letras con tilde de las lenguas latinas (en minúscula), a su base.
  static final Map<int, int> _bases = () {
    const groups = {
      'a': 'áàâäãå',
      'e': 'éèêë',
      'i': 'íìîï',
      'o': 'óòôöõ',
      'u': 'úùûü',
      'n': 'ñ',
      'c': 'ç',
      'y': 'ýÿ',
    };
    return {
      for (final entry in groups.entries)
        for (final unit in entry.value.runes) unit: entry.key.runes.first,
    };
  }();
}
