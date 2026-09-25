import 'package:flutter/material.dart';
import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ícono, nombre y descripción de cada insignia (F17, D7), mismo criterio
/// que `entity_presentation.dart` para `NoteKind`/`RelationKind`: un ícono
/// ya usado en otro lado de la app para el mismo concepto, no uno nuevo por
/// insignia —`tenLivingNotes` reusa el de `NoteKind.living`, `hundredReviews`
/// el del destino de navegación de Repaso, `contradictionResolved` el de
/// `RelationKind.contradicts`, `completeTopicBranch` el del Atlas—.
extension BadgeKindPresentation on BadgeKind {
  IconData get icon => switch (this) {
    BadgeKind.firstMatureNote => Icons.eco,
    BadgeKind.tenLivingNotes => Icons.spa_outlined,
    BadgeKind.hundredReviews => Icons.style,
    BadgeKind.contradictionResolved => Icons.compare_arrows,
    BadgeKind.completeTopicBranch => Icons.account_tree,
    BadgeKind.monthOfWeeklyConsolidation => Icons.calendar_month,
  };

  String label(AppLocalizations l10n) => switch (this) {
    BadgeKind.firstMatureNote => l10n.habitBadgeFirstMatureNoteLabel,
    BadgeKind.tenLivingNotes => l10n.habitBadgeTenLivingNotesLabel,
    BadgeKind.hundredReviews => l10n.habitBadgeHundredReviewsLabel,
    BadgeKind.contradictionResolved =>
      l10n.habitBadgeContradictionResolvedLabel,
    BadgeKind.completeTopicBranch => l10n.habitBadgeCompleteTopicBranchLabel,
    BadgeKind.monthOfWeeklyConsolidation =>
      l10n.habitBadgeMonthOfWeeklyConsolidationLabel,
  };

  String description(AppLocalizations l10n) => switch (this) {
    BadgeKind.firstMatureNote => l10n.habitBadgeFirstMatureNoteDescription,
    BadgeKind.tenLivingNotes => l10n.habitBadgeTenLivingNotesDescription,
    BadgeKind.hundredReviews => l10n.habitBadgeHundredReviewsDescription,
    BadgeKind.contradictionResolved =>
      l10n.habitBadgeContradictionResolvedDescription,
    BadgeKind.completeTopicBranch =>
      l10n.habitBadgeCompleteTopicBranchDescription,
    BadgeKind.monthOfWeeklyConsolidation =>
      l10n.habitBadgeMonthOfWeeklyConsolidationDescription,
  };
}
