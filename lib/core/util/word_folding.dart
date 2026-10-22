/// Comparar palabras como las lee una persona: sin mayúsculas ni acentos
/// —«Revolución» y «revolucion» son la misma—, y sabiendo cuáles no dicen
/// nada por sí solas —«de», «la», «the»—.
///
/// Lo comparten ubicar el pasaje de una tarjeta (`anchorQuote`, F30) y
/// validar las palabras clave que propone la IA (F36).
library;

/// La letra o el número [unit] en minúscula y sin acento, o `null` si no es
/// ni una cosa ni la otra.
String? foldWordChar(int unit) {
  final char = String.fromCharCode(unit).toLowerCase();
  final plain = _accents[char];
  if (plain != null) return plain;
  final code = char.codeUnitAt(0);
  final isLetterOrDigit =
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x61 && code <= 0x7a) ||
      // El resto de las letras —griego, cirílico…— cuentan tal cual.
      (code >= 0xc0 && char != char.toUpperCase());
  return isLetterOrDigit ? char : null;
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Lo que está en cualquier texto, en castellano y en inglés —las dos
/// lenguas de la app—: artículos, preposiciones, conjunciones. Ya plegadas.
const _commonWords = {
  // Castellano.
  'a', 'al', 'ante', 'con', 'como', 'cual', 'cuando', 'de', 'del', 'desde',
  'donde', 'durante', 'e', 'el', 'en', 'entre', 'era', 'eran', 'es', 'esa',
  'ese', 'eso', 'esta', 'este', 'esto', 'fue', 'fueron', 'ha', 'han', 'hasta',
  'la', 'las', 'le', 'les', 'lo', 'los', 'mas', 'muy', 'ni', 'no', 'o', 'para',
  'pero', 'por', 'que', 'se', 'ser', 'si', 'sin', 'sobre', 'son', 'su', 'sus',
  'tambien', 'u', 'un', 'una', 'unas', 'uno', 'unos', 'y', 'ya',
  // Inglés.
  'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'had', 'has',
  'have', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'that', 'the', 'their',
  'this', 'to', 'was', 'were', 'which', 'with',
};

/// Si [folded] —ya plegada con [foldWordChar]— es una palabra que está en
/// cualquier texto y no dice nada sola.
bool isCommonWord(String folded) => _commonWords.contains(folded);
