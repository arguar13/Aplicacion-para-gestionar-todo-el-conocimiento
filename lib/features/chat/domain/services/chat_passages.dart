/// Cuánto texto de cada fuente se le da al modelo en el chat con la bóveda
/// (F30): el pasaje donde está lo que se preguntó, no el elemento entero.
///
/// Con cuatro fuentes son unos 2.400 caracteres —unos 700 tokens—: entran en
/// la ventana de 2048 junto con la instrucción, la pregunta, un poco de lo
/// conversado y la respuesta. Más texto es más espera hasta la primera
/// palabra: el modelo lee todo el pedido antes de empezar a escribir.
const kChatPassageChars = 600;

/// Cuántas fuentes se le dan al modelo, como mucho.
const kChatMaxSources = 4;

/// Cuántas palabras de la pregunta se buscan, como mucho: las primeras que
/// no son vacías.
const kChatMaxQuestionTerms = 8;

/// Las palabras de [question] que sirven para buscar en la bóveda (F30): sin
/// las vacías —artículos, preposiciones, «contame», «qué dice»—, sin
/// repetidas y sin las de una o dos letras, que como prefijo encuentran
/// casi cualquier cosa. Los números van siempre: un año distingue mucho.
///
/// Hasta F30 se buscaba cada palabra de la pregunta por separado, también
/// «de», «la» y «qué»: quince consultas para una pregunta común, y las
/// palabras vacías traían cualquier cosa.
List<String> questionTerms(String question, {int max = kChatMaxQuestionTerms}) {
  final terms = <String>[];
  final seen = <String>{};
  for (final match in _word.allMatches(question)) {
    final word = match.group(0)!;
    final folded = foldForSearch(word);
    final isNumber = _digits.hasMatch(folded);
    if (!isNumber && folded.length < 3) continue;
    if (isNumber && folded.length < 2) continue;
    if (_stopWords.contains(folded)) continue;
    if (!seen.add(folded)) continue;
    terms.add(word);
    if (terms.length == max) break;
  }
  return terms;
}

/// Dónde está, dentro de [content], el pasaje de hasta [maxChars] caracteres
/// que más palabras distintas de [terms] junta (F30): para darle al modelo
/// lo que importa de una fuente y no su principio. Coincide como el índice
/// de búsqueda —sin mayúsculas ni acentos, cada palabra como principio de
/// otra—.
///
/// Empieza en el principio de la oración si queda cerca, o de una palabra, y
/// termina al final de una palabra. Sin ninguna coincidencia, el principio
/// del texto.
({int start, int end}) passageWindow(
  String content,
  List<String> terms, {
  int maxChars = kChatPassageChars,
}) {
  if (content.length <= maxChars) return (start: 0, end: content.length);

  final folded = foldForSearch(content);
  final hits = <({int at, int term})>[];
  for (var t = 0; t < terms.length; t++) {
    final term = foldForSearch(terms[t]);
    if (term.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = folded.indexOf(term, from);
      if (at < 0) break;
      from = at + 1;
      if (at == 0 || !_isWordChar(content, at - 1)) hits.add((at: at, term: t));
    }
  }
  if (hits.isEmpty) {
    return (start: 0, end: _wordEnd(content, maxChars, limit: maxChars));
  }
  hits.sort((a, b) => a.at.compareTo(b.at));

  // La ventana que junta más palabras distintas; a igualdad, la primera.
  var best = hits.first.at;
  var bestCount = 0;
  for (final hit in hits) {
    final distinct = {
      for (final other in hits)
        if (other.at >= hit.at && other.at < hit.at + maxChars * 3 ~/ 4)
          other.term,
    }.length;
    if (distinct > bestCount) {
      bestCount = distinct;
      best = hit.at;
    }
  }

  // Un poco de lo anterior, para que se entienda: desde el principio de la
  // oración si está a menos de un cuarto de la ventana.
  final lead = maxChars ~/ 4;
  var start = _sentenceStart(content, best, lead);
  if (start + maxChars > content.length) {
    start = _wordStart(content, content.length - maxChars);
  }
  final end = _wordEnd(content, start + maxChars, limit: start + maxChars);
  return (start: start, end: end);
}

