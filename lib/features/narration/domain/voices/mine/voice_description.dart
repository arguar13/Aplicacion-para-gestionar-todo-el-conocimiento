import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Lo que se entendió de una descripción en palabras (F47, paso 4b): los
/// controles que se pudieron poner y las palabras que los pusieron.
@immutable
class DescribedVoice {
  const DescribedVoice({
    required this.design,
    required this.understood,
    this.accent,
  });

  /// Los controles, con lo que no se nombró como estaba.
  final VoiceDesign design;

  /// Las palabras reconocidas, en el orden en que aparecen.
  final List<String> understood;

  /// Si se pidió un acento con región —«rioplatense», «mexicano»— que el
  /// teléfono no puede dar con Kokoro: su código (`es-AR`), para decirlo.
  final String? accent;
}

/// Traduce [text] —«hombre joven, rioplatense, cálido y entusiasta, como un
/// relator de fútbol»— a los controles de una voz creada, partiendo de
/// [current]: lo que la descripción no nombra queda como estaba.
///
/// Es un diccionario de palabras en español y en inglés, sin IA: lo que se
/// pide queda a la vista («Entendí: hombre, joven, cálido») y se ajusta con
/// los controles. Si nombra dos géneros, o dos estilos, vale el último.
DescribedVoice interpretVoiceDescription(String text, VoiceDesign current) {
  final words = _words(text);
  var design = current;
  final understood = <String>[];
  String? accent;

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final pair = i + 1 < words.length ? '$word ${words[i + 1]}' : null;
    final term = pair != null && _phrases.containsKey(pair) ? pair : word;
    final meaning = _phrases[term] ?? _terms[word];
    if (meaning == null) continue;
    if (term == pair) i++;
    understood.add(term);
    switch (meaning) {
      case _Gender(:final gender):
        design = design.copyWith(gender: gender);
      case _Age(:final age):
        design = design.copyWith(age: age);
      case _Timbre(:final timbre):
        design = design.copyWith(timbre: timbre);
      case _Style(:final style):
        design = design.copyWith(style: style);
      case _Pace(:final factor):
        design = design.copyWith(
          pace: factor.clamp(VoiceDesign.minPace, VoiceDesign.maxPace),
        );
      case _Locale(:final locale, :final region):
        design = design.copyWith(locale: locale);
        accent = region;
    }
  }
  return DescribedVoice(design: design, understood: understood, accent: accent);
}

/// Las palabras de [text], en minúscula y sin signos; las tildes quedan.
List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((word) => word.isNotEmpty)
    .toList();

sealed class _Meaning {
  const _Meaning();
}

class _Gender extends _Meaning {
  const _Gender(this.gender);
  final VoiceGender gender;
}

class _Age extends _Meaning {
  const _Age(this.age);
  final VoiceAge age;
}

class _Timbre extends _Meaning {
  const _Timbre(this.timbre);
  final VoiceTimbre timbre;
}

class _Style extends _Meaning {
  const _Style(this.style);
  final VoiceStyle style;
}

class _Pace extends _Meaning {
  const _Pace(this.factor);
  final double factor;
}

class _Locale extends _Meaning {
  const _Locale(this.locale, [this.region]);

  /// Uno de [OfflineVoiceCatalog.kokoroLocales].
  final String locale;

  /// El acento pedido, si Kokoro no lo tiene: `es-AR`.
  final String? region;
}

const _female = _Gender(VoiceGender.female);
const _male = _Gender(VoiceGender.male);
const _young = _Age(VoiceAge.young);
const _adult = _Age(VoiceAge.adult);
const _senior = _Age(VoiceAge.senior);
const _deep = _Timbre(VoiceTimbre.deep);
const _clear = _Timbre(VoiceTimbre.clear);
const _velvety = _Timbre(VoiceTimbre.velvety);
const _bright = _Timbre(VoiceTimbre.bright);
const _warm = _Style(VoiceStyle.warm);
const _calm = _Style(VoiceStyle.calm);
const _expressive = _Style(VoiceStyle.expressive);
const _energetic = _Style(VoiceStyle.energetic);
const _authoritative = _Style(VoiceStyle.authoritative);
const _slow = _Pace(0.88);
const _fast = _Pace(1.15);
const _spanish = _Locale('es');

/// Lo que se dice en dos palabras.
const _phrases = <String, _Meaning>{
  'mediana edad': _adult,
  'tercera edad': _senior,
  'con autoridad': _authoritative,
  'muy expresivo': _expressive,
  'muy expresiva': _expressive,
  'de españa': _spanish,
  'de méxico': _Locale('es', 'es-MX'),
  'de argentina': _Locale('es', 'es-AR'),
  'de brasil': _Locale('pt-BR'),
  'de francia': _Locale('fr-FR'),
  'de italia': _Locale('it'),
  'de india': _Locale('hi'),
  'en inglés': _Locale('en-US'),
  'en español': _spanish,
  'en francés': _Locale('fr-FR'),
  'en italiano': _Locale('it'),
  'en portugués': _Locale('pt-BR'),
  'en hindi': _Locale('hi'),
  'deep voice': _deep,
  'middle aged': _adult,
};

