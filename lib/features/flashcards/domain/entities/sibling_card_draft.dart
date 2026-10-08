import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';

/// Una de las tarjetas hermanas de un grupo que se crea de una vez (F31): las
/// dos direcciones de una pregunta, o los huecos de un texto.
///
/// Las hermanas de un grupo comparten `group_id` y, para la cola de estudio, no
/// se estudian el mismo día.
@immutable
class SiblingCardDraft {
  const SiblingCardDraft({
    required this.front,
    required this.back,
    this.kind = FlashcardKind.freeRecall,
    this.clozeIndex,
    this.sourceCharStart,
    this.sourceCharEnd,
  });

  /// Las dos direcciones de una pregunta: la tarjeta de ida y la de vuelta,
  /// con el frente y el reverso cambiados.
  static List<SiblingCardDraft> bothDirections({
    required String front,
    required String back,
    FlashcardKind kind = FlashcardKind.freeRecall,
  }) => [
    SiblingCardDraft(front: front, back: back, kind: kind),
    SiblingCardDraft(front: back, back: front, kind: kind),
  ];

  /// Los huecos de un texto: una tarjeta por cada número de hueco de
  /// [clozeNumbers] (1, 2…), todas con el mismo [text] —el texto ENTERO con sus
  /// huecos marcados— y [extra] como complemento opcional. Qué huecos tiene un
  /// texto lo dice quien lo analiza; esto solo arma las tarjetas.
  static List<SiblingCardDraft> clozes({
    required String text,
    required Iterable<int> clozeNumbers,
    String extra = '',
  }) => [
    for (final number in clozeNumbers)
      SiblingCardDraft(
        front: text,
        back: extra,
        kind: FlashcardKind.cloze,
        clozeIndex: number,
      ),
  ];

  final String front;
  final String back;
  final FlashcardKind kind;

  /// En una tarjeta `cloze`, cuál hueco tapa (desde 1).
  final int? clozeIndex;

  final int? sourceCharStart;
  final int? sourceCharEnd;
}
