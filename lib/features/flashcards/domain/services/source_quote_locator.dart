/// Dónde está [quote] dentro de [content], SOLO si está textual (F11); `null`
/// si no.
///
/// La cita que trae un borrador de tarjeta la escribió un modelo de lenguaje, y
/// un modelo chico la cambia sin avisar: una palabra por otra, otra puntuación,
/// un resumen en vez de la frase. Guardarla como el lugar de la fuente del que
/// salió la tarjeta sería inventar un rango: «Ver en la fuente» llevaría a un
/// fragmento que no dice eso. Por eso se comprueba con una búsqueda exacta, y
/// si no coincide la tarjeta se guarda igual, sin fragmento: mejor ninguno que
/// uno equivocado. No se intenta adivinar cuál era —nada de comparaciones
/// aproximadas—.
///
/// Lo único que se tolera es lo que el modelo suele agregar por su cuenta: los
/// espacios de los bordes y un par de comillas que envuelve la frase entera.
/// Si la frase aparece más de una vez, es la primera.
///
/// El rango es `[start, end)` sobre [content] tal cual llega: el mismo texto
/// que usa la lectura, para que el salto caiga en el lugar.
({int start, int end})? locateQuote(String content, String? quote) {
  final unwrapped = _withoutWrappingQuotes(quote?.trim() ?? '');
  if (unwrapped.isEmpty) return null;

  final start = content.indexOf(unwrapped);
  if (start < 0) return null;
  return (start: start, end: start + unwrapped.length);
}

/// Sin las comillas que envuelven la frase entera —`"…"`, `“…”`, `«…»`—: una
/// sola vez, y solo si abren y cierran de a pares.
String _withoutWrappingQuotes(String text) {
  if (text.length < 2) return text;
  const pairs = {'"': '"', '“': '”', '«': '»', "'": "'"};
  final closing = pairs[text[0]];
  if (closing != null && text.endsWith(closing)) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}