/// Minúsculas y sin acentos, carácter por carácter —el largo no cambia, así
/// que una posición sirve en el texto original—, como el tokenizador del
/// índice (`remove_diacritics 2`), que tampoco distingue la ñ.
String foldForSearch(String text) {
  final buffer = StringBuffer();
  for (final unit in text.toLowerCase().codeUnits) {
    buffer.writeCharCode(_folding[unit] ?? unit);
  }
  return buffer.toString();
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _digits = RegExp(r'^\d+$');

bool _isWordChar(String text, int index) => _wordChar.hasMatch(text[index]);

int _wordStart(String text, int index) {
  var i = index.clamp(0, text.length);
  while (i > 0 && _isWordChar(text, i - 1)) {
    i--;
  }
  return i;
}

/// El final de la palabra en [index], sin pasar de [limit]: si la palabra
/// cruza el límite, se corta antes de ella.
int _wordEnd(String text, int index, {required int limit}) {
  final max = limit.clamp(0, text.length);
  var i = index.clamp(0, max);
  if (i == text.length || !_isWordChar(text, i)) return i;
  while (i > 0 && _isWordChar(text, i - 1)) {
    i--;
  }
  return i;
}

/// El principio de la oración que contiene [index], si está a menos de
/// [lead] caracteres; si no, el principio de la palabra a [lead] antes.
int _sentenceStart(String text, int index, int lead) {
  final floor = (index - lead).clamp(0, text.length);
  for (var i = index; i > floor; i--) {
    final previous = text[i - 1];
    if (previous == '\n' ||
        ((previous == ' ') &&
            i >= 2 &&
            const {'.', '!', '?', '…'}.contains(text[i - 2]))) {
      return i;
    }
  }
  return floor == 0 ? 0 : _wordStart(text, floor);
}

final Map<int, int> _folding = () {
  const groups = <String, String>{
    'a': 'áàâäãåā',
    'e': 'éèêëēė',
    'i': 'íìîïī',
    'o': 'óòôöõøō',
    'u': 'úùûüū',
    'y': 'ýÿ',
    'n': 'ñ',
    'c': 'ç',
  };
  return {
    for (final entry in groups.entries)
      for (final unit in entry.value.codeUnits) unit: entry.key.codeUnitAt(0),
  };
}();

/// Las palabras que no dicen de qué se pregunta, ya plegadas
/// ([foldForSearch]): las más comunes del español y del inglés, y los
/// pedidos típicos de un chat.
const _stopWords = <String>{
  // Español: artículos, pronombres, preposiciones, conjunciones.
  'los', 'las', 'una', 'unos', 'unas', 'del', 'que', 'por', 'para', 'con',
  'sin', 'sobre', 'entre', 'hasta', 'desde', 'hacia', 'segun', 'tras',
  'como', 'cual', 'cuales', 'cuando', 'donde', 'quien', 'quienes',
  'cuanto', 'cuanta', 'cuantos', 'cuantas', 'porque', 'pero', 'mas',
  'menos', 'muy', 'hay', 'este', 'esta', 'esto', 'estos', 'estas', 'ese',
  'esa', 'eso', 'esos', 'esas', 'aquel', 'aquella', 'aquello', 'tambien',
  'todo', 'todos', 'toda', 'todas', 'otro', 'otra', 'otros', 'otras',
  'cada', 'algo', 'algun', 'alguno', 'alguna', 'nada', 'ningun', 'ninguno',
  'pues', 'entonces', 'asi', 'aqui', 'ahi', 'alli', 'aca', 'alla', 'sus',
  'mis', 'tus', 'nos', 'les', 'ella', 'ellos', 'ellas', 'usted',
  'ustedes', 'vos', 'nosotros', 'mio', 'mia', 'tuyo', 'suyo', 'cosa',
  'cosas', 'tema', 'temas', 'puede', 'pueden', 'puedo', 'podes',
  'podrias', 'puedes', 'seria', 'sera', 'fue', 'fueron', 'son', 'era',
  'eran', 'ser', 'estar', 'estan', 'estaba', 'tiene', 'tienen',
  'tengo', 'tenes', 'tienes', 'tener', 'hace', 'hacer', 'hizo', 'dice',
  'dicen', 'decir', 'dijo', 'sabes', 'saber', 'quiero', 'queria',
  'quisiera', 'necesito', 'favor', 'gracias', 'hola', 'bueno', 'bien',
  'ahora', 'despues', 'antes', 'luego', 'siempre', 'nunca', 'tan', 'tanto',
  'mucho', 'mucha', 'muchos', 'muchas', 'poco', 'pocos', 'solo', 'sola',
  'ademas', 'mismo', 'misma', 'aun', 'todavia', 'dentro', 'fuera',
  // Pedidos del chat.
  'contame', 'contas', 'cuentame', 'decime', 'dime', 'explicame',
  'explica', 'explicar', 'explicacion', 'resumime', 'resumen', 'resumir',
  'resume', 'hablame', 'habla', 'hablar', 'mostrame', 'muestrame',
  'busca', 'buscar', 'busques', 'encontra', 'encuentra', 'boveda',
  'guarde', 'guardado', 'guardados', 'guardadas', 'notas', 'nota',
  'elemento', 'elementos', 'informacion', 'datos', 'dato', 'acerca',
  'respecto', 'relacion', 'pregunta', 'respuesta', 'ejemplo', 'ejemplos',
  // Inglés.
  'the', 'and', 'for', 'with', 'about', 'what', 'which', 'who', 'whom',
  'when', 'where', 'why', 'how', 'this', 'that', 'these', 'those', 'are',
  'was', 'were', 'been', 'being', 'have', 'has', 'had', 'does', 'did',
  'can', 'could', 'would', 'should', 'will', 'from', 'into', 'than',
  'then', 'there', 'their', 'they', 'them', 'you', 'your', 'not', 'but',
  'all', 'any', 'some', 'tell', 'explain', 'summarize', 'show', 'please',
  'vault', 'notes', 'note',
};
