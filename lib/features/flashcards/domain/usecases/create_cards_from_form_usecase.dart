import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';

/// Crea las tarjetas de lo que la persona llenó en el formulario (F31,
/// decisión 73): cada [CardForm] sabe cuántas tarjetas es y cómo se guardan.
///
/// Todas las formas se guardan **enteras o ninguna**: las dos direcciones y los
/// huecos van por `createSiblings` (una transacción), y una sola tarjeta es una
/// sola escritura. Un texto con un solo hueco no necesita hermanas y se guarda
/// como una tarjeta suelta (un grupo pide al menos dos).
class CreateCardsFromFormUseCase {
  const CreateCardsFromFormUseCase(this._flashcards);

  final FlashcardRepository _flashcards;

  /// [sourceCharStart] y [sourceCharEnd] dicen de qué fragmento de la fuente
  /// salen las tarjetas de huecos (las que propone la IA a partir de un texto);
  /// las demás formas no los usan.
  Future<Either<Failure, List<Flashcard>>> call({
    required String itemId,
    required CardForm form,
    int? sourceCharStart,
    int? sourceCharEnd,
  }) async {
    switch (form) {
      case QaCardForm():
        return (await _flashcards.create(
          itemId: itemId,
          front: form.front,
          back: form.back,
        )).map((card) => [card]);
      case BothDirectionsCardForm():
        return _flashcards.createSiblings(
          itemId: itemId,
          drafts: SiblingCardDraft.bothDirections(
            front: form.front.trim(),
            back: form.back.trim(),
          ),
        );
      case TypedCardForm():
        return (await _flashcards.create(
          itemId: itemId,
          front: form.front,
          back: form.back,
          kind: FlashcardKind.typedAnswer,
        )).map((card) => [card]);
      case MultipleChoiceCardForm():
        return (await _flashcards.createMultipleChoice(
          itemId: itemId,
          front: form.question,
          options: [
            FlashcardOptionDraft(content: form.correct, isCorrect: true),
            for (final distractor in form.distractors)
              FlashcardOptionDraft(content: distractor, isCorrect: false),
          ],
        )).map((card) => [card]);
      case ClozeCardForm():
        final parsed = parseCloze(form.text);
        final problems = validateCloze(form.text);
        if (problems.isNotEmpty) {
          return left(
            Failure.validation(message: clozeProblemMessage(problems.first)),
          );
        }
        final numbers = parsed.numbers;
        if (numbers.length == 1) {
          return (await _flashcards.create(
            itemId: itemId,
            front: form.text,
            back: form.extra,
            kind: FlashcardKind.cloze,
            clozeIndex: numbers.single,
            sourceCharStart: sourceCharStart,
            sourceCharEnd: sourceCharEnd,
          )).map((card) => [card]);
        }
        return _flashcards.createSiblings(
          itemId: itemId,
          drafts: [
            for (final number in numbers)
              SiblingCardDraft(
                front: form.text.trim(),
                back: form.extra.trim(),
                kind: FlashcardKind.cloze,
                clozeIndex: number,
                sourceCharStart: sourceCharStart,
                sourceCharEnd: sourceCharEnd,
              ),
          ],
        );
    }
  }
}
