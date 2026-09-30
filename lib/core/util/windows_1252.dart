/// [bytes] leídos como Windows-1252: lo que escriben los programas viejos de
/// Windows en español, y lo que un navegador hace con una página que dice
/// ser ISO-8859-1 o no dice nada (F22).
///
/// Es Latin-1 salvo del 0x80 al 0x9F, donde Latin-1 tiene caracteres de
/// control y Windows-1252 las comillas tipográficas, las rayas, los puntos
/// suspensivos y el euro. Los cinco lugares que deja sin definir (0x81,
/// 0x8D, 0x8F, 0x90, 0x9D) quedan con su mismo código, como hace Windows y
/// dice el estándar: un byte no se pierde aunque no tenga letra.
///
/// Uno solo para el texto plano y para las páginas web: la tabla es la
/// misma.
String decodeWindows1252(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.writeCharCode(
      byte >= 0x80 && byte <= 0x9F ? _high[byte - 0x80] : byte,
    );
  }
  return buffer.toString();
}

/// Del 0x80 al 0x9F.
// dart format off
const _high = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
];
// dart format on
