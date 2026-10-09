/// La búsqueda de texto de «Mis tarjetas» (F31, ola 2, decisión 72).
///
/// SQLite compara sin distinguir mayúsculas solo las letras ASCII (`LIKE`), y
/// no sabe de acentos: buscar «roman» no encontraría «Románico», ni «alvaro»
/// a «Álvaro». Se resuelve en el patrón y no en la base —sin funciones propias
/// ni una columna normalizada, que en la web no existen—: cada letra del texto
/// buscado se vuelve una CLASE de `GLOB` con todas sus formas (`a` →
/// `[aAáÁàÀäÄâÂãÃåÅ]`). `GLOB` distingue mayúsculas, pero con la clase da
/// igual.
///
/// La **ñ no es una n** (`año` ≠ `ano`, como en «escribí la respuesta»): es
/// otra letra del castellano y confundirlas mezclaría palabras distintas.
library;

/// Cuántas palabras como mucho se toman de lo que se escribió: cada una es una
/// condición más en la consulta, y a partir de unas cuantas no afinan nada.
const kMaxSearchTerms = 8;

/// Las formas en que puede aparecer cada letra base (en minúscula) dentro de
/// una tarjeta. Una letra que no está acá solo se parea con sus dos
/// mayúsculas/minúsculas.
const _variants = <String, String>{
  'a': 'aAáÁàÀäÄâÂãÃåÅāĀ',
  'e': 'eEéÉèÈëËêÊēĒ',
  'i': 'iIíÍìÌïÏîÎīĪ',
  'o': 'oOóÓòÒöÖôÔõÕōŌ',
  'u': 'uUúÚùÙüÜûÛūŪ',
  'y': 'yYýÝÿŸ',
  'c': 'cCçÇ',
  'ñ': 'ñÑ',
};

/// De cada letra acentuada a su base, para que «á» busque igual que «a».
final Map<String, String> _baseOf = () {
  final map = <String, String>{};
  _variants.forEach((base, forms) {
    for (final form in forms.split('')) {
      map[form] = base;
    }
  });
  return map;
}();

/// Los patrones `GLOB` de [text]: uno por palabra, cada uno `*palabra*`. Una
/// tarjeta coincide si cumple TODOS (las palabras en cualquier orden). Vacío si
/// no hay nada que buscar.
List<String> cardSearchPatterns(String text) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(kMaxSearchTerms);
  return [for (final word in words) '*${_glob(word)}*'];
}

String _glob(String word) {
  final out = StringBuffer();
  for (final char in word.runes.map(String.fromCharCode)) {
    final base = _baseOf[char] ?? char.toLowerCase();
    final forms = _variants[base];
    if (forms != null) {
      out.write('[$forms]');
    } else if (char == '*' || char == '?' || char == '[') {
      // Los comodines de GLOB, tomados al pie de la letra.
      out.write('[$char]');
    } else {
      final lower = char.toLowerCase();
      final upper = char.toUpperCase();
      out.write(lower == upper ? char : '[$lower$upper]');
    }
  }
  return out.toString();
}
