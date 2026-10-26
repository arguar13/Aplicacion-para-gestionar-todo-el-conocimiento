import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// Un pasaje del texto que el modelo tiene que leer (F40): la oración con una
/// fecha escrita y, antes, la oración anterior como contexto —«Ese año
/// publicó…» solo se entiende con la que dice cuál—.
@immutable
class DatedPassage {
  const DatedPassage({
    required this.start,
    required this.text,
    required this.expressions,
  });

  /// Dónde empieza [text] en el texto entero.
  final int start;

  /// El pasaje, tal cual está en el texto.
  final String text;

  /// Las expresiones de tiempo que hay en él, con sus posiciones en el texto
  /// **entero**: con qué se comprueba que lo que el modelo devuelve es una
  /// fecha que el texto dice.
  final List<TemporalExpression> expressions;

  int get end => start + text.length;

  @override
  bool operator ==(Object other) =>
      other is DatedPassage &&
      other.start == start &&
      other.text == text &&
      listEquals(other.expressions, expressions);

  @override
  int get hashCode => Object.hash(start, text, Object.hashAll(expressions));

  @override
  String toString() => 'DatedPassage($start, ${text.length} caracteres)';
}

/// Los pasajes que se le dan juntos al modelo en un pedido (F40): no tienen
/// por qué ser contiguos en el texto, pero cada uno conserva su lugar en él.
@immutable
class DatedTextPart {
  DatedTextPart(List<DatedPassage> passages)
    : assert(passages.isNotEmpty, 'Un pedido tiene al menos un pasaje.'),
      passages = List.unmodifiable(passages);

  final List<DatedPassage> passages;

  /// Cuántos caracteres de texto tiene, sin lo que le agrega el pedido.
  int get chars => passages.fold(0, (sum, p) => sum + p.text.length);

  /// Lo que queda después de los primeros [count] pasajes, o `null` si ya
  /// estaban todos: lo que falta pedir cuando el modelo no alcanzó a leer el
  /// pedido entero.
  DatedTextPart? after(int count) =>
      count >= passages.length ? null : DatedTextPart(passages.sublist(count));

  @override
  bool operator ==(Object other) =>
      other is DatedTextPart && listEquals(other.passages, passages);

  @override
  int get hashCode => Object.hashAll(passages);

  @override
  String toString() => 'DatedTextPart(${passages.length} pasajes, $chars)';
}

/// Cuánto puede medir la oración anterior para servir de contexto: una más
/// larga ocuparía el pedido sin aportar.
const kMaxContextSentenceChars = 300;

/// Lo que cada pasaje suma al pedido además de su texto: el número entre
/// corchetes y el salto de línea.
const kDatedPassageOverheadChars = 8;

/// Cuántos caracteres de pasaje cuenta un pasaje cualquiera, para repartir
/// cuántos entran en un pedido: la oración con su fecha y la anterior, unos
/// cientos.
const _charsPerPassage = 400;

/// Lo más que se le piden a un modelo en un solo pedido.
const _maxPassagesPerPart = 40;

/// Cuántos pasajes entran, como mucho, en un pedido de [maxChars]: cada uno
/// puede traer más de un hecho, y cada hecho es una línea de respuesta.
int maxPassagesPerPart(int maxChars) =>
    (maxChars ~/ _charsPerPassage).clamp(1, _maxPassagesPerPart);

/// Los pasajes de [text] que conviene mandar al modelo, repartidos en pedidos
/// de hasta [maxChars] caracteres (F40).
///
/// Un texto sin ninguna expresión de tiempo da una lista vacía: no hay nada
/// que preguntarle al modelo, y un libro de 300 páginas no se manda entero.
/// El resto —las oraciones con un año, un siglo, una década— se agrupa en
/// pasajes con la oración anterior de contexto, se parte lo que no entre en un
/// pedido y se reparte en pedidos en el orden del texto.
///
/// [markdown] dice cómo se parte el texto en oraciones (`splitStudySentences`).
List<DatedTextPart> selectDatedParts(
  String text, {
  required int maxChars,
  bool markdown = false,
}) {
  assert(maxChars > kDatedPassageOverheadChars * 2, 'Un pedido tiene lugar.');
  final expressions = findTemporalExpressions(text);
  if (expressions.isEmpty) return const [];

  final sentences = splitStudySentences(text, markdown: markdown);
  final runs = _runsOf(text, sentences, expressions);

  final passages = <DatedPassage>[
    for (final run in runs)
      ..._fitted(text, run, expressions, maxChars - kDatedPassageOverheadChars),
  ];
  return _packed(passages, maxChars);
}

/// Un tramo contiguo del texto, `[start, end)`, que va junto al modelo.
typedef _Run = ({int start, int end});

