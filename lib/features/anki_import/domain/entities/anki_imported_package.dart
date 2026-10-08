import 'package:meta/meta.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';

/// La forma de una tarjeta de Anki, tal como Sinapsis la entiende (F31).
enum AnkiCardKind {
  /// Frente y dorso.
  basic,

  /// Una de las dos tarjetas hermanas de una nota «y tarjeta invertida»: la
  /// de ida (`ord` 0) y la de vuelta (`ord` 1) llegan como dos
  /// [AnkiImportedCard] con el mismo [AnkiImportedCard.noteId].
  reversed,

  /// Huecos para completar (`{{c1::...}}`): una tarjeta por número.
  cloze,

  /// «Escribí la respuesta» (`{{type:Campo}}`): [AnkiImportedCard.back] es la
  /// respuesta que hay que escribir.
  typed,

  /// Opción múltiple del modelo propio de Sinapsis (`Question`, `Answer`,
  /// `Distractor1..3`): es lo que exporta Sinapsis, así que ida y vuelta no
  /// la degrada a una tarjeta básica.
  multipleChoice,
}

/// En qué punto del ciclo de repaso de Anki está una tarjeta.
enum AnkiCardState {
  /// Nunca se estudió.
  newCard,

  /// Se está aprendiendo (pasos de minutos o de un día, todavía no pasó a
  /// repasarse en días).
  learning,

  /// Ya se repasa a intervalos de días.
  review,

  /// Se olvidó y se está volviendo a aprender.
  relearning,
}

/// El calendario de una tarjeta de Anki, traducido a SM-2.
///
/// Los campos de SM-2 son los que Sinapsis ya guarda por tarjeta
/// (`easeFactor`, `intervalDays`, `repetitions`, `dueAt`); el resto es lo
/// que Anki sabe de más y que se puede usar o ignorar.
@immutable
class AnkiCardSchedule {
  const AnkiCardSchedule({
    required this.state,
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    this.dueAt,
    this.newPosition,
    this.lastReviewedAt,
    this.suspended = false,
    this.postponed = false,
    this.inFilteredDeck = false,
  });

  final AnkiCardState state;

  /// `factor / 1000` de Anki (2500 → 2.5). Una tarjeta nueva, que en Anki
  /// tiene 0, queda en 2.5, el valor inicial de SM-2.
  final double easeFactor;

  /// `ivl` de Anki, en días. 0 en una tarjeta nueva o que recién se aprende.
  final int intervalDays;

  /// `reps` de Anki: cuántas veces se repasó. Una tarjeta nueva tiene 0;
  /// cualquier otra, al menos 1.
  final int repetitions;

  /// Cuántas veces se olvidó.
  final int lapses;

  /// Cuándo toca. Para una tarjeta de repaso es el día (a la hora local en
  /// que empezó la colección); para una que se está aprendiendo, el instante
  /// exacto. `null` para una nueva: Anki solo guarda su orden en la cola.
  final DateTime? dueAt;

  /// El lugar en la cola de las nuevas (`due` de Anki). Solo en las nuevas.
  final int? newPosition;

  /// El último repaso, si el paquete trae el historial (`revlog`).
  final DateTime? lastReviewedAt;

  /// Pausada (suspendida) en Anki: no se muestra hasta que se reactive.
  final bool suspended;

  /// Pospuesta hasta mañana (`buried`, a mano o por una hermana).
  final bool postponed;

  /// Estaba en un mazo filtrado: el calendario es el original, y el mazo,
  /// al que pertenecía.
  final bool inFilteredDeck;

  bool get isNew => state == AnkiCardState.newCard;
}

/// Una tarjeta traída de Anki.
@immutable
class AnkiImportedCard {
  const AnkiImportedCard({
    required this.ankiCardId,
    required this.noteId,
    required this.guid,
    required this.ord,
    required this.kind,
    required this.front,
    required this.back,
    required this.schedule,
    this.tags = const [],
    this.media = const [],
    this.clozeSource,
    this.clozeNumber,
    this.distractors = const [],
    this.noteTypeName = '',
  });

  /// El `id` de la tarjeta en Anki.
  final int ankiCardId;

  /// El `id` de la nota. Las tarjetas hermanas (las dos direcciones, los
  /// distintos números de hueco de un mismo texto) lo comparten.
  final int noteId;

  /// El `guid` de la nota: lo que Anki usa para reconocer la misma nota en
  /// otra colección. Sinapsis, al exportar, escribe ahí el id de su tarjeta.
  final String guid;

  /// Cuál de las plantillas de la nota es (0 para la primera).
  final int ord;

  final AnkiCardKind kind;

  /// El frente, sin HTML. Para [AnkiCardKind.cloze] es la pregunta ya armada
  /// (el hueco como `[...]`); la fuente completa está en [clozeSource].
  final String front;