/// Lo que se dice en una palabra. Los acentos con región que Kokoro no tiene
/// —rioplatense, mexicano— ponen el español y lo dicen.
const _terms = <String, _Meaning>{
  // Género.
  'mujer': _female,
  'femenina': _female,
  'femenino': _female,
  'chica': _female,
  'señora': _female,
  'muchacha': _female,
  'woman': _female,
  'female': _female,
  'girl': _female,
  'hombre': _male,
  'masculina': _male,
  'masculino': _male,
  'varón': _male,
  'chico': _male,
  'señor': _male,
  'muchacho': _male,
  'man': _male,
  'male': _male,
  'guy': _male,
  // Edad.
  'joven': _young,
  'adolescente': _young,
  'juvenil': _young,
  'young': _young,
  'adulto': _adult,
  'adulta': _adult,
  'madura': _adult,
  'maduro': _adult,
  'adult': _adult,
  'mayor': _senior,
  'anciano': _senior,
  'anciana': _senior,
  'abuelo': _senior,
  'abuela': _senior,
  'veterano': _senior,
  'old': _senior,
  'elderly': _senior,
  // Timbre.
  'grave': _deep,
  'profunda': _deep,
  'profundo': _deep,
  'ronca': _deep,
  'ronco': _deep,
  'deep': _deep,
  'clara': _clear,
  'claro': _clear,
  'nítida': _clear,
  'nítido': _clear,
  'clear': _clear,
  'aterciopelada': _velvety,
  'aterciopelado': _velvety,
  'suave': _velvety,
  'velvety': _velvety,
  'smooth': _velvety,
  'brillante': _bright,
  'aguda': _bright,
  'agudo': _bright,
  'bright': _bright,
  // Estilo.
  'cálida': _warm,
  'cálido': _warm,
  'cercana': _warm,
  'cercano': _warm,
  'amable': _warm,
  'warm': _warm,
  'serena': _calm,
  'sereno': _calm,
  'tranquila': _calm,
  'tranquilo': _calm,
  'calma': _calm,
  'calmo': _calm,
  'relajada': _calm,
  'relajado': _calm,
  'calm': _calm,
  'expresiva': _expressive,
  'expresivo': _expressive,
  'dramática': _expressive,
  'dramático': _expressive,
  'narrador': _expressive,
  'narradora': _expressive,
  'expressive': _expressive,
  'enérgica': _energetic,
  'enérgico': _energetic,
  'entusiasta': _energetic,
  'animada': _energetic,
  'animado': _energetic,
  'relator': _energetic,
  'relatora': _energetic,
  'energetic': _energetic,
  'firme': _authoritative,
  'seria': _authoritative,
  'serio': _authoritative,
  'formal': _authoritative,
  'autoritaria': _authoritative,
  'autoritario': _authoritative,
  'authoritative': _authoritative,
  // Ritmo.
  'lenta': _slow,
  'lento': _slow,
  'pausada': _slow,
  'pausado': _slow,
  'slow': _slow,
  'rápida': _fast,
  'rápido': _fast,
  'ágil': _fast,
  'fast': _fast,
  // Idioma y acento.
  'español': _spanish,
  'española': _spanish,
  'castellano': _spanish,
  'castellana': _spanish,
  'spanish': _spanish,
  'rioplatense': _Locale('es', 'es-AR'),
  'argentina': _Locale('es', 'es-AR'),
  'argentino': _Locale('es', 'es-AR'),
  'porteña': _Locale('es', 'es-AR'),
  'porteño': _Locale('es', 'es-AR'),
  'uruguaya': _Locale('es', 'es-UY'),
  'uruguayo': _Locale('es', 'es-UY'),
  'mexicana': _Locale('es', 'es-MX'),
  'mexicano': _Locale('es', 'es-MX'),
  'colombiana': _Locale('es', 'es-CO'),
  'colombiano': _Locale('es', 'es-CO'),
  'chilena': _Locale('es', 'es-CL'),
  'chileno': _Locale('es', 'es-CL'),
  'peruana': _Locale('es', 'es-PE'),
  'peruano': _Locale('es', 'es-PE'),
  'inglés': _Locale('en-US'),
  'inglesa': _Locale('en-GB'),
  'english': _Locale('en-US'),
  'americana': _Locale('en-US'),
  'americano': _Locale('en-US'),
  'american': _Locale('en-US'),
  'británica': _Locale('en-GB'),
  'británico': _Locale('en-GB'),
  'british': _Locale('en-GB'),
  'francesa': _Locale('fr-FR'),
  'francés': _Locale('fr-FR'),
  'french': _Locale('fr-FR'),
  'italiana': _Locale('it'),
  'italiano': _Locale('it'),
  'italian': _Locale('it'),
  'brasileña': _Locale('pt-BR'),
  'brasileño': _Locale('pt-BR'),
  'portuguesa': _Locale('pt-BR', 'pt-PT'),
  'portugués': _Locale('pt-BR'),
  'portuguese': _Locale('pt-BR'),
  'brazilian': _Locale('pt-BR'),
  'hindi': _Locale('hi'),
};

