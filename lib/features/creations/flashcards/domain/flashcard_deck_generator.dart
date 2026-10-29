import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/domain/deck_review.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_prompt.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_items.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Genera un mazo de «Tarjetas didácticas» (F43, paso 8).
///
/// 1. **Las tarjetas**, con [writeStudyItems]: de una vez o por partes, con el
///    número, la dificultad, el tema y el idioma elegidos.
/// 2. **Las ilustraciones**, si se pidió «Incluir imágenes»: unas pocas con
///    IA —con la cuenta elegida en «Con tu IA actual»—; si no se puede, se
///    dice por qué en el visor y van los dibujos de la app. Nunca hacen fallar
///    el mazo.
/// 3. **«Sumar a mi repaso»** (decisión F, prendido de fábrica): las tarjetas
///    quedan en su documento procesado y entran en «Para hoy». Va al final,
///    después de lo último que se puede cancelar: un mazo cancelado no deja
///    tarjetas sueltas en el repaso.
class FlashcardDeckGenerator extends CreationGenerator {
  const FlashcardDeckGenerator({
    required DeckReview review,
    required StudyIllustrator Function() illustrator,
  }) : _review = review,
       _illustrator = illustrator;

  final DeckReview _review;
  final StudyIllustrator Function() _illustrator;

  @override
  StudyCreationKind get kind => StudyCreationKind.flashcards;

  @override
  int maxOutputTokens(CreationJob job) => deckExpectedOutputTokens(job.options);

  /// Lo que se reserva para la respuesta es lo de las tarjetas que entran en
  /// esta ventana: con Gemma, unas ocho; con un modelo grande, todas.
  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: studyItemsReplyTokens(
          _request(job, severalSources: true),
          contextTokens,
        ),
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final options = job.options;
    final illustrated = options[CreationOptionValues.images] == true;
    final batch = await writeStudyItems(
      request: _request(job, severalSources: material.sources.length > 1),
      job: job,
      material: material,
      writer: writer,
      progress: progress,
      share: illustrated ? 0.7 : 0.95,
    );
    var deck = FlashcardDeck(
      title: batch.title,
      cards: [
        for (final (index, card) in batch.items.indexed)
          card.copyWith(id: 'c${index + 1}'),
      ],
    );

    if (illustrated) deck = await _illustrate(deck, job, progress);

    if (job.cancellation.isCancelled) throw const CreationCancelledException();
    if (options[DeckOptionKeys.addToReview] != false) {
      progress(0.97, CreationStep.finishing);
      final added = await _review.add(
        deck,
        fallbackDocument: material.sourceIds.firstOrNull,
      );
      deck = added.getOrElse(
        (failure) => throw StateError('No se sumó al repaso: $failure'),
      );
    }
    return CreationOutput(
      title: deck.title,
      content: FlashcardDeckJson.encodeString(deck),
    );
  }

  StudyItemsRequest<DeckCard> _request(
    CreationJob job, {
    required bool severalSources,
  }) {
    final options = job.options;
    final illustrated = options[CreationOptionValues.images] == true;
    final topic = '${options[CreationOptionKeys.topic] ?? ''}';
    return StudyItemsRequest(
      count: deckCardCount(options),
      tokensPerItem: deckTokensPerCard(options),
      task: (count, {required part}) => deckTask(
        count: count,
        difficulty: options[CreationOptionValues.difficulty],
        illustrated: illustrated,
        severalSources: severalSources && !part,
        topic: topic,
        part: part,
        illustrations: deckIllustrationCount(options),
      ),
      schema: deckSchema(
        illustrated: illustrated,
        severalSources: severalSources,
      ),
      parse: (json) {
        final deck = FlashcardDeckJson.parse(json);
        return StudyItemBatch(title: deck.title, items: deck.cards);
      },
    );
  }

  /// Las ilustraciones con IA de las tarjetas que la IA propuso dibujar,
  /// hasta el tope del mazo; lo que no sale queda dicho.
  Future<FlashcardDeck> _illustrate(
    FlashcardDeck deck,
    CreationJob job,
    CreationProgressReport progress,
  ) async {
    final limit = deckIllustrationCount(job.options);
    final wanted = [
      for (final card in deck.cards)
        if (card.illustrationPrompt.isNotEmpty)
          (card.id, card.illustrationPrompt),
    ].take(limit).toList();
    if (wanted.isEmpty) return deck;
    final drawn = await _illustrator()(
      creationId: job.creation.id,
      wanted: wanted,
      cancellation: job.cancellation,
      accountId: _accountOf(job),
      onDrawn: (done, total) =>
          progress(0.7 + 0.25 * done / total, CreationStep.finishing),
    );
    return FlashcardDeck(
      title: deck.title,
      inReview: deck.inReview,
      illustrationFailure: drawn.failure,
      illustrationAccount: drawn.account,
      cards: [
        for (final card in deck.cards)
          if (drawn.references[card.id] case final reference?)
            card.copyWith(illustrationRef: reference)
          else
            card,
      ],
    );
  }
}

String? _accountOf(CreationJob job) {
  final id = job.options[CreationOptionKeys.imageAccountId];
  return id is String && id.isNotEmpty ? id : null;
}
