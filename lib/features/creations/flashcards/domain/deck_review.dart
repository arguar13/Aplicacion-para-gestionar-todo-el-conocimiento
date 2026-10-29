import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/services/ai_rejection_fingerprint.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';

/// «Sumar a mi repaso» (F43, paso 8, decisión F): las tarjetas de un mazo
/// quedan en su documento procesado como cualquier tarjeta suya —las mismas
/// que muestra «Tarjetas de repaso» en Procesado y que cuenta «Para hoy»—, con
/// el calendario de siempre.
///
/// - **Sumar** crea en su documento la tarjeta de cada una que no la tiene y
///   anota cuál es. Es idempotente: una que ya tiene la suya no se vuelve a
///   crear, y una cuya pregunta el documento ya tiene —la misma, sin
///   mayúsculas ni tildes— se une a esa en vez de duplicarla. Una que se había
///   sacado vuelve con su historia.
/// - **Sacar** las pausa (`FlashcardRepository.suspend`): dejan de entrar en
///   «Para hoy», pero no se borra nada —ni la tarjeta ni lo que se repasó—, y
///   sumarlas de nuevo las trae como estaban.
///
/// Una tarjeta sin documento (el de un mazo muy viejo) va al documento de
/// la creación que se le dé (`fallbackDocument`).
class DeckReview {
  const DeckReview({required FlashcardRepository Function() flashcards})
    : _flashcards = flashcards;

  final FlashcardRepository Function() _flashcards;

  /// Suma [deck] al repaso; devuelve el mazo con cada tarjeta unida a la suya
  /// y prendido.
  Future<Either<Failure, FlashcardDeck>> add(
    FlashcardDeck deck, {
    required String? fallbackDocument,
  }) async {
    final repository = _flashcards();
    final byDocument = <String, List<Flashcard>>{};
    final cards = <DeckCard>[];
    final toResume = <String>{};
    for (final card in deck.cards) {
      final documentId = card.documentId ?? fallbackDocument;
      if (documentId == null) {
        cards.add(card);
        continue;
      }
      final existing = byDocument[documentId] ??= [
        ...await repository.watchForItem(documentId).first,
      ];
      final linked = _find(existing, card);
      if (linked != null) {
        if (linked.suspended) toResume.add(linked.id);
        cards.add(
          card.copyWith(documentId: documentId, flashcardId: linked.id),
        );
        continue;
      }
      final created = await repository.create(
        itemId: documentId,
        front: card.front,
        back: card.back,
      );
      switch (created) {
        case Left(:final value):
          return left(value);
        case Right(:final value):
          existing.add(value);
          cards.add(
            card.copyWith(documentId: documentId, flashcardId: value.id),
          );
      }
    }
    final resumed = await repository.unsuspend(toResume);
    if (resumed case Left(:final value)) return left(value);
    return right(deck.copyWith(cards: cards, inReview: true));
  }

  /// Saca [deck] del repaso: pausa sus tarjetas y lo deja apagado.
  Future<Either<Failure, FlashcardDeck>> remove(FlashcardDeck deck) async {
    final ids = {
      for (final card in deck.cards)
        if (card.flashcardId case final id?) id,
    };
    final paused = await _flashcards().suspend(ids);
    return paused.map((_) => deck.copyWith(inReview: false));
  }

  /// La tarjeta de [card] entre las de su documento: la que anotó, o una con
  /// su misma pregunta.
  static Flashcard? _find(List<Flashcard> existing, DeckCard card) {
    if (card.flashcardId case final id?) {
      for (final flashcard in existing) {
        if (flashcard.id == id) return flashcard;
      }
    }
    final fingerprint = card.fingerprint;
    for (final flashcard in existing) {
      if (flashcardRejectionFingerprint(flashcard.front) == fingerprint) {
        return flashcard;
      }
    }
    return null;
  }
}
