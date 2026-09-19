/// Cómo decide el vocabulario controlado que dos textos son la MISMA
/// etiqueta o el mismo valor: sin distinguir mayúsculas ni acentos.
///
/// "Canción", "cancion" y "CANCIÓN" son un solo valor de `Tema`; "Roma" y
/// "Rome" no —eso es traducción, no grafía, y no lo decide una función de
/// texto—.
///
/// A diferencia de `normalizeForDedup`, que compara contenido de fuentes y
/// por eso descarta también la puntuación, acá la puntuación cuenta: "S. XX"
/// y "SXX" son valores distintos hasta que alguien diga lo contrario.
String normalizeVocabularyLabel(String value) {
  final lowered = _composeTildeAndCedilla(value).toLowerCase();

  final folded = StringBuffer();
  for (final rune in lowered.runes) {
    // Marcas combinantes sueltas —texto en forma descompuesta, como el que
    // sale de los nombres de archivo de macOS—: un acento separado de su
    // letra también se descarta.
    if (rune >= _combiningMarksStart && rune <= _combiningMarksEnd) continue;
    final replacement = _accentFolding[rune];
    folded.write(replacement ?? String.fromCharCode(rune));
  }

  return folded.toString().trim().replaceAll(_whitespaceRun, ' ');
}

final _whitespaceRun = RegExp(r'\s+');

/// El bloque Unicode de marcas combinantes (acentos, diéresis, tildes,
/// cedillas… escritos como un carácter aparte): U+0300 a U+036F.
const _combiningMarksStart = 0x0300;
const _combiningMarksEnd = 0x036F;

// Armadas por código y no escritas en literal: en el fuente, `n` + tilde
// combinante se vería idéntica a `ñ`, y la línea de abajo parecería un
// reemplazo de algo por sí mismo.
final _combiningTilde = String.fromCharCode(0x0303);
final _combiningCedilla = String.fromCharCode(0x0327);

/// `ñ` y `ç` NO se pliegan: son letras propias, no una `n` o una `c` con
/// adorno —"año" y "ano" son palabras distintas—.
///
/// Pero llegan a veces en forma descompuesta (`n` + tilde combinante, `c` +
/// cedilla combinante), y sin este paso el descarte de marcas de arriba las
/// convertiría en `n` y `c`. Se recomponen antes de plegar nada.
String _composeTildeAndCedilla(String value) => value
    .replaceAll('n$_combiningTilde', 'ñ')
    .replaceAll('N$_combiningTilde', 'Ñ')
    .replaceAll('c$_combiningCedilla', 'ç')
    .replaceAll('C$_combiningCedilla', 'Ç');

/// Las vocales con acento, diéresis, grave, circunflejo y tilde —ya en
/// minúscula: se aplica después de `toLowerCase`— y la `ý`/`ÿ`. Solo estas;
/// nada más se pliega por intuición.
const _accentFolding = <int, String>{
  0xE1: 'a', // á
  0xE0: 'a', // à
  0xE2: 'a', // â
  0xE4: 'a', // ä
  0xE3: 'a', // ã
  0xE9: 'e', // é
  0xE8: 'e', // è
  0xEA: 'e', // ê
  0xEB: 'e', // ë
  0xED: 'i', // í
  0xEC: 'i', // ì
  0xEE: 'i', // î
  0xEF: 'i', // ï
  0xF3: 'o', // ó
  0xF2: 'o', // ò
  0xF4: 'o', // ô
  0xF6: 'o', // ö
  0xF5: 'o', // õ
  0xFA: 'u', // ú
  0xF9: 'u', // ù
  0xFB: 'u', // û
  0xFC: 'u', // ü
  0xFD: 'y', // ý
  0xFF: 'y', // ÿ
};
