/// El número romano canónico que escribe [text] (`XIX` → 19), o `null` si no
/// es uno válido (F40).
///
/// Estricto a propósito: «IIII», «VX», «IC» o «MIM» no se leen como números.
/// Un «s. V» solo es un siglo si el romano es de verdad un romano; lo que se
/// parece pero no lo es —una sigla, una inicial— no tiene que pasar por
/// siglo. Se acepta en mayúsculas o minúsculas, y se comprueba escribiéndolo
/// de vuelta: si el número, escrito en canónico, no da el mismo texto, no era
/// un romano válido.
int? parseRoman(String text) {
  final upper = text.toUpperCase();
  if (upper.isEmpty) return null;
  var total = 0;
  for (var i = 0; i < upper.length; i++) {
    final value = _values[upper[i]];
    if (value == null) return null;
    final next = i + 1 < upper.length ? _values[upper[i + 1]] : null;
    total += next != null && next > value ? -value : value;
  }
  return total > 0 && total < 4000 && romanOf(total) == upper ? total : null;
}

/// [number] (1–3999) en romanos canónicos: `19` → `XIX`.
String romanOf(int number) {
  assert(number > 0 && number < 4000, 'Los romanos van de 1 a 3999.');
  final buffer = StringBuffer();
  var rest = number;
  for (final (value, symbol) in _table) {
    while (rest >= value) {
      buffer.write(symbol);
      rest -= value;
    }
  }
  return buffer.toString();
}

const _values = {
  'I': 1,
  'V': 5,
  'X': 10,
  'L': 50,
  'C': 100,
  'D': 500,
  'M': 1000,
};

const _table = [
  (1000, 'M'),
  (900, 'CM'),
  (500, 'D'),
  (400, 'CD'),
  (100, 'C'),
  (90, 'XC'),
  (50, 'L'),
  (40, 'XL'),
  (10, 'X'),
  (9, 'IX'),
  (5, 'V'),
  (4, 'IV'),
  (1, 'I'),
];
