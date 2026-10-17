import 'package:meta/meta.dart';

/// Una tarjeta que hizo la IA, como se la da a revisar a otro modelo (F33):
/// la pregunta, la respuesta y el pasaje del texto del que sale.
@immutable
class FlashcardToReview {
  const FlashcardToReview({
    required this.front,
    required this.back,
    required this.passage,
  });

  final String front;
  final String back;

  /// El pedazo del texto del elemento alrededor de donde la tarjeta dice
  /// salir (`passageForReview`). Es contra lo que el modelo la juzga.
  final String passage;
}

/// Lo que el modelo revisor dice de una tarjeta que está mal (F33). Las que
/// están bien no traen veredicto: no hay nada que proponer.
@immutable
sealed class FlashcardVerdict {
  const FlashcardVerdict({required this.index, required this.reason});

  /// Cuál de las tarjetas que se le dieron, desde 0.
  final int index;

  /// Por qué, en una línea del modelo.
  final String reason;
}

/// Corregirla: la pregunta y la respuesta como deberían quedar.
final class FlashcardCorrection extends FlashcardVerdict {
  const FlashcardCorrection({
    required super.index,
    required super.reason,
    required this.front,
    required this.back,
  });

  final String front;
  final String back;

  @override
  bool operator ==(Object other) =>
      other is FlashcardCorrection &&
      other.index == index &&
      other.reason == reason &&
      other.front == front &&
      other.back == back;

  @override
  int get hashCode => Object.hash(index, reason, front, back);

  @override
  String toString() => 'FlashcardCorrection($index, $front | $back; $reason)';
}

/// Sacarla: está mal y no tiene arreglo, o el pasaje no la respalda.
final class FlashcardRemoval extends FlashcardVerdict {
  const FlashcardRemoval({required super.index, required super.reason});

  @override
  bool operator ==(Object other) =>
      other is FlashcardRemoval &&
      other.index == index &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(index, reason);

  @override
  String toString() => 'FlashcardRemoval($index; $reason)';
}

/// Revisa tarjetas que hizo la IA, con el modelo de lenguaje elegido (F33,
/// «Revisar con otro modelo»): dice cuáles hay que corregir —y cómo— y cuáles
/// sacar. Nunca agrega tarjetas, y nunca guarda nada: lo que dice queda como
/// propuesta, para que la persona decida.
// ignore: one_member_abstracts
abstract interface class FlashcardReviewer {
  /// Los veredictos sobre [cards], solo de las que están mal. Lista vacía si
  /// están todas bien, o si el modelo no contestó nada que se pudiera leer:
  /// lo que no se entiende no se propone.
  Future<List<FlashcardVerdict>> reviewFlashcards(
    List<FlashcardToReview> cards,
  );
}

/// El pasaje de [text] que se le muestra al revisor para una tarjeta de
/// [start] a [end] —el lugar donde se ubicó su cita—, de unos [chars]
/// caracteres, con la cita en el medio y cortado en un espacio para no partir
/// palabras. Sin lugar, el principio del texto, que en una nota corta es el
/// texto entero.
String passageForReview(
  String text, {
  required int? start,
  required int? end,
  required int chars,
}) {
  if (text.length <= chars) return text.trim();
  final from = start == null || start < 0 || start > text.length ? 0 : start;
  final to = end == null || end < from || end > text.length ? from : end;
  final margin = ((chars - (to - from)) / 2).floor().clamp(0, chars);
  var left = (from - margin).clamp(0, text.length);
  var right = (to + margin).clamp(0, text.length);
  // Lo que sobra de un lado se usa del otro.
  if (left == 0) right = chars.clamp(0, text.length);
  if (right == text.length) left = (text.length - chars).clamp(0, text.length);

  var passage = text.substring(left, right);
  if (left > 0) {
    final space = passage.indexOf(' ');
    if (space >= 0 && space < 40) passage = passage.substring(space + 1);
    passage = '…$passage';
  }
  if (right < text.length) {
    final space = passage.lastIndexOf(' ');
    if (space >= 0 && passage.length - space < 40) {
      passage = passage.substring(0, space);
    }
    passage = '$passage…';
  }
  return passage.trim();
}
