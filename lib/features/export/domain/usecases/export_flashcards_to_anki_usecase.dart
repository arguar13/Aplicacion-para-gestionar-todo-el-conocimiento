import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/citations/data/services/fragment_locator_resolver.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_path.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';

/// Exporta todo el mazo de flashcards de la bóveda a un `.apkg` de Anki, en
/// subdecks por su Tema (F17, D1/D2), con la procedencia de cada tarjeta en
/// el reverso (F17, commit 3).
///
/// A diferencia de `ExportItemUseCase`, no exporta un elemento sino todas
/// las tarjetas a la vez: es un mazo, no un documento suelto.
class ExportFlashcardsToAnkiUseCase implements UseCase<Unit, NoParams> {
  const ExportFlashcardsToAnkiUseCase({
    required FlashcardRepository flashcards,
    required AnkiTopicResolver topics,
    required BibliographyRepository bibliography,
    required FragmentLocatorResolver locator,
    required ReferenceStyle citationStyle,
    required CitationLanguage citationLanguage,
    required AnkiDeckBuilder builder,
    required FileSaver saver,
  }) : _flashcards = flashcards,
       _topics = topics,
       _bibliography = bibliography,
       _locator = locator,
       _citationStyle = citationStyle,
       _citationLanguage = citationLanguage,
       _builder = builder,
       _saver = saver;

  final FlashcardRepository _flashcards;
  final AnkiTopicResolver _topics;
  final BibliographyRepository _bibliography;
  final FragmentLocatorResolver _locator;
  final ReferenceStyle _citationStyle;
  final CitationLanguage _citationLanguage;
  final AnkiDeckBuilder _builder;
  final FileSaver _saver;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final found = await _flashcards.getAll();

    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final cards = found.getRight().toNullable() ?? const [];

    try {
      final itemIds = {for (final card in cards) card.itemId};
      final resolution = await _topics.resolve(itemIds);

      // Fuentes citables por elemento (F15): una nota manual o un elemento
      // que ya no existe no trae fila, `sourcesOf` las deja afuera sola —el
      // mismo criterio que `citeFragment`, «una nota no se cita»—.
      final citationSourceByItem = {
        for (final bibliographySource in await _bibliography.sourcesOf(itemIds))
          bibliographySource.itemId: bibliographySource.source,
      };

      // El locator (página o minuto) de cada tarjeta con un rango real, en
      // una sola consulta por lotes —no una por tarjeta—.
      final locatorByCard = await _locator.locateMany([
        for (final card in cards)
          if (card.hasSourceRange)
            (
              key: card.id,
              itemId: card.itemId,
              charOffset: card.sourceCharStart!,
            ),
      ]);

      // La misma regla que `citeFragment` (F15) para elegir la forma: la
      // nota al pie en un estilo de notas —Chicago—, la cita en el texto en
      // los demás. El reverso de una tarjeta es una vista suelta, igual que
      // el portapapeles, nunca una nota al pie de verdad.
      final form = _citationStyle.forms.contains(CitationForm.note)
          ? CitationForm.note
          : CitationForm.inText;

      final exports = [
        for (final card in cards)
          AnkiCardExport(
            card: card,
            deckPath: ankiDeckPathOf(
              firstTopicValueId: resolution.firstTopicByItem[card.itemId],
              temaTree: resolution.tree,
              labelOf: resolution.labelOf,
            ),
            provenance: _provenanceOf(
              citationSourceByItem[card.itemId],
              locatorByCard[card.id],
              form,
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

  /// La cita de [source], como texto plano —el campo de Anki no distingue
  /// cursiva de texto normal salvo que se le pida en HTML, y el portapapeles
  /// de F15 ya resuelve el mismo compromiso con `Citation.toPlainText`—.
  /// `null` sin fuente citable.
  String? _provenanceOf(
    CitationSource? source,
    CitationLocator? locator,
    CitationForm form,
  ) {
    if (source == null) return null;
    final citation = _citationStyle.format(
      form,
      source,
      CitationContext(language: _citationLanguage, locator: locator),
    );
    final text = citation.toPlainText();
    return text.isEmpty ? null : text;
  }
}
