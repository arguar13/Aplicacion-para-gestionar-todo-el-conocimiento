import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_ids.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_path.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';

/// Una vida útil razonable para el `id` de una tarjeta de Anki como instante de
/// creación: Anki nació en 2006, y lo que dice ser de mañana es un error.
final _ankiBirth = DateTime(2006);

/// Cuántos pasos de aprendizaje tiene Sinapsis (`LearningSteps.standard`).
const _learningStepCount = 2;

/// Arma qué se escribe al traer [package] (F31, decisión 73): a qué elementos
/// caen las tarjetas, y cada tarjeta ya traducida a Sinapsis.
///
/// Pura: no toca la base ni el reloj. [alreadyImported] son los `ankiCardId` de
/// las tarjetas que ya están en la bóveda (el repositorio lo averigua); esas no
/// se vuelven a traer. [now] es el momento de la importación: de ahí salen el
/// «hoy» de las tarjetas nuevas y hasta cuándo dura una pospuesta.
///
/// **El calendario** pasa de Anki a SM-2 sin perder en qué punto estaba cada
/// tarjeta: nueva (sin repasos), aprendiendo (con el paso que le falta, y la
/// hora a la que vuelve), repasando (con su intervalo, su facilidad y la fecha)
/// o reaprendiendo tras olvidarla. Una tarjeta pausada sigue pausada y una
/// pospuesta lo sigue hasta mañana. La fecha de un repaso por días no cae antes
/// de las 4:00 de su día: los repasos de Anki son «de ese día», y para
/// Sinapsis el día de estudio empieza a esa hora.
AnkiImportPlan planAnkiImport(
  AnkiImportedPackage package, {
  required AnkiImportDestination destination,
  required Set<int> alreadyImported,
  required DateTime now,
  StudyDay studyDay = const StudyDay(),
}) {
  // Cuántas tarjetas de cada nota hay en el paquete: las hermanas se enlazan
  // aunque alguna ya esté importada.
  final cardsPerNote = <int, int>{};
  for (final card in package.cards) {
    cardsPerNote.update(card.noteId, (n) => n + 1, ifAbsent: () => 1);
  }

  final itemsById = <String, _ItemBuilder>{};
  final seen = <String>{};
  var duplicates = 0;
  var unusable = 0;

  for (final deck in package.decks) {
    final target = _targetOf(deck.path, destination);
    for (final card in deck.cards) {
      final cardId = ankiImportedCardId(card);
      if (alreadyImported.contains(card.ankiCardId) || !seen.add(cardId)) {
        duplicates++;
        continue;
      }
      final itemId = ankiImportedItemId(target.key);
      final planned = _plannedCard(
        card,
        id: cardId,
        itemId: itemId,
        siblings: (cardsPerNote[card.noteId] ?? 1) > 1,
        now: now,
        studyDay: studyDay,
      );
      if (planned == null) {
        unusable++;
        continue;
      }
      itemsById
          .putIfAbsent(itemId, () => _ItemBuilder(itemId, target))
          .cards
          .add(planned);
    }
  }

  return AnkiImportPlan(
    items: [for (final builder in itemsById.values) builder.build()],
    alreadyImported: duplicates,
    unusable: unusable,
  );
}

/// A dónde cae un mazo: su clave, el título del elemento y sus etiquetas.
class _Target {
  const _Target(this.key, this.title, this.tags, this.description);

  final String key;
  final String title;
  final List<String> tags;
  final String description;
}

_Target _targetOf(String deckPath, AnkiImportDestination destination) {
  if (destination == AnkiImportDestination.singleItem) {
    return const _Target('', kAnkiImportedName, [
      kAnkiImportedName,
    ], 'Tarjetas traídas de Anki.');
  }
  final levels = displayLevelsOf(deckPath);
  final title = levels.isEmpty ? kAnkiImportedName : levels.join(' › ');
  return _Target(deckPath, title, [
    kAnkiImportedName,
    ...levels,
  ], 'Tarjetas traídas del mazo «$deckPath» de Anki.');
}

/// Los niveles de un mazo de Anki sin lo que Sinapsis mismo agrega al exportar:
/// el mazo raíz «Sinapsis» y el «Sin tema». Lo que se exportó y se vuelve a
/// traer no debería quedar con «Sinapsis» de etiqueta.
List<String> displayLevelsOf(String deckPath) {
  final levels = [
    for (final level in deckPath.split('::'))
      if (level.trim().isNotEmpty) level.trim(),
  ];
  if (levels.isNotEmpty && levels.first == kAnkiRootDeckName) {
    levels.removeAt(0);
  }
  if (levels.length == 1 && levels.first == kAnkiNoTopicDeckName) {
    return const [];
  }
  return levels;
}

class _ItemBuilder {
  _ItemBuilder(this.id, this.target);

  final String id;
  final _Target target;
  final cards = <AnkiPlannedCard>[];

  AnkiPlannedItem build() => AnkiPlannedItem(
    id: id,
    title: target.title,
    description: target.description,
    tags: target.tags,
    cards: cards,
  );
}

