import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/citations/data/services/fragment_locator_resolver.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_path.dart';
import 'package:sinapsis/features/export/domain/services/anki_text_export.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';

/// Exporta el mazo de flashcards de la bóveda a un `.apkg` de Anki, en
/// subdecks por su Tema (F17, D1/D2), con la procedencia de cada tarjeta en
/// el reverso (F17, commit 3) e incremental por defecto (F17, D4).
///
/// A diferencia de `ExportItemUseCase`, no exporta un elemento sino todas
/// las tarjetas a la vez: es un mazo, no un documento suelto.
class ExportFlashcardsToAnkiUseCase
    implements UseCase<Unit, ExportFlashcardsToAnkiParams> {
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
  Future<Either<Failure, Unit>> call(
    ExportFlashcardsToAnkiParams params,
  ) async {
    final found = params.exportAll
        ? await _flashcards.getAll()
        : await _flashcards.getPendingExport();

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

      final exports = <AnkiCardExport>[];
      for (final card in cards) {
        final answerAndDistractors = await _answerAndDistractorsOf(card);
        // `null`: una tarjeta de opción múltiple con una forma que este
        // mazo no sabe mapear fielmente (ver el doc comment de
        // `_answerAndDistractorsOf`) — queda afuera del archivo, y afuera
        // de `markExported` más abajo, así que el próximo incremental la
        // vuelve a intentar en vez de darla por exportada sin haberlo
        // estado.
        if (answerAndDistractors == null) continue;
        exports.add(
          AnkiCardExport(
            card: card,
            deckPath: ankiDeckPathOf(
              firstTopicValueId: resolution.firstTopicByItem[card.itemId],
              temaTree: resolution.tree,
              labelOf: resolution.labelOf,
            ),
            answer: answerAndDistractors.answer,
            distractors: answerAndDistractors.distractors,
            provenance: _provenanceOf(
              citationSourceByItem[card.itemId],
              locatorByCard[card.id],
              form,
            ),
          ),
        );
      }
      final Uint8List bytes;
      final String fileName;
      switch (params.format) {
        case AnkiExportFormat.apkg:
          bytes = await _builder.build(exports);
          fileName = 'sinapsis.apkg';
        case AnkiExportFormat.tsv:
          bytes = buildAnkiTextExport(exports, AnkiTextFormat.tsv);
          fileName = 'sinapsis.tsv';
        case AnkiExportFormat.csv:
          bytes = buildAnkiTextExport(exports, AnkiTextFormat.csv);
          fileName = 'sinapsis.csv';
      }
      await _saver.saveFile(fileName: fileName, bytes: bytes);

      // Recién ahora, con el archivo ya guardado, quedan marcadas como
      // exportadas (F17, D4): un fallo acá no deshace el guardado, pero sí
      // se avisa —dejarlo pasar en silencio repetiría estas mismas
      // tarjetas en el próximo incremental sin que nadie se entere—. Solo
      // las que de verdad entraron en `exports` (F20): una excluida por no
      // poder mapearse fiel no puede quedar marcada como exportada sin
      // haberlo estado.
      final marked = await _flashcards.markExported({
        for (final export in exports) export.card.id,
      });
      final markFailure = marked.getLeft().toNullable();
      if (markFailure != null) return left(markFailure);

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

  /// Cuántos distractores como máximo trae el segundo modelo de nota de
  /// `AnkiPackageBuilder` (F20, commit 9): tres campos fijos, uno por
  /// distractor. Es el mismo tope que `DistractorSourcer.sourceDistractors`
  /// ya pide por defecto, así que ninguna pregunta armada por
  /// `GenerateQuizUseCase` lo pasa hoy — queda acá igual, para no exportar
  /// a medias si algún día una pregunta trae más.
  static const _maxDistractors = 3;

  /// La respuesta y los distractores de [card], según su forma (F20).
  /// `freeRecall`/`trueFalse`: `card.back` tal cual, sin distractores.
  /// `multipleChoice`: la opción marcada correcta como respuesta, el resto
  /// como distractores —`card.back` queda vacío para esta forma, no sirve—.
  ///
  /// `null` si la pregunta no se puede mapear fielmente al segundo modelo:
  /// sin ninguna opción, sin ninguna marcada correcta, o con más
  /// distractores de los que el modelo tiene campos —nunca pasa hoy, ver
  /// [_maxDistractors]—. Mejor dejarla afuera del mazo, señalado en el
  /// comentario de quien llama, que exportar una tarjeta rota o
  /// recortada a medias.
  Future<({String answer, List<String> distractors})?> _answerAndDistractorsOf(
    Flashcard card,
  ) async {
    if (card.kind != FlashcardKind.multipleChoice) {
      return (answer: card.back, distractors: const <String>[]);
    }

    final result = await _flashcards.optionsFor(card.id);
    final options = result.getRight().toNullable() ?? const [];
    final correct = options.where((o) => o.isCorrect);
    if (correct.length != 1) return null;

    final distractors = [
      for (final option in options)
        if (!option.isCorrect) option.content,
    ];
    if (distractors.isEmpty || distractors.length > _maxDistractors) {
      return null;
    }

    return (answer: correct.single.content, distractors: distractors);
  }
}

/// En qué archivo termina el mazo (F17, commit 5): el paquete completo, o
/// el camino alternativo de texto plano —D5, para cuando el `.apkg` no
/// sirve—.
enum AnkiExportFormat { apkg, tsv, csv }

/// Qué tanto del mazo exportar (F17, D4) y en qué formato (commit 5). Por
/// defecto, solo lo que nunca se exportó —[exportAll] en falso—; en verdad
/// exportarlo TODO de nuevo es una opción aparte, para quien cambia de
/// dispositivo Anki o necesita resincronizar por completo.
final class ExportFlashcardsToAnkiParams {
  const ExportFlashcardsToAnkiParams({
    this.exportAll = false,
    this.format = AnkiExportFormat.apkg,
  });

  final bool exportAll;
  final AnkiExportFormat format;
}
