import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';

/// Dónde caen las tarjetas que se traen de Anki (F31, decisión 73).
enum AnkiImportDestination {
  /// Un elemento por cada mazo de Anki, con el nombre del mazo y sus niveles
  /// (`Historia::Roma` → «Historia › Roma») como etiquetas. Es lo más parecido
  /// a cómo estaban organizadas en Anki.
  perDeck,

  /// Todas en un solo elemento, «Importado de Anki».
  singleItem,
}

/// El nombre del elemento y de la etiqueta con que se marcan las tarjetas
/// traídas de Anki.
const kAnkiImportedName = 'Importado de Anki';

/// Una tarjeta lista para guardarse: ya traducida del mundo de Anki al de
/// Sinapsis, con su calendario mapeado a SM-2 (decisión 73).
@immutable
class AnkiPlannedCard {
  const AnkiPlannedCard({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.front,
    required this.back,
    required this.createdAt,
    required this.dueAt,
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    this.lastReviewedAt,
    this.learningStep,
    this.suspended = false,
    this.buriedUntil,
    this.groupId,
    this.clozeIndex,
    this.choiceDistractors = const [],
  });

  /// Determinista a partir de la nota y la plantilla de Anki: traer dos veces
  /// el mismo paquete da el mismo `id`, y es lo que evita duplicar.
  final String id;
  final String itemId;
  final FlashcardKind kind;
  final String front;

  /// En opción múltiple, la respuesta correcta (la tarjeta guarda `back` vacío
  /// y la respuesta vive en sus opciones).
  final String back;
  final DateTime createdAt;
  final DateTime dueAt;
  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime? lastReviewedAt;
  final int? learningStep;
  final bool suspended;
  final DateTime? buriedUntil;
  final String? groupId;
  final int? clozeIndex;

  /// Solo en opción múltiple: las opciones incorrectas, en orden.
  final List<String> choiceDistractors;
}

/// Un elemento donde caen tarjetas, con las que se le suman.
@immutable
class AnkiPlannedItem {
  const AnkiPlannedItem({
    required this.id,
    required this.title,
    required this.tags,
    required this.cards,
    this.description = '',
  });

  /// Determinista: reimportar suma al mismo elemento en vez de crear otro.
  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final List<AnkiPlannedCard> cards;
}

/// Lo que va a escribir una importación, entero.
@immutable
class AnkiImportPlan {
  const AnkiImportPlan({
    required this.items,
    required this.alreadyImported,
    required this.unusable,
  });

  /// Los elementos con tarjetas por traer (uno sin tarjetas nuevas no está).
  final List<AnkiPlannedItem> items;

  /// Cuántas tarjetas del paquete ya estaban en la bóveda.
  final int alreadyImported;

  /// Cuántas no se pueden traer por no tener nada que mostrar.
  final int unusable;

  int get cardCount => items.fold(0, (sum, item) => sum + item.cards.length);
}

/// Lo que pasó al traer un paquete.
@immutable
class AnkiImportReport {
  const AnkiImportReport({
    required this.cardsImported,
    required this.itemsCreated,
    required this.alreadyImported,
    required this.unusable,
  });

  final int cardsImported;

  /// Los elementos que se crearon (los que ya existían de una importación
  /// anterior no cuentan).
  final int itemsCreated;
  final int alreadyImported;
  final int unusable;
}

/// Cuántas tarjetas de cada forma trae un paquete.
@immutable
class AnkiKindCounts {
  const AnkiKindCounts({
    this.basic = 0,
    this.reversed = 0,
    this.cloze = 0,
    this.typed = 0,
    this.multipleChoice = 0,
  });

  final int basic;
  final int reversed;
  final int cloze;
  final int typed;
  final int multipleChoice;

  int get total => basic + reversed + cloze + typed + multipleChoice;
}

/// Lo que se muestra antes de traer un paquete: de qué está hecho y qué se
/// va a perder o ya estaba.
@immutable
class AnkiImportPreview {
  const AnkiImportPreview({
    required this.deckCount,
    required this.cardCount,
    required this.kinds,
    required this.newCards,
    required this.learningCards,
    required this.reviewCards,
    required this.suspendedCards,
    required this.postponedCards,
    required this.filteredDeckCards,
    required this.imageCount,
    required this.audioCount,
    required this.videoCount,
    required this.alreadyImported,
    required this.skippedCards,
    required this.warnings,
    required this.deckPaths,
  });

  factory AnkiImportPreview.of(
    AnkiImportedPackage package, {
    required int alreadyImported,
  }) {
    var basic = 0;
    var reversed = 0;
    var cloze = 0;
    var typed = 0;
    var choice = 0;
    var fresh = 0;
    var learning = 0;
    var review = 0;
    var suspended = 0;
    var postponed = 0;
    var filtered = 0;
    for (final card in package.cards) {
      switch (card.kind) {
        case AnkiCardKind.basic:
          basic++;
        case AnkiCardKind.reversed:
          reversed++;
        case AnkiCardKind.cloze:
          cloze++;
        case AnkiCardKind.typed:
          typed++;
        case AnkiCardKind.multipleChoice:
          choice++;
      }
      switch (card.schedule.state) {
        case AnkiCardState.newCard:
          fresh++;
        case AnkiCardState.learning:
        case AnkiCardState.relearning:
          learning++;
        case AnkiCardState.review:
          review++;
      }
      if (card.schedule.suspended) suspended++;
      if (card.schedule.postponed) postponed++;
      if (card.schedule.inFilteredDeck) filtered++;
    }
    return AnkiImportPreview(
      deckCount: package.decks.length,
      cardCount: package.cardCount,
      kinds: AnkiKindCounts(
        basic: basic,
        reversed: reversed,
        cloze: cloze,
        typed: typed,
        multipleChoice: choice,
      ),
      newCards: fresh,
      learningCards: learning,
      reviewCards: review,
      suspendedCards: suspended,
      postponedCards: postponed,
      filteredDeckCards: filtered,
      imageCount: package.imageCount,
      audioCount: package.audioCount,
      videoCount: package.videoCount,
      alreadyImported: alreadyImported,
      skippedCards: package.skippedCards,
      warnings: package.warnings,
      deckPaths: [for (final deck in package.decks) deck.path],
    );
  }

  final int deckCount;
  final int cardCount;
  final AnkiKindCounts kinds;
  final int newCards;

  /// Las que se están aprendiendo o reaprendiendo.
  final int learningCards;
  final int reviewCards;
  final int suspendedCards;
  final int postponedCards;

  /// Las que estaban en un mazo filtrado (entran con su calendario original).
  final int filteredDeckCards;
  final int imageCount;
  final int audioCount;
  final int videoCount;

  /// Cuántas ya están en la bóveda de una importación anterior: no se
  /// vuelven a traer.
  final int alreadyImported;

  /// Cuántas el lector dejó afuera por no tener nada que mostrar.
  final int skippedCards;
  final List<String> warnings;
  final List<String> deckPaths;

  /// Las que se traerían ahora.
  int get toImport => cardCount - alreadyImported;

  bool get hasUnimportedMedia => imageCount + audioCount + videoCount > 0;
  bool get hasFilteredDeck => filteredDeckCards > 0;
}