/// Lo que dice [checkRealPerson] de una descripción.
@immutable
class RealPersonFinding {
  const RealPersonFinding(this.names);

  /// Lo que parece el nombre de una persona, como está escrito.
  final List<String> names;

  bool get found => names.isNotEmpty;
}

/// Si [text] —la descripción de una voz que se va a crear— nombra a una
/// persona real (F47, paso 4b): una voz creada no imita a nadie, y si lo
/// pide, la app lo dice y propone describir el estilo en su lugar.
///
/// **La heurística, sin listas de famosos** (una lista inventada se queda
/// corta, y nombrar personas en el código no corresponde): se buscan
/// **nombres propios** —palabras con mayúscula que no empiezan una oración—
/// que no sean vocabulario de una voz —idiomas, países, gentilicios, «Voz»—, y
/// los pedidos de imitar: «como Fulano», «la voz de Fulano», «que suene
/// como», «imitar», «imitando», «sounds like», «impersonate»…
///
/// - «Hombre joven, cálido, como un relator de fútbol» no nombra a nadie:
///   pasa.
/// - «Como Messi», «la voz de Juan Pérez», «imitando a mi profesor» y
///   «sounds like Morgan Freeman» no pasan.
/// - En minúscula, un nombre solo no se reconoce («como messi»): por eso
///   también se marcan los pedidos de imitar, con nombre o sin él.
/// - Un nombre solo al comienzo de la descripción («Messi, enérgico») no se
///   distingue de la primera palabra de una oración; sí uno con apellido
///   («Morgan Freeman, grave»), porque la segunda palabra ya no empieza nada.
RealPersonFinding checkRealPerson(String text) {
  final names = <String>[];

  // Los nombres propios: mayúscula que no empieza una oración.
  final tokens = RegExp(
    r'[\p{L}\p{N}]+|[.!?¿¡:;\n]',
    unicode: true,
  ).allMatches(text).map((match) => match.group(0)!).toList();
  var sentenceStart = true;
  final run = <String>[];
  void flush() {
    if (run.isNotEmpty) names.add(run.join(' '));
    run.clear();
  }

  for (final token in tokens) {
    if (RegExp(r'^[.!?¿¡:;\n]$').hasMatch(token)) {
      flush();
      sentenceStart = true;
      continue;
    }
    final capitalized =
        token.length > 1 &&
        token[0] == token[0].toUpperCase() &&
        token[0] != token[0].toLowerCase() &&
        token != token.toUpperCase();
    final vocabulary = _notNames.contains(token.toLowerCase());
    if (capitalized && !vocabulary && !sentenceStart) {
      run.add(token);
    } else if (capitalized && !vocabulary && run.isNotEmpty) {
      run.add(token);
    } else {
      flush();
    }
    sentenceStart = false;
  }
  flush();

  // Los pedidos de imitar, con nombre o sin él.
  final lower = text.toLowerCase();
  for (final match in _imitation.allMatches(lower)) {
    final phrase = text.substring(match.start, match.end).trim();
    if (!names.any(phrase.contains)) names.add(phrase);
  }
  return RealPersonFinding(List.unmodifiable(names));
}

/// Pedir que suene como alguien. «Como un relator», «como una locutora» no:
/// un artículo dice que es un oficio, no una persona.
final _imitation = RegExp(
  r'\b(imit(a|ar|ando|e|ación)\b[^,.;]*'
  r'|que suene (igual )?(a|como)\b[^,.;]*'
  r'|parecida a\s+(?!un\b|una\b)[^,.;]*'
  r'|parecido a\s+(?!un\b|una\b)[^,.;]*'
  r'|la voz de\s+(?!un\b|una\b|los\b|las\b|el\b|la\b)[^,.;]*'
  r'|sounds? like\b[^,.;]*'
  r'|the voice of\b[^,.;]*'
  r'|impersonat\w*[^,.;]*'
  r'|clon(ar|e)\b[^,.;]*)',
  unicode: true,
);

/// Las palabras que van con mayúscula sin ser el nombre de una persona: los
/// idiomas, países y gentilicios —en inglés llevan mayúscula—, y lo que se
/// escribe en una descripción.
const _notNames = {
  'voz',
  'voice',
  'kokoro',
  'english',
  'spanish',
  'french',
  'italian',
  'portuguese',
  'brazilian',
  'british',
  'american',
  'hindi',
  'german',
  'mexican',
  'argentinian',
  'argentine',
  'colombian',
  'chilean',
  'peruvian',
  'uruguayan',
  'spain',
  'mexico',
  'méxico',
  'argentina',
  'colombia',
  'chile',
  'perú',
  'peru',
  'uruguay',
  'brasil',
  'brazil',
  'france',
  'francia',
  'italy',
  'italia',
  'india',
  'españa',
  'england',
  'inglaterra',
  'london',
  'londres',
  'buenos',
  'aires',
  'rioplatense',
  'latinoamérica',
  'latinoamericana',
  'latinoamericano',
  'latin',
  'america',
  'i',
};
