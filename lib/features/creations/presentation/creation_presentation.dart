/// Cómo se dice cada cosa de «Lo creado» (F43): un solo lugar para el nombre y
/// el ícono de cada tipo, el título de una creación sin título y por qué falló
/// una. Lo usan la papelera, «Lo creado», las hojas y los visores.
library;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El nombre de [kind], como en su tarjeta de crear.
String studyCreationKindLabel(AppLocalizations l10n, StudyCreationKind kind) =>
    switch (kind) {
      StudyCreationKind.fullText => l10n.f43DataKindFullText,
      StudyCreationKind.summary => l10n.f43DataKindSummary,
      StudyCreationKind.synthesis => l10n.f43DataKindSynthesis,
      StudyCreationKind.presentation => l10n.f43DataKindPresentation,
      StudyCreationKind.mindMap => l10n.f43DataKindMindMap,
      StudyCreationKind.report => l10n.f43DataKindReport,
      StudyCreationKind.flashcards => l10n.f43DataKindFlashcards,
      StudyCreationKind.quiz => l10n.f43DataKindQuiz,
      StudyCreationKind.infographic => l10n.f43DataKindInfographic,
      StudyCreationKind.dataTable => l10n.f43DataKindDataTable,
    };

/// El ícono de [kind], el de las capturas del plan: ¶, ≡, ◆, ▭, ⊶, ✦, ⧉, ?,
/// ▥ y ☰. El color de cada uno lo pone la grilla.
IconData studyCreationKindIcon(StudyCreationKind kind) => switch (kind) {
  StudyCreationKind.fullText => Icons.notes_outlined,
  StudyCreationKind.summary => Icons.short_text,
  StudyCreationKind.synthesis => Icons.diamond_outlined,
  StudyCreationKind.presentation => Icons.slideshow_outlined,
  StudyCreationKind.mindMap => Icons.account_tree_outlined,
  StudyCreationKind.report => Icons.auto_awesome_outlined,
  StudyCreationKind.flashcards => Icons.style_outlined,
  StudyCreationKind.quiz => Icons.quiz_outlined,
  StudyCreationKind.infographic => Icons.insert_chart_outlined,
  StudyCreationKind.dataTable => Icons.table_chart_outlined,
};

/// El título de [creation]: el suyo, o el nombre de su tipo mientras no tiene.
String studyCreationTitle(AppLocalizations l10n, StudyCreation creation) {
  final title = creation.title?.trim();
  return title == null || title.isEmpty
      ? studyCreationKindLabel(l10n, creation.kind)
      : title;
}

/// Por qué falló, en una línea, para la fila de «Lo creado».
String creationFailureMessage(AppLocalizations l10n, CreationFailure failure) =>
    switch (failure) {
      CreationFailure.cancelled => l10n.f43DataFailureCancelled,
      CreationFailure.noSources => l10n.f43DataFailureNoSources,
      CreationFailure.modelUnavailable => l10n.f43DataFailureModelUnavailable,
      CreationFailure.unreadableReply => l10n.f43DataFailureUnreadableReply,
      CreationFailure.interrupted => l10n.f43DataFailureInterrupted,
      CreationFailure.unsupported => l10n.f43DataFailureUnsupported,
      CreationFailure.error => l10n.f43DataFailureError,
    };

/// En qué paso va, para la línea de «Generando…».
String creationStepLabel(AppLocalizations l10n, CreationStep step) =>
    switch (step) {
      CreationStep.preparing => l10n.f43DataStepPreparing,
      CreationStep.writing => l10n.f43DataStepWriting,
      CreationStep.readingParts => l10n.f43DataStepReadingParts,
      CreationStep.joining => l10n.f43DataStepJoining,
      CreationStep.finishing => l10n.f43DataStepFinishing,
      CreationStep.illustrating => l10n.f43IgStepIllustrating,
    };
