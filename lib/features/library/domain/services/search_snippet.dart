import 'package:sinapsis/features/library/domain/entities/search_citation.dart';

/// Cuántos caracteres se muestran antes y después de la primera coincidencia.
const _before = 60;
const _after = 110;

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// El fragmento de [content] que rodea a lo que se buscó, con cada coincidencia
/// entre [kSnippetOpen] y [kSnippetClose]. Si ninguna palabra aparece, el
/// comienzo del texto, sin marcas.
///
/// Se arma acá y no con `snippet()` de FTS5 por una razón de costo: esa
/// función solo puede correr dentro de una consulta que recorre el índice por
/// coincidencias, y pedirla solo para los cincuenta elementos de una página
/// obligaba a recorrer TODAS las coincidencias de la bóveda —dos segundos con
/// una palabra frecuente—. Con el texto del chunk ya en mano, buscar la palabra
/// es recorrer unos cientos de caracteres.
///
/// Coincide como el índice: sin distinguir mayúsculas ni acentos, y cada
/// palabra buscada como PREFIJO de una palabra del texto —"paradig" marca
/// "paradigma"—; se marca la palabra entera.
String buildSnippet(String content, List<String> terms) {
  final folded = _fold(content);
  final wanted = [
    for (final term in terms)
      if (_fold(term.trim()).isNotEmpty) _fold(term.trim()),
  ];

  final matches = <(int, int)>[];
  for (final term in wanted) {
    var from = 0;
    while (true) {
      final at = folded.indexOf(term, from);
      if (at < 0) break;
      from = at + 1;
      final startsWord = at == 0 || !_isWordChar(content, at - 1);
      if (!startsWord) continue;
      var end = at + term.length;
      while (end < content.length && _isWordChar(content, end)) {
        end++;
      }
      matches.add((at, end));
    }
  }

  if (matches.isEmpty) {
    final end = _wordEnd(content, _before + _after);
    return end >= content.length ? content : '${content.substring(0, end)}…';
  }
  matches.sort((a, b) => a.$1.compareTo(b.$1));

  final first = matches.first.$1;
  final start = first <= _before ? 0 : _wordStart(content, first - _before);
  final end = _wordEnd(content, first + _after);

  final buffer = StringBuffer();
  if (start > 0) buffer.write('…');
  var cursor = start;
  for (final (from, to) in matches) {
    if (from < cursor || from >= end) continue;
    buffer
      ..write(content.substring(cursor, from))
      ..write(kSnippetOpen)
      ..write(content.substring(from, to))
      ..write(kSnippetClose);
    cursor = to;
  }
  buffer.write(content.substring(cursor, end.clamp(cursor, content.length)));
  if (end < content.length) buffer.write('…');
  return buffer.toString();
}

bool _isWordChar(String text, int index) => _wordChar.hasMatch(text[index]);

/// El principio de la palabra que contiene [index], o el primer espacio
/// anterior.
int _wordStart(String text, int index) {
  var i = index.clamp(0, text.length);
  while (i > 0 && _isWordChar(text, i - 1)) {
    i--;
  }
  return i;
}

/// El final de la palabra que contiene [index].
int _wordEnd(String text, int index) {
  var i = index.clamp(0, text.length);
  while (i < text.length && _isWordChar(text, i)) {
    i++;
  }
  return i;
}

/// Minúsculas y sin acentos, unidad por unidad, para que una posición del
/// texto plegado sea la misma en el original —`normalizeVocabularyLabel` puede
/// cambiar el largo—. Pliega también la ñ y la ç, como el tokenizador del
/// índice (`remove_diacritics 2`), que no distingue "año" de "ano".
String _fold(String text) {
  final buffer = StringBuffer();
  for (final unit in text.toLowerCase().codeUnits) {
    buffer.writeCharCode(_folding[unit] ?? unit);
  }
  return buffer.toString();
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
