/// Los números de una infografía, tal como los escribe un texto (F43): «40 %»,
/// «3.000.000», «12,5», «1,234.5», «x2», «40 años».
///
/// El material está casi siempre en castellano: el punto separa los miles
/// («1.500» es mil quinientos) y la coma, los decimales. Un texto en inglés
/// («1,234.5») también se entiende, porque se mira cuál de los dos
/// separadores va último.
abstract final class InfographicNumbers {
  static final _number = RegExp(r'-?\d+(?:[.,]\d+|\s\d{3}(?!\d))*');

  /// El primer número de [raw] —un número, o un texto que trae uno—, o null
  /// si no hay ninguno.
  static double? parse(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is! String) return null;
    final match = _number.firstMatch(raw);
    if (match == null) return null;
    // Los espacios de adentro («3 000 000») son separadores de miles.
    final digits = match.group(0)!.replaceAll(RegExp(r'\s'), '');
    final lastDot = digits.lastIndexOf('.');
    final lastComma = digits.lastIndexOf(',');
    String normalized;
    if (lastDot >= 0 && lastComma >= 0) {
      // Los dos: el último es el decimal.
      normalized = lastComma > lastDot
          ? digits.replaceAll('.', '').replaceAll(',', '.')
          : digits.replaceAll(',', '');
    } else if (lastComma >= 0) {
      normalized = _single(digits, ',');
    } else if (lastDot >= 0) {
      normalized = _single(digits, '.');
    } else {
      normalized = digits;
    }
    return double.tryParse(normalized);
  }

  /// Con un solo tipo de separador: si aparece más de una vez, o va seguido
  /// de exactamente tres cifras, son miles; si no, es el decimal.
  static String _single(String digits, String separator) {
    final parts = digits.split(separator);
    final thousands =
        parts.length > 2 || (parts.length == 2 && parts.last.length == 3);
    return thousands ? parts.join() : parts.join('.');
  }

  /// La fracción de [raw] si es un porcentaje («40 %», «12,5%»), entre 0 y
  /// 1; null si no lo es o se pasa de 100.
  static double? percentOf(String raw) {
    if (!raw.contains('%')) return null;
    final number = parse(raw);
    if (number == null || number < 0 || number > 100) return null;
    return number / 100;
  }

  /// [value] escrito como en castellano: «3.000.000», «12,5». Sin decimales
  /// si es entero; con uno o dos si no.
  static String format(double value) {
    final negative = value < 0;
    final abs = value.abs();
    final rounded = (abs * 100).round() / 100;
    final whole = rounded.truncate();
    final cents = ((rounded - whole) * 100).round();
    final groups = <String>[];
    var rest = whole.toString();
    while (rest.length > 3) {
      groups.insert(0, rest.substring(rest.length - 3));
      rest = rest.substring(0, rest.length - 3);
    }
    groups.insert(0, rest);
    var text = groups.join('.');
    if (cents != 0) {
      final decimals = cents.toString().padLeft(2, '0');
      text += ',${decimals.endsWith('0') ? decimals[0] : decimals}';
    }
    return negative ? '-$text' : text;
  }
}
