/// Cuántas palabras de la lista de un idioma hacen falta, como mínimo, para
/// darlo por reconocido.
const _minimumHits = 4;

/// Cuántas veces más palabras tiene que sumar el idioma ganador que el
/// segundo para darlo por seguro: el español y el portugués, o el italiano y
/// el español, comparten un puñado de palabras.
const _winningMargin = 2;

/// Cuánto del texto se mira: el comienzo de una descripción de YouTube dice
/// de qué trata; el final suele ser enlaces, créditos y avisos.
const _maximumLength = 2000;

/// El idioma en que está escrito [text], como código de dos letras, o `null`
/// si no se puede saber con seguridad (F22).
///
/// Es una estimación barata por palabras de uso muy frecuente —artículos,
/// preposiciones, pronombres—, para el título y la descripción de un video:
/// de dónde sale una pista más sobre qué idioma se habla en él cuando
/// YouTube no lo dice. No intenta acertar siempre: ante la duda, `null`. Un
/// título corto o con nombres propios no alcanza, y es mejor no saberlo que
/// equivocarse.
///
/// Reconoce el español, el inglés, el portugués, el francés, el italiano y el
/// alemán: los que ofrece la app para transcribir.
///
/// [maximumLength] es cuánto del comienzo se mira. Para el texto de un video
/// —que se compara con el idioma que se habla antes de guardarlo (F45, paso
/// 4)— se mira más: su comienzo puede ser una presentación con música o un
/// saludo en otro idioma.
String? guessLanguage(String text, {int maximumLength = _maximumLength}) {
  final cut = text.length > maximumLength
      ? text.substring(0, maximumLength)
      : text;
  final words = _wordPattern
      .allMatches(cut.replaceAll(_linkPattern, ' ').toLowerCase())
      .map((match) => match.group(0)!);

  final hits = {for (final language in _commonWords.keys) language: 0};
  for (final word in words) {
    for (final entry in _commonWords.entries) {
      if (entry.value.contains(word)) hits[entry.key] = hits[entry.key]! + 1;
    }
  }

  final ranking = hits.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final best = ranking.first;
  final second = ranking[1];
  if (best.value < _minimumHits) return null;
  if (best.value < second.value * _winningMargin) return null;
  return best.key;
}

final _linkPattern = RegExp(r'(https?://|www\.)\S+');

/// Una palabra: letras, con sus tildes y diéresis.
final _wordPattern = RegExp('[a-záéíóúüñàâçèêëîïôùûœäößãõì]+');

/// Palabras muy comunes de cada idioma, elegidas por lo poco que se parecen a
/// las de los otros. Las que dos idiomas comparten (como «una» o «como»)
/// suman a los dos, y el margen de [_winningMargin] las descarta.
const _commonWords = <String, Set<String>>{
  'es': {
    'el', 'los', 'las', 'una', 'del', 'por', 'con', 'es', 'pero', 'como', //
    'más', 'está', 'también', 'qué', 'muy', 'sobre', 'este', 'esta', 'sus',
    'se', 'lo', 'su', 'al', 'son', 'entre', 'hay', 'todo', 'cómo', 'cuando',
    'donde', 'porque', 'nuestro', 'hacer', 'años', 'tiene', 'ser',
  },
  'en': {
    'the', 'and', 'of', 'to', 'is', 'in', 'that', 'it', 'you', 'for', //
    'with', 'this', 'are', 'was', 'on', 'be', 'as', 'at', 'by', 'from',
    'have', 'not', 'what', 'about', 'your', 'how', 'we', 'they', 'will',
    'can', 'all', 'an', 'or', 'but', 'which', 'their',
  },
  'pt': {
    'não', 'uma', 'os', 'as', 'são', 'você', 'isso', 'dos', 'das', 'mais', //
    'pelo', 'pela', 'ele', 'ela', 'muito', 'do', 'da', 'em', 'com', 'para',
    'também', 'está', 'é', 'um', 'seu', 'sua', 'foi', 'tem', 'só', 'já',
    'nós', 'aqui', 'como', 'quando', 'então',
  },
  'fr': {
    'le', 'les', 'des', 'une', 'est', 'et', 'du', 'dans', 'pour', 'que', //
    'qui', 'pas', 'sur', 'avec', 'au', 'aux', 'ce', 'cette', 'sont', 'nous',
    'vous', 'je', 'il', 'elle', 'ils', 'mais', 'ou', 'où', 'très', 'plus',
    'être', 'fait', 'comme', 'tout', 'ses', 'leur', 'ça',
  },
  'it': {
    'il', 'gli', 'una', 'dei', 'della', 'delle', 'che', 'per', 'con', 'non', //
    'sono', 'più', 'anche', 'come', 'questo', 'questa', 'nel', 'nella',
    'degli', 'alla', 'molto', 'ma', 'è', 'cosa', 'tutto', 'quando', 'dove',
    'perché', 'essere', 'fare', 'suo', 'loro', 'noi', 'voi',
  },
  'de': {
    'der', 'die', 'das', 'und', 'ist', 'nicht', 'ein', 'eine', 'mit', 'für', //
    'auf', 'den', 'dem', 'des', 'von', 'zu', 'im', 'sich', 'auch', 'es',
    'wir', 'sie', 'ich', 'du', 'aber', 'wie', 'wenn', 'dass', 'wird', 'sind',
    'oder', 'nach', 'bei', 'noch', 'über', 'nur', 'zum', 'zur',
  },
};
