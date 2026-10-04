import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';

/// Dónde está, en el texto, el pasaje del que una tarjeta de la IA dice salir
/// (F30), y qué tan seguro es.
@immutable
class QuoteAnchor {
  const QuoteAnchor({
    required this.start,
    required this.end,
    required this.exact,
  });

  /// El rango `[start, end)` del pasaje **real** del texto —no el de la cita
  /// que escribió el modelo—: es lo que «Ver en la fuente» resalta.
  final int start;
  final int end;

  /// Si la cita estaba textual (`locateQuote`), o se ubicó aunque el modelo
  /// la haya cambiado un poco.
  final bool exact;

  @override
  bool operator ==(Object other) =>
      other is QuoteAnchor &&
      other.start == start &&
      other.end == end &&
      other.exact == exact;

  @override
  int get hashCode => Object.hash(start, end, exact);

  @override
  String toString() => 'QuoteAnchor($start, $end${exact ? ', exacta' : ''})';
}

/// Qué parte de las palabras con contenido de la cita tiene que aparecer junta
/// en una oración del texto para que la cita cuente como de ese pasaje (F30).
///
/// Medido con `quote_anchor_test.dart`, sobre tres textos —historia y
/// ciencia en castellano, uno en inglés—: 24 citas cambiadas como las cambia
/// un modelo chico —otro tiempo verbal, un sinónimo, el orden, resumida, sin
/// acentos, «753 a. C.» por «753 antes de Cristo»— reúnen de 0,60 a 1; 22 que
/// no son de ningún pasaje —inventadas sobre el mismo tema, de otro texto, o
/// armadas con palabras de oraciones distintas— reúnen de 0 a 0,50. El umbral
/// es la más baja de las cambiadas: lo dudoso por debajo no se pierde, va a
/// revisar.
///
/// Lo que no distingue: una cita que cambia algo **dentro** de la oración de
/// la que sale —«Augusto expulsó a Tarquinio», cuando fueron los romanos—
/// cae en esa oración, que es de donde sale. La cita ubica el pasaje; si la
/// tarjeta lo entendió bien no lo puede saber ninguna búsqueda, tampoco la
/// textual.
const kQuoteAnchorMinRecall = 0.6;

/// Cuántas palabras con contenido tiene que tener una cita, como mínimo, para
/// buscarla aproximada: con dos, cualquier pasaje que las nombre parecería el
/// suyo. Una más corta solo cuenta textual.
const kQuoteAnchorMinWords = 3;

/// Ubica en [content] la cita que el modelo dio para una tarjeta (F30), o
/// `null` si no es de ningún pasaje.
///
/// Primero, textual (`locateQuote`). Si no, la busca aunque el modelo la haya
/// parafraseado: sin distinguir mayúsculas, acentos, puntuación ni espacios,
/// y después por sus palabras con contenido —sin artículos ni preposiciones,
/// por la raíz, para que «fundada» y «fundación» cuenten como la misma—: el
/// pasaje del texto, del largo de la cita, que tenga juntas al menos
/// [kQuoteAnchorMinRecall] de ellas. El rango que devuelve es el del pasaje
/// real, de su primera palabra encontrada a la última.
///
/// Una cita que no se ubica no es un error: es la señal de que el modelo pudo
/// inventar, y quien llama decide qué hacer con la tarjeta.
QuoteAnchor? anchorQuote(String content, String? quote) {
  final exact = locateQuote(content, quote);
  if (exact != null) {
    return QuoteAnchor(start: exact.start, end: exact.end, exact: true);
  }
  if (quote == null || quote.trim().isEmpty || content.isEmpty) return null;

  final text = _tokensOf(content);
  final cited = _tokensOf(quote);
  if (text.isEmpty || cited.isEmpty) return null;

  // Igual salvo mayúsculas, acentos, puntuación y espacios: la cita entera,
  // palabra por palabra.
  final same = _sequenceIn(text, cited);
  if (same != null) {
    return QuoteAnchor(
      start: text[same].start,
      end: text[same + cited.length - 1].end,
      exact: false,
    );
  }

  return _looseAnchor(text, cited);
}

/// La cita parafraseada: el pasaje del texto que reúne más de sus palabras,
/// si alcanza [kQuoteAnchorMinRecall].
QuoteAnchor? _looseAnchor(List<_Token> text, List<_Token> cited) {
  final passage = _bestPassage(text, cited);
  if (passage == null || passage.recall < kQuoteAnchorMinRecall) return null;
  return QuoteAnchor(
    start: text[passage.first].start,
    end: text[passage.last].end,
    exact: false,
  );
}

/// Qué parte de las palabras con contenido de [quote] reúne el mejor pasaje
/// de [content] (ver [_bestPassage]); `null` si la cita tiene menos de
/// [kQuoteAnchorMinWords]. Es lo que mide el umbral.
@visibleForTesting
double? quoteAnchorRecall(String content, String quote) =>
    _bestPassage(_tokensOf(content), _tokensOf(quote))?.recall;

