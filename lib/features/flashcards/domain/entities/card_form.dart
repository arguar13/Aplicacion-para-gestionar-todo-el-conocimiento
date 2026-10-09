import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer_alternatives.dart';

/// Lo que la persona llenó al crear o editar una tarjeta (F31, decisión 73):
/// una forma por cada tipo de tarjeta que se arma a mano. Es el puente entre
/// el formulario y el repositorio —el formulario no sabe cómo se guarda cada
/// forma, y el repositorio no sabe de pantallas—.
@immutable
sealed class CardForm {
  const CardForm();

  /// Cuántas tarjetas salen de esta forma.
  int get cardCount;
}

/// Pregunta y respuesta libres: una tarjeta.
class QaCardForm extends CardForm {
  const QaCardForm({required this.front, required this.back});

  final String front;
  final String back;

  @override
  int get cardCount => 1;
}

/// Las dos direcciones: pregunta → respuesta y respuesta → pregunta, como dos
/// tarjetas hermanas.
class BothDirectionsCardForm extends CardForm {
  const BothDirectionsCardForm({required this.front, required this.back});

  final String front;
  final String back;

  @override
  int get cardCount => 2;
}

/// Un texto con huecos (`El {{c1::Imperio}} cayó en {{c2::476}}`): una tarjeta
/// por cada número de hueco, y [extra] como complemento opcional.
class ClozeCardForm extends CardForm {
  const ClozeCardForm({required this.text, this.extra = ''});

  final String text;
  final String extra;

  /// Los números de hueco que tiene [text] (vacío si no se puede leer).
  List<int> get numbers => parseCloze(text).numbers;

  /// Lo que está mal escrito, listo para mostrar (vacío si el texto sirve).
  List<ClozeProblem> get problems => validateCloze(text);

  @override
  int get cardCount => numbers.length;
}

/// «Escribí la respuesta»: la persona escribe la respuesta y se la compara con
/// [answer] y con las [alternatives] que también valen.
class TypedCardForm extends CardForm {
  const TypedCardForm({
    required this.front,
    required this.answer,
    this.alternatives = const [],
  });

  final String front;
  final String answer;
  final List<String> alternatives;

  /// Lo que se guarda en `back` (ver [TypedAnswerSpec]).
  String get back => TypedAnswerSpec.of(answer, alternatives).encoded;

  @override
  int get cardCount => 1;
}

/// Una pregunta de opción múltiple armada a mano: la respuesta correcta y al
/// menos un distractor.
class MultipleChoiceCardForm extends CardForm {
  const MultipleChoiceCardForm({
    required this.question,
    required this.correct,
    required this.distractors,
  });

  final String question;
  final String correct;
  final List<String> distractors;

  @override
  int get cardCount => 1;
}
