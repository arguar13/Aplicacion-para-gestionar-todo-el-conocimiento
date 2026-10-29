import 'dart:convert';

/// Texto en UTF-8 leído como Latin-1 —«DeclaraciÃ³n» por «Declaración»—,
/// vuelto a leer como lo que era (F43, M7).
///
/// Pasa cuando algo toma bytes por letras de a uno: los metadatos de un PDF
/// leídos byte a byte, un encabezado HTTP —`dart:io` lee cada byte como una
/// letra de Latin-1—. Cada letra que en UTF-8 ocupa dos bytes se ve como dos:
/// la «ó» (`C3 B3`) como «Ã³», la «ñ» (`C3 B1`) como «Ã±».
///
/// Devuelve el texto arreglado, o `null` si [text] no es eso. Solo lo es si:
///
/// - tiene la firma: una letra de `U+00C2` a `U+00F4` —lo que se ve de un
///   byte que abre una letra de UTF-8— seguida de una de `U+0080` a
///   `U+00BF` —lo que se ve de uno que la sigue—;
/// - todas sus letras caben en un byte (Latin-1): una sola que no, y no
///   salió de leer bytes de a uno;
/// - esos bytes son UTF-8 válido, sin una sola secuencia rota;
/// - y lo que sale no trae caracteres de control.
///
/// Un texto bien leído no pasa esas cuatro: «Declaración» como bytes es
/// `… 63 69 F3 6E`, y `F3 6E` no es UTF-8. Por eso se puede aplicar a
/// cualquier texto sin miedo, y aplicarlo a lo que ya se arregló no hace
/// nada.
///
/// Si se leyó mal dos veces seguidas —lo ya roto, vuelto a guardar en UTF-8 y
/// vuelto a leer como Latin-1—, se deshacen las dos.
String? repairUtf8Mojibake(String text) {
  var current = text;
  // Tres vueltas alcanzan para cualquier cosa leída mal de verdad, y ponen
  // un techo.
  for (var round = 0; round < 3; round++) {
    final next = _repairOnce(current);
    if (next == null) break;
    current = next;
  }
  return identical(current, text) ? null : current;
}

/// [text] arreglado si es UTF-8 leído como Latin-1, o el mismo [text] si no.
String withUtf8MojibakeRepaired(String text) =>
    repairUtf8Mojibake(text) ?? text;

/// Si [text] tiene la firma de UTF-8 leído como Latin-1. No dice si se puede
/// arreglar: eso lo dice [repairUtf8Mojibake].
bool hasUtf8MojibakeSignature(String text) => _signature.hasMatch(text);

/// Una letra que abre una secuencia de UTF-8 de dos a cuatro bytes, seguida
/// de una que la continúa, vistas como Latin-1.
final _signature = RegExp('[Â-ô][\u0080-¿]');

/// Lo que no puede salir de un texto de verdad: los controles de C0 (menos
/// tabulación y saltos de línea), DEL y los de C1.
final _controls = RegExp(
  '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
);

String? _repairOnce(String text) {
  if (!_signature.hasMatch(text)) return null;
  for (final unit in text.codeUnits) {
    if (unit > 0xFF) return null;
  }
  final String decoded;
  try {
    decoded = const Utf8Decoder().convert(latin1.encode(text));
  } on FormatException {
    return null;
  }
  if (decoded == text || _controls.hasMatch(decoded)) return null;
  return decoded;
}