/// El pasaje de [text] que reúne más palabras con contenido de [cited]: de
/// cuál a cuál de sus palabras va, y qué parte de las de la cita tiene.
///
/// Un pasaje no pasa de una oración: una frase inventada con palabras de dos
/// oraciones vecinas —«Gutenberg imprimió doscientos libros en Maguncia», con
/// «doscientas ciudades» al final de una y «la Biblia de Gutenberg, impresa
/// en Maguncia» en la otra— las encontraría todas en un tramo que cruza las
/// dos. Una cita que de verdad junta dos oraciones queda por debajo del
/// umbral y va a revisar, que es lo que tiene que pasar con lo dudoso.
({int first, int last, double recall})? _bestPassage(
  List<_Token> text,
  List<_Token> cited,
) {
  final wanted = <String, int>{};
  for (final token in cited) {
    if (token.meaningful) {
      wanted.update(token.stem, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final needed = wanted.values.fold(0, (a, b) => a + b);
  if (needed < kQuoteAnchorMinWords) return null;

  // Además, no mucho más largo que la cita —el modelo resume, pero las
  // palabras de la cita tienen que estar juntas—, para que una oración
  // larguísima no junte palabras de una punta y de la otra.
  final window = math.max(cited.length * 2, kQuoteAnchorMinWords);

  var bestFound = 0;
  var bestFirst = 0;
  var bestLast = 0;
  for (var start = 0; start < text.length; start++) {
    // Un pasaje empieza en una palabra de la cita: los demás comienzos dan lo
    // mismo o menos.
    if (!text[start].meaningful || !wanted.containsKey(text[start].stem)) {
      continue;
    }
    final left = Map.of(wanted);
    var found = 0;
    var last = start;
    final end = math.min(text.length, start + window);
    for (var i = start; i < end; i++) {
      final token = text[i];
      final remaining = left[token.stem];
      if (token.meaningful && remaining != null && remaining > 0) {
        left[token.stem] = remaining - 1;
        found++;
        last = i;
      }
      if (token.endsSentence) break;
    }
    if (found > bestFound) {
      bestFound = found;
      bestFirst = start;
      bestLast = last;
    }
  }
  return (first: bestFirst, last: bestLast, recall: bestFound / needed);
}

/// Dónde empieza [cited] entero, palabra por palabra, dentro de [text].
int? _sequenceIn(List<_Token> text, List<_Token> cited) {
  outer:
  for (var i = 0; i + cited.length <= text.length; i++) {
    for (var j = 0; j < cited.length; j++) {
      if (text[i + j].folded != cited[j].folded) continue outer;
    }
    return i;
  }
  return null;
}

/// Una palabra de un texto: dónde está, cómo se compara y si dice algo.
@immutable
class _Token {
  const _Token(this.start, this.end, this.folded, {required this.endsSentence});

  final int start;
  final int end;

  /// Si con ella termina una oración: la sigue un punto —que no es el de una
  /// abreviatura de una letra, como «a. C.»—, un signo de cierre o un salto
  /// de línea.
  final bool endsSentence;

  /// En minúsculas y sin acentos.
  final String folded;

  /// Si es una palabra con contenido: no un artículo, una preposición o una
  /// conjunción, que están en cualquier pasaje.
  /// Una letra sola —la «a» de «a. C.»— tampoco.
  bool get meaningful =>
      (folded.length > 1 || _digits.hasMatch(folded)) &&
      !_stopWords.contains(folded);

  /// Su raíz, para que una cita en otro tiempo verbal o con la palabra
  /// derivada cuente: las primeras cinco letras. Los números, enteros.
  String get stem => folded.length <= _stemLength || _digits.hasMatch(folded)
      ? folded
      : folded.substring(0, _stemLength);
}

const _stemLength = 5;
final _digits = RegExp(r'^\d+$');

/// Las palabras de [text], plegadas, con su lugar en el texto original. Un
/// carácter que no es letra ni número separa.
List<_Token> _tokensOf(String text) {
  final spans = <({int start, int end, String folded})>[];
  final buffer = StringBuffer();
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final folded = _fold(text.codeUnitAt(i));
    if (folded != null) {
      if (start < 0) start = i;
      buffer.write(folded);
    } else if (start >= 0) {
      spans.add((start: start, end: i, folded: buffer.toString()));
      buffer.clear();
      start = -1;
    }
  }
  if (start >= 0) {
    spans.add((start: start, end: text.length, folded: buffer.toString()));
  }
  return [
    for (var i = 0; i < spans.length; i++)
      _Token(
        spans[i].start,
        spans[i].end,
        spans[i].folded,
        endsSentence:
            spans[i].folded.length > 1 &&
            _sentenceEnd.hasMatch(
              text.substring(
                spans[i].end,
                i + 1 < spans.length ? spans[i + 1].start : text.length,
              ),
            ),
      ),
  ];
}

/// Lo que hay entre dos palabras cuando termina una oración: un salto de
/// línea, o un signo de cierre seguido de un espacio o del final. «1.5» no.
final _sentenceEnd = RegExp(r'\n|[.!?…](\s|$)');

/// La letra o el número [unit] en minúscula y sin acento, o `null` si no es
/// ni una cosa ni la otra.
String? _fold(int unit) {
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

/// Lo que está en cualquier pasaje, en castellano y en inglés —las dos
/// lenguas de la app—: no dice de cuál es una cita. Ya plegadas.
const _stopWords = {
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
