import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_path.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';

/// Exporta todo el mazo de flashcards de la bóveda a un `.apkg` de Anki, en
/// subdecks por su Tema (F17, D1/D2).
///
/// A diferencia de `ExportItemUseCase`, no exporta un elemento sino todas
/// las tarjetas a la vez: es un mazo, no un documento suelto.
class ExportFlashcardsToAnkiUseCase implements UseCase<Unit, NoParams> {
  const ExportFlashcardsToAnkiUseCase({
    required FlashcardRepository flashcards,
    required AnkiTopicResolver topics,
    required AnkiDeckBuilder builder,
    required FileSaver saver,
  }) : _flashcards = flashcards,
       _topics = topics,
       _builder = builder,
       _saver = saver;

  final FlashcardRepository _flashcards;
  final AnkiTopicResolver _topics;
  final AnkiDeckBuilder _builder;
  final FileSaver _saver;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final found = await _flashcards.getAll();

    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final cards = found.getRight().toNullable() ?? const [];

    try {
      final resolution = await _topics.resolve({
        for (final card in cards) card.itemId,
      });
      final exports = [
        for (final card in cards)
          AnkiCardExport(
            card: card,
            deckPath: ankiDeckPathOf(
              firstTopicValueId: resolution.firstTopicByItem[card.itemId],
              temaTree: resolution.tree,
              labelOf: resolution.labelOf,
            ),
          ),
      ];
      final bytes = await _builder.build(exports);
      await _saver.saveFile(fileName: 'sinapsis.apkg', bytes: bytes);
      return right(unit);
      // El armado del paquete o el diálogo de guardado pueden fallar por
      // motivos que no tienen un tipo propio, igual que en
      // `ExportItemUseCase`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}
