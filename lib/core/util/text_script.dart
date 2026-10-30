/// La escritura —el alfabeto— de un texto (F45, paso 4): latina, árabe,
/// cirílica… Es la pista más firme que hay de que un texto no está en el
/// idioma que se esperaba: un video en español no puede tener su
/// transcripción escrita en letras árabes, diga lo que diga la etiqueta de la
/// pista que se bajó.
enum TextScript {
  latin,
  greek,
  cyrillic,
  hebrew,
  arabic,
  devanagari,
  thai,
  hangul,

  /// El chino y el japonés: ideogramas, y los silabarios del japonés.
  cjk,
}

/// Cuántas letras de cada escritura tiene un texto (F45, paso 4).
///
/// Solo cuenta letras de las escrituras de [TextScript]: los números, la
/// puntuación, los espacios y las marcas de tiempo no dicen nada del idioma,
/// y una escritura que no está en la lista no se cuenta —ni a favor ni en
/// contra—.
class ScriptCensus {
  ScriptCensus._(this._counts, this.letters);

  final Map<TextScript, int> _counts;

  /// Cuántas letras se contaron en total.
  final int letters;

  /// Qué parte de las letras, de 0 a 1, es de [script]; 0 si no hay letras.
  double shareOf(TextScript script) =>
      letters == 0 ? 0 : (_counts[script] ?? 0) / letters;

  /// La escritura con más letras, o `null` si no hay ninguna.
  TextScript? get dominant {
    TextScript? best;
    var most = 0;
    for (final MapEntry(:key, :value) in _counts.entries) {
      if (value > most) {
        best = key;
        most = value;
      }
    }
    return best;
  }

  /// La escritura de casi todo el texto —al menos [share] de sus letras, y
  /// [minimumLetters] letras—, o `null` si es corto o mezcla escrituras.
  TextScript? clearScript({int minimumLetters = 8, double share = 0.8}) {
    final script = dominant;
    if (script == null || letters < minimumLetters) return null;
    return shareOf(script) >= share ? script : null;
  }
}

/// Las letras de [text] por escritura: ver [ScriptCensus].
ScriptCensus scriptCensusOf(String text) {
  final counts = <TextScript, int>{};
  var letters = 0;
  for (final rune in text.runes) {
    final script = _scriptOf(rune);
    if (script == null) continue;
    counts[script] = (counts[script] ?? 0) + 1;
    letters++;
  }
  return ScriptCensus._(counts, letters);
}

/// La escritura de una letra, o `null` si no es una letra de las que se
/// cuentan.
TextScript? _scriptOf(int rune) {
  if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
    return TextScript.latin;
  }
  if (rune < 0xC0) return null;
  // Latín con tildes, sin el «×» y el «÷», que no son letras.
  if (rune <= 0x24F) {
    return rune == 0xD7 || rune == 0xF7 ? null : TextScript.latin;
  }
  if (rune >= 0x1E00 && rune <= 0x1EFF) return TextScript.latin;
  if ((rune >= 0x370 && rune <= 0x3FF) || (rune >= 0x1F00 && rune <= 0x1FFF)) {
    return TextScript.greek;
  }
  if (rune >= 0x400 && rune <= 0x52F) return TextScript.cyrillic;
  if (rune >= 0x5D0 && rune <= 0x5F2) return TextScript.hebrew;
  if (_isArabicLetter(rune)) return TextScript.arabic;
  if (rune >= 0x904 && rune <= 0x97F) return TextScript.devanagari;
  if (rune >= 0xE01 && rune <= 0xE5B) return TextScript.thai;
  if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0x1100 && rune <= 0x11FF) ||
      (rune >= 0x3130 && rune <= 0x318F)) {
    return TextScript.hangul;
  }
  if ((rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF)) {
    return TextScript.cjk;
  }
  return null;
}

/// Una letra árabe —también la del persa y el urdu—, sin sus números ni su
/// puntuación.
bool _isArabicLetter(int rune) {
  if (rune >= 0x620 && rune <= 0x64A) return true;
  if (rune >= 0x66E && rune <= 0x6D3) return true;
  if (rune >= 0x6FA && rune <= 0x6FF) return true;
  if (rune >= 0x750 && rune <= 0x77F) return true;
  if (rune >= 0x8A0 && rune <= 0x8FF) return true;
  if (rune >= 0xFB50 && rune <= 0xFDFF) return true;
  return rune >= 0xFE70 && rune <= 0xFEFC;
}

/// La escritura en que se escribe el idioma [code] ("es", "ar", "pt-BR"), o
/// `null` si es de una escritura que no se cuenta —el armenio, el georgiano,
/// el bengalí…—: de esos no se puede decir si un texto está en su escritura.
///
/// Cualquier idioma que no está en la lista se escribe en letras latinas: el
/// español, el inglés y los demás que ofrece la app, y también el turco, el
/// polaco, el vietnamita o el indonesio.
TextScript? scriptOfLanguage(String code) {
  final language = code.toLowerCase().split(RegExp('[-_]')).first;
  if (_uncountedLanguages.contains(language)) return null;
  return _languageScripts[language] ?? TextScript.latin;
}

const _languageScripts = {
  'ar': TextScript.arabic,
  'fa': TextScript.arabic,
  'ur': TextScript.arabic,
  'ps': TextScript.arabic,
  'sd': TextScript.arabic,
  'ug': TextScript.arabic,
  'he': TextScript.hebrew,
  'iw': TextScript.hebrew,
  'yi': TextScript.hebrew,
  'ru': TextScript.cyrillic,
  'uk': TextScript.cyrillic,
  'be': TextScript.cyrillic,
  'bg': TextScript.cyrillic,
  'mk': TextScript.cyrillic,
  'kk': TextScript.cyrillic,
  'ky': TextScript.cyrillic,
  'mn': TextScript.cyrillic,
  'tg': TextScript.cyrillic,
  'tt': TextScript.cyrillic,
  'ba': TextScript.cyrillic,
  'el': TextScript.greek,
  'hi': TextScript.devanagari,
  'mr': TextScript.devanagari,
  'ne': TextScript.devanagari,
  'sa': TextScript.devanagari,
  'th': TextScript.thai,
  'ko': TextScript.hangul,
  'ja': TextScript.cjk,
  'zh': TextScript.cjk,
};

/// Idiomas cuya escritura no se cuenta (ver [scriptOfLanguage]). El serbio
/// también: se escribe en cirílico y en latín.
const _uncountedLanguages = {
  'sr', 'hy', 'ka', 'am', 'ti', 'bn', 'as', 'pa', 'gu', 'or', 'ta', 'te', //
  'kn', 'ml', 'si', 'my', 'km', 'lo', 'bo', 'dv', 'und', 'zxx', 'mul',
};

/// El idioma más probable de un texto en [script], si la escritura sola lo
/// dice: el árabe, el ruso, el griego… `null` para las que comparten muchos
/// idiomas sin uno que domine —el latín— o mezclan dos —el chino y el
/// japonés—.
String? languageOfScript(TextScript script) => switch (script) {
  TextScript.arabic => 'ar',
  TextScript.cyrillic => 'ru',
  TextScript.greek => 'el',
  TextScript.hebrew => 'he',
  TextScript.devanagari => 'hi',
  TextScript.thai => 'th',
  TextScript.hangul => 'ko',
  TextScript.latin || TextScript.cjk => null,
};
