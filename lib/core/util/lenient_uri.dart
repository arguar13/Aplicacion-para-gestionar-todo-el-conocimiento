import 'dart:convert';

/// Decodifica los `%XX` de [text] **sin lanzar nunca**: lo que se puede
/// decodificar se decodifica, y lo que está mal escrito —un `%` sin sus dos
/// cifras, bytes que no son UTF-8— queda como venía.
///
/// Las direcciones que trae una página no las controla quien las lee:
/// Wikipedia tiene enlaces con un `%E3%A` suelto. `Uri.pathSegments` y
/// `Uri.decodeComponent` lanzan una `FormatException` ante eso, y una
/// dirección rota de un enlace sin importancia le costaba a la persona el
/// artículo entero. Para saber cómo se llama un archivo o de qué clase es,
/// con lo que se entienda alcanza.
String decodePercentLenient(String text) {
  if (!text.contains('%')) return text;

  final bytes = <int>[];
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x25 /* % */ && i + 2 < runes.length) {
      final high = _hex(runes[i + 1]);
      final low = _hex(runes[i + 2]);
      if (high != null && low != null) {
        bytes.add(high * 16 + low);
        i += 2;
        continue;
      }
    }
    bytes.addAll(utf8.encode(String.fromCharCode(rune)));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

int? _hex(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
  if (rune >= 0x41 && rune <= 0x46) return rune - 0x41 + 10;
  if (rune >= 0x61 && rune <= 0x66) return rune - 0x61 + 10;
  return null;
}

/// El último tramo no vacío del camino de [url], decodificado con
/// [decodePercentLenient]: el nombre del archivo al que apunta, o `null` si
/// no hay ninguno. Nunca lanza, a diferencia de `Uri.pathSegments`.
String? lastPathSegmentOf(Uri url) {
  final last = url.path.split('/').where((s) => s.isNotEmpty).lastOrNull;
  return last == null ? null : decodePercentLenient(last);
}
