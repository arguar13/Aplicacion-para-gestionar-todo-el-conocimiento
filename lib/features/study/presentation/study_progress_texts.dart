import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dice la franja de la tarjeta de estudiar mientras analiza (F39),
/// aparte del widget para decirlo igual donde haga falta y probarlo sin
/// dibujar nada.
///
/// - Si la IA en la nube falló por algo pasajero y se repite sola:
///   «Reintentando (2 de 4): la respuesta se cortó a mitad…».
/// - Si no, la parte que va, el porcentaje y —desde la primera parte hecha—
///   cuánto falta, aproximado.
String studyRunningMessage(AppLocalizations l10n, StudyAnalysisRunning run) {
  final retry = run.retry;
  if (retry != null) {
    return aiRetryingText(
      l10n,
      attempt: retry.attempt,
      maxAttempts: retry.maxAttempts,
      failure: retry.failure,
    );
  }
  final progress = run.progress;
  if (progress == null || progress.partsTotal <= 0) {
    return l10n.studyPreparing;
  }
  final part = (progress.partsDone + 1).clamp(1, progress.partsTotal);
  final remaining = run.remaining;
  if (remaining == null) {
    return l10n.studyAnalyzingPercent(
      part,
      progress.partsTotal,
      progress.percent,
    );
  }
  return l10n.studyAnalyzingEta(
    part,
    progress.partsTotal,
    progress.percent,
    studyEtaText(l10n, remaining),
  );
}

/// «menos de 1 min», «unos 3 min», «unas 1 h 20 min»: lo que falta, grueso a
/// propósito —es una estimación—.
String studyEtaText(AppLocalizations l10n, Duration remaining) {
  if (remaining < const Duration(minutes: 1)) {
    return l10n.studyEtaLessThanMinute;
  }
  // Para arriba: decir «2 min» cuando faltan 1:20 es más honesto que «1».
  final minutes = (remaining.inSeconds / 60).ceil();
  if (minutes < 60) return l10n.studyEtaMinutes(minutes);
  return l10n.studyEtaHours(minutes ~/ 60, minutes % 60);
}

/// Por qué se cortó el análisis, y qué hacer (F39): para una falla de la IA
/// en la nube, qué pasó de verdad —sin conexión, la espera que venció, la
/// cuota, el servicio caído— y qué hacer; si fue otra cosa, el aviso de
/// siempre.
String studyFailedMessage(AppLocalizations l10n, StudyAnalysisFailed failed) {
  final failure = failed.failure;
  if (failure == null) return l10n.studyFailed;
  return l10n.studyFailedWhy(aiFailureHelp(l10n, failure));
}