AnkiPlannedCard? _plannedCard(
  AnkiImportedCard card, {
  required String id,
  required String itemId,
  required bool siblings,
  required DateTime now,
  required StudyDay studyDay,
}) {
  final placeholder = _mediaPlaceholder(card.media);
  var front = card.front.trim();
  var back = card.back.trim();
  var kind = switch (card.kind) {
    AnkiCardKind.basic || AnkiCardKind.reversed => FlashcardKind.freeRecall,
    AnkiCardKind.cloze => FlashcardKind.cloze,
    AnkiCardKind.typed => FlashcardKind.typedAnswer,
    AnkiCardKind.multipleChoice => FlashcardKind.multipleChoice,
  };
  int? clozeIndex;
  var distractors = const <String>[];

  if (kind == FlashcardKind.cloze) {
    final source = (card.clozeSource ?? '').trim();
    final number = card.clozeNumber;
    if (number == null || !parseCloze(source).numbers.contains(number)) {
      return null;
    }
    front = source;
    clozeIndex = number;
    // El dorso de la tarjeta es el texto con el hueco revelado y, debajo, el
    // «extra» de la nota: de ahí sale solo el extra.
    final revealed = parseCloze(source).answerFor(number);
    back = back.startsWith(revealed)
        ? back.substring(revealed.length).trim()
        : '';
  } else if (kind == FlashcardKind.multipleChoice) {
    if (card.distractors.isEmpty || back.isEmpty || front.isEmpty) {
      // Sin con qué armar las opciones, es una pregunta y una respuesta.
      kind = FlashcardKind.freeRecall;
    } else {
      distractors = card.distractors;
    }
  }

  if (front.isEmpty) front = placeholder;
  if (back.isEmpty && kind != FlashcardKind.cloze) {
    if (kind == FlashcardKind.multipleChoice) return null;
    back = placeholder;
  }
  if (front.isEmpty || (back.isEmpty && kind != FlashcardKind.cloze)) {
    return null;
  }

  final schedule = _scheduleOf(card.schedule, now: now, studyDay: studyDay);
  final grouped =
      siblings &&
      (card.kind == AnkiCardKind.reversed || card.kind == AnkiCardKind.cloze);

  return AnkiPlannedCard(
    id: id,
    itemId: itemId,
    kind: kind,
    front: front,
    back: back,
    createdAt: _createdAt(card.ankiCardId, now),
    dueAt: schedule.dueAt,
    easeFactor: schedule.ease,
    intervalDays: schedule.interval,
    repetitions: schedule.repetitions,
    lastReviewedAt: schedule.lastReviewedAt,
    learningStep: schedule.learningStep,
    suspended: card.schedule.suspended,
    buriedUntil: card.schedule.postponed ? studyDay.endOf(now) : null,
    groupId: grouped ? ankiImportedGroupId(card.guid) : null,
    clozeIndex: clozeIndex,
    choiceDistractors: distractors,
  );
}

/// El `id` de una tarjeta de Anki es el instante en que se creó, en
/// milisegundos: sirve de fecha de creación mientras sea una fecha creíble.
DateTime _createdAt(int ankiCardId, DateTime now) {
  final at = DateTime.fromMillisecondsSinceEpoch(ankiCardId);
  final latest = now.add(const Duration(days: 1));
  return at.isBefore(_ankiBirth) || at.isAfter(latest) ? now : at;
}

class _Schedule {
  const _Schedule({
    required this.dueAt,
    required this.ease,
    required this.interval,
    required this.repetitions,
    this.lastReviewedAt,
    this.learningStep,
  });

  final DateTime dueAt;
  final double ease;
  final int interval;
  final int repetitions;
  final DateTime? lastReviewedAt;
  final int? learningStep;
}

_Schedule _scheduleOf(
  AnkiCardSchedule s, {
  required DateTime now,
  required StudyDay studyDay,
}) {
  switch (s.state) {
    case AnkiCardState.newCard:
      return _Schedule(
        dueAt: now,
        ease: s.easeFactor,
        interval: 0,
        repetitions: 0,
      );
    case AnkiCardState.learning:
      // Con dos pasos, «falta 2» es que está en el primero y «falta 1» en el
      // segundo; sin dato, empieza por el primero.
      final step = s.learningStepsLeft <= 0
          ? 0
          : (_learningStepCount - s.learningStepsLeft).clamp(0, 1);
      return _Schedule(
        dueAt: s.dueAt ?? now,
        ease: s.easeFactor,
        interval: 0,
        repetitions: s.repetitions < 1 ? 1 : s.repetitions,
        lastReviewedAt: s.lastReviewedAt,
        learningStep: step,
      );
    case AnkiCardState.relearning:
      return _Schedule(
        dueAt: s.dueAt ?? now,
        ease: s.easeFactor,
        interval: s.intervalDays < 1 ? 1 : s.intervalDays,
        repetitions: s.repetitions < 1 ? 1 : s.repetitions,
        lastReviewedAt: s.lastReviewedAt,
        learningStep: 0,
      );
    case AnkiCardState.review:
      final due = s.dueAt ?? now;
      final dayStart = DateTime(
        due.year,
        due.month,
        due.day,
        studyDay.startHour,
      );
      return _Schedule(
        dueAt: due.isBefore(dayStart) ? dayStart : due,
        ease: s.easeFactor,
        interval: s.intervalDays < 1 ? 1 : s.intervalDays,
        repetitions: s.repetitions < 1 ? 1 : s.repetitions,
        lastReviewedAt: s.lastReviewedAt,
      );
  }
}

/// Lo que se muestra en lugar de un frente o un dorso que era solo un archivo
/// (una imagen, un audio): la tarjeta entra sin él y que se vea qué faltó.
String _mediaPlaceholder(List<AnkiMediaRef> media) {
  final labels = <String>{
    for (final ref in media)
      switch (ref.kind) {
        AnkiMediaKind.image => '[imagen]',
        AnkiMediaKind.audio => '[audio]',
        AnkiMediaKind.video => '[video]',
      },
  };
  return labels.join(' ');
}
