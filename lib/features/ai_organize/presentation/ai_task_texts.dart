import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se dice lo que hace la IA ahora y lo que costó cada pasada (F39,
/// paso 6): un solo lugar para «Ahora», «Cómo lo hace» y la actividad, aparte
/// de los widgets para decirlo igual donde haga falta y probarlo sin dibujar
/// nada.

/// Una duración corta y exacta: «45 s», «2 min 14 s», «1 h 05 min». Los
/// segundos que sobran en una hora no se cuentan: ya no importan.
String aiDurationText(AppLocalizations l10n, Duration duration) {
  final total = duration.isNegative ? 0 : duration.inSeconds;
  if (total < 60) return l10n.aiDurationSeconds(total);
  if (total < 3600) {
    return l10n.aiDurationMinutes(total ~/ 60, total % 60);
  }
  final minutes = (total % 3600) ~/ 60;
  return l10n.aiDurationHours(total ~/ 3600, minutes);
}

/// Una cantidad de tokens con el separador de miles de [locale]: «12.340».
String aiTokenCount(String locale, int tokens) =>
    NumberFormat.decimalPattern(locale).format(tokens);

/// Qué hace la tarea, en una frase con el título del elemento: «Analizando
/// «Historia» para estudiar».
String aiTaskHeadline(AppLocalizations l10n, AiTask task) {
  final title = task.title.trim();
  return switch (task.kind) {
    AiTaskKind.studyAnalysis =>
      title.isEmpty ? l10n.aiNowStudyUntitled : l10n.aiNowStudy(title),
    AiTaskKind.organize => l10n.aiNowOrganize(title),
    AiTaskKind.flashcards => l10n.aiNowFlashcards(title),
    AiTaskKind.dates => l10n.aiNowDates(title),
    AiTaskKind.review => l10n.aiNowReview(title),
  };
}

/// Cuánto va, en lo que se cuenta: «Parte 3 de 12», «Paso 2 de 5»,
/// «Elemento 4 de 9».
String aiProgressText(AppLocalizations l10n, AiTaskProgress progress) =>
    switch (progress.unit) {
      AiTaskUnit.part => l10n.aiNowPart(progress.current, progress.total),
      AiTaskUnit.step => l10n.aiNowStep(progress.current, progress.total),
      AiTaskUnit.item => l10n.aiNowItem(progress.current, progress.total),
    };

/// El nombre de un paso de «Cómo lo hace».
String aiStepLabel(AppLocalizations l10n, AiTaskStepKind step) =>
    switch (step) {
      AiTaskStepKind.studySplit => l10n.aiStepStudySplit,
      AiTaskStepKind.studySend => l10n.aiStepStudySend,
      AiTaskStepKind.studyJoin => l10n.aiStepStudyJoin,
      AiTaskStepKind.organizeReference => l10n.aiStepOrganizeReference,
      AiTaskStepKind.organizeProperties => l10n.aiStepOrganizeProperties,
      AiTaskStepKind.organizeSpace => l10n.aiStepOrganizeSpace,
      AiTaskStepKind.organizeRelations => l10n.aiStepOrganizeRelations,
      AiTaskStepKind.organizeFlashcards => l10n.aiStepOrganizeFlashcards,
      AiTaskStepKind.organizeAtlas => l10n.aiStepOrganizeAtlas,
      AiTaskStepKind.organizeDates => l10n.aiStepOrganizeDates,
      AiTaskStepKind.reviewFlashcards => l10n.aiStepReviewFlashcards,
      AiTaskStepKind.reviewThings => l10n.aiStepReviewThings,
    };

/// Lo que costó una pasada, en una línea: «Gemini 3.1 Flash Lite · 2 min 14 s
/// · 12.340 tokens». Sin nada que contar —las pasadas de antes, que no lo
/// guardaban—, `null`: no se inventa un cero.
String? aiRunCostText(AppLocalizations l10n, String locale, AiRun run) {
  if (!run.hasUsage) return null;
  final model = run.model;
  final prefix = model == null || model.trim().isEmpty
      ? ''
      : '${modelLabel(model)} · ';
  final hasTime = run.workTime > Duration.zero;
  final hasTokens = run.tokens > 0;
  final time = aiDurationText(l10n, run.workTime);
  final tokens = aiTokenCount(locale, run.tokens);
  if (hasTime && hasTokens) {
    return l10n.aiRunCostTimeTokens(prefix, time, tokens);
  }
  if (hasTime) return l10n.aiRunCostTime(prefix, time);
  return l10n.aiRunCostTokens(prefix, tokens);
}