  /// El dorso, sin HTML. Para [AnkiCardKind.cloze], el texto completo con el
  /// hueco revelado en negrita, y debajo el «extra» de la nota si lo hay.
  final String back;

  final AnkiCardSchedule schedule;

  /// Las etiquetas de la nota (`a::b` conserva su jerarquía).
  final List<String> tags;

  /// Los medios que la tarjeta referencia, sin importar.
  final List<AnkiMediaRef> media;

  /// Solo en [AnkiCardKind.cloze]: el texto con sus `{{c1::...}}`, sin HTML,
  /// y qué número de hueco pregunta esta tarjeta.
  final String? clozeSource;
  final int? clozeNumber;

  /// Solo en [AnkiCardKind.multipleChoice]: las opciones incorrectas, en
  /// orden y sin las vacías.
  final List<String> distractors;

  /// El nombre del tipo de nota en Anki («Básico», «Cloze»…).
  final String noteTypeName;

  /// Si no tiene nada que mostrar con las palabras solas (una tarjeta cuyo
  /// frente es una imagen).
  bool get isMediaOnly => front.isEmpty && media.isNotEmpty;
}

/// Un mazo de Anki con sus tarjetas.
class AnkiImportedDeck {
  const AnkiImportedDeck({
    required this.id,
    required this.path,
    required this.cards,
  });

  /// El `id` del mazo en Anki.
  final int id;

  /// El nombre completo, con `::` entre los niveles: `Historia::Roma`.
  final String path;

  /// El último nivel de [path].
  String get name {
    final cut = path.lastIndexOf('::');
    return cut < 0 ? path : path.substring(cut + 2);
  }

  /// Los niveles de [path], de la raíz a la hoja.
  List<String> get levels => path.split('::');

  final List<AnkiImportedCard> cards;
}

/// Una respuesta del historial de Anki (`revlog`).
@immutable
class AnkiImportedReview {
  const AnkiImportedReview({
    required this.ankiCardId,
    required this.reviewedAt,
    required this.ease,
    required this.intervalDays,
    required this.previousIntervalDays,
    required this.durationMs,
  });

  final int ankiCardId;
  final DateTime reviewedAt;

  /// El botón: 1 de nuevo, 2 difícil, 3 bien, 4 fácil.
  final int ease;

  /// El intervalo que quedó y el que había, en días (0 si era de minutos).
  final int intervalDays;
  final int previousIntervalDays;

  /// Cuánto tardó en contestar, en milisegundos.
  final int durationMs;
}

/// Lo que se leyó de un `.apkg`.
class AnkiImportedPackage {
  const AnkiImportedPackage({
    required this.decks,
    required this.reviews,
    required this.packageMediaFiles,
    required this.collectionCreatedAt,
    required this.sourceFile,
    this.warnings = const [],
    this.skippedCards = 0,
  });

  /// Los mazos que tienen al menos una tarjeta, en el orden en que aparece
  /// su primera tarjeta.
  final List<AnkiImportedDeck> decks;

  /// El historial de repasos, si el paquete lo trae (vacío si no).
  final List<AnkiImportedReview> reviews;

  /// Cuántos archivos de medios trae el paquete (la tabla `media`).
  final int packageMediaFiles;

  /// Cuándo se creó la colección: el día 0 de los vencimientos de Anki.
  final DateTime collectionCreatedAt;

  /// Qué archivo del `.apkg` se leyó (`collection.anki21`, `collection.anki2`).
  final String sourceFile;

  /// Avisos en español para mostrar (algo que no se pudo leer, un mazo
  /// filtrado, un historial incompleto…).
  final List<String> warnings;

  /// Cuántas tarjetas se dejaron afuera por no tener nada que mostrar o por
  /// apuntar a una nota que no está.
  final int skippedCards;

  /// Todas las tarjetas, de todos los mazos.
  Iterable<AnkiImportedCard> get cards => decks.expand((d) => d.cards);

  int get cardCount => decks.fold(0, (sum, d) => sum + d.cards.length);

  /// Los medios distintos que las tarjetas referencian y que no se traen.
  List<AnkiMediaRef> get referencedMedia {
    final seen = <AnkiMediaRef>{};
    for (final card in cards) {
      seen.addAll(card.media);
    }
    return seen.toList();
  }

  int get imageCount =>
      referencedMedia.where((m) => m.kind == AnkiMediaKind.image).length;

  int get audioCount =>
      referencedMedia.where((m) => m.kind == AnkiMediaKind.audio).length;

  int get videoCount =>
      referencedMedia.where((m) => m.kind == AnkiMediaKind.video).length;

  /// Si alguna tarjeta usa medios: la pantalla avisa que entran sin ellos.
  bool get hasUnimportedMedia => referencedMedia.isNotEmpty;
}
