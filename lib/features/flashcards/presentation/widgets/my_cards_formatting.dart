import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los textos de «Mis tarjetas» (F31, ola 2, decisión 72): cómo se dice la
/// etapa, la forma y el vencimiento de una tarjeta. Funciones sueltas y puras,
/// para probarlas sin una pantalla.

/// El texto con el que se reconoce la tarjeta en la lista: su frente. Una de
/// huecos muestra su hueco tapado (`El [...] cayó en 476`), no las marcas.
String cardListTitle(Flashcard card) {
  final number = card.clozeIndex;
  if (card.kind == FlashcardKind.cloze && number != null) {
    final text = parseCloze(card.front);
    if (text.numbers.contains(number)) return text.questionFor(number);
  }
  return card.front;
}

/// La etapa, en una palabra: una pausada es «Pausada» sea cual sea su etapa.
String cardStageLabel(AppLocalizations l10n, Flashcard card) {
  if (card.suspended) return l10n.myCardsStageSuspended;
  return switch (card.phase) {
    CardPhase.newCard => l10n.myCardsStageNew,
    CardPhase.learning => l10n.myCardsStageLearning,
    CardPhase.relearning => l10n.myCardsStageRelearning,
    CardPhase.review =>
      card.intervalDays >= kMatureIntervalDays
          ? l10n.myCardsStageMature
          : l10n.myCardsStageYoung,
  };
}

/// La forma de la tarjeta, o `null` si es la común (pregunta y respuesta sin
/// hermanas): no se rotula lo que es lo de siempre.
String? cardShapeLabel(AppLocalizations l10n, Flashcard card) {
  final kind = switch (card.kind) {
    FlashcardKind.freeRecall => null,
    FlashcardKind.cloze => l10n.myCardsKindCloze,
    FlashcardKind.typedAnswer => l10n.myCardsKindTyped,
    FlashcardKind.multipleChoice => l10n.myCardsKindMultipleChoice,
    FlashcardKind.trueFalse => l10n.myCardsKindTrueFalse,
  };
  if (card.groupId == null) return kind;
  return kind == null
      ? l10n.myCardsSiblings
      : l10n.myCardsKindWithSiblings(kind);
}

/// Cuándo vence, contado en días de estudio (4:00 a 4:00), no en días de
/// calendario: a las 2:00 de la madrugada, lo que vence «a las 3:00» es de hoy.
String cardDueLabel(
  AppLocalizations l10n,
  Flashcard card,
  DateTime now, {
  StudyDay day = const StudyDay(),
}) {
  if (card.phase == CardPhase.newCard) return l10n.myCardsDueNone;
  final today = day.startOf(now);
  final due = day.startOf(card.dueAt);
  // En UTC para que el cambio de horario no mida un día de 23 o 25 horas.
  final days = DateTime.utc(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (days < 0) return l10n.myCardsDueAgo(-days);
  if (days == 0) return l10n.myCardsDueToday;
  if (days == 1) return l10n.myCardsDueTomorrow;
  return l10n.myCardsDueIn(days);
}

/// Un ícono para la forma de la tarjeta.
IconData cardKindIcon(FlashcardKind kind) => switch (kind) {
  FlashcardKind.freeRecall => Icons.style_outlined,
  FlashcardKind.cloze => Icons.format_underlined,
  FlashcardKind.typedAnswer => Icons.keyboard_outlined,
  FlashcardKind.multipleChoice => Icons.checklist,
  FlashcardKind.trueFalse => Icons.rule,
};

/// El rótulo de un estado de filtro.
String statusFilterLabel(AppLocalizations l10n, CardBrowserStatus status) =>
    switch (status) {
      CardBrowserStatus.newCards => l10n.myCardsStatusNew,
      CardBrowserStatus.learning => l10n.myCardsStatusLearning,
      CardBrowserStatus.due => l10n.myCardsStatusDue,
      CardBrowserStatus.suspended => l10n.myCardsStatusSuspended,
      CardBrowserStatus.buried => l10n.myCardsStatusBuried,
      CardBrowserStatus.young => l10n.myCardsStatusYoung,
      CardBrowserStatus.mature => l10n.myCardsStatusMature,
    };

/// El rótulo de un criterio de orden.
String sortLabel(AppLocalizations l10n, CardBrowserSort sort) => switch (sort) {
  CardBrowserSort.due => l10n.myCardsSortDue,
  CardBrowserSort.created => l10n.myCardsSortCreated,
  CardBrowserSort.ease => l10n.myCardsSortEase,
  CardBrowserSort.interval => l10n.myCardsSortInterval,
  CardBrowserSort.lapses => l10n.myCardsSortLapses,
};