/// Los tramos con las oraciones que tienen una expresión de tiempo, cada una
/// con la anterior si sirve de contexto. Las que se tocan se juntan.
List<_Run> _runsOf(
  String text,
  List<StudySentence> sentences,
  List<TemporalExpression> expressions,
) {
  // Qué oración tiene cada expresión, y hasta dónde llega la que se pasa del
  // final de su oración.
  final firstSentence = <int>[];
  final reach = <int, int>{};
  for (final e in expressions) {
    final index = _sentenceAt(sentences, e.start);
    if (index == null) continue;
    if (firstSentence.isEmpty || firstSentence.last != index) {
      firstSentence.add(index);
    }
    reach[index] = math.max(reach[index] ?? 0, e.end);
  }

  final runs = <({int first, int last, int end})>[];
  for (final index in firstSentence) {
    final first = _hasContext(text, sentences, index) ? index - 1 : index;
    final end = math.max(sentences[index].end, reach[index]!);
    if (runs.isNotEmpty && first <= runs.last.last + 1) {
      final previous = runs.removeLast();
      runs.add((
        first: previous.first,
        last: index,
        end: math.max(previous.end, end),
      ));
    } else {
      runs.add((first: first, last: index, end: end));
    }
  }
  return [for (final r in runs) (start: sentences[r.first].start, end: r.end)];
}

/// La oración que contiene [offset], o `null` si cae entre dos: en una marca
/// de comienzo de renglón, por ejemplo.
int? _sentenceAt(List<StudySentence> sentences, int offset) {
  var low = 0;
  var high = sentences.length - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    final sentence = sentences[mid];
    if (offset < sentence.start) {
      high = mid - 1;
    } else if (offset >= sentence.end) {
      low = mid + 1;
    } else {
      return mid;
    }
  }
  return null;
}

/// Si la oración anterior a [index] sirve de contexto: existe, no es larguísima
/// y está en el mismo párrafo.
bool _hasContext(String text, List<StudySentence> sentences, int index) {
  if (index == 0) return false;
  final previous = sentences[index - 1];
  if (previous.length > kMaxContextSentenceChars) return false;
  final between = text.substring(previous.end, sentences[index].start);
  return !_paragraphBreak.hasMatch(between);
}

final _paragraphBreak = RegExp(r'\n[ \t]*\n');

/// El tramo [run] como pasajes de hasta [maxChars]: uno solo si entra; si no,
/// cortado como se cortan los textos largos (`splitIntoParts`), y sin los
/// pedazos que se quedaron sin ninguna fecha.
Iterable<DatedPassage> _fitted(
  String text,
  _Run run,
  List<TemporalExpression> expressions,
  int maxChars,
) sync* {
  final pieces = run.end - run.start <= maxChars
      ? [TextPart(start: run.start, text: text.substring(run.start, run.end))]
      : [
          for (final part in splitIntoParts(
            text.substring(run.start, run.end),
            maxChars: maxChars,
          ))
            TextPart(start: run.start + part.start, text: part.text),
        ];
  for (final piece in pieces) {
    final inside = _within(expressions, piece.start, piece.end);
    if (inside.isNotEmpty) {
      yield DatedPassage(
        start: piece.start,
        text: piece.text,
        expressions: inside,
      );
    }
  }
}

/// Las expresiones de [expressions] —en orden y sin pisarse— que caen
/// enteras en `[start, end)`.
List<TemporalExpression> _within(
  List<TemporalExpression> expressions,
  int start,
  int end,
) {
  // La primera que empieza en `start` o después, buscada a mitades: un libro
  // tiene decenas de miles de expresiones y miles de pasajes.
  var low = 0;
  var high = expressions.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (expressions[mid].start < start) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  final inside = <TemporalExpression>[];
  for (var i = low; i < expressions.length; i++) {
    final e = expressions[i];
    if (e.start >= end) break;
    if (e.end <= end) inside.add(e);
  }
  return inside;
}

/// Los [passages] repartidos, en orden, en pedidos de hasta [maxChars]
/// caracteres contando lo que cada pasaje suma al pedido, y de hasta
/// [maxPassagesPerPart] pasajes.
List<DatedTextPart> _packed(List<DatedPassage> passages, int maxChars) {
  final perPart = maxPassagesPerPart(maxChars);
  final parts = <DatedTextPart>[];
  var current = <DatedPassage>[];
  var used = 0;
  for (final passage in passages) {
    final cost = passage.text.length + kDatedPassageOverheadChars;
    if (current.isNotEmpty &&
        (used + cost > maxChars || current.length >= perPart)) {
      parts.add(DatedTextPart(current));
      current = [];
      used = 0;
    }
    current.add(passage);
    used += cost;
  }
  if (current.isNotEmpty) parts.add(DatedTextPart(current));
  return parts;
}
