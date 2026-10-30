import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Empezar a estudiar un texto con la IA (F36): lo que comparten las fichas
// del original (`OriginalStudyBar`), la franja de avance y lo extraído en
// Repasar. Los botones de estudiar de la Biblioteca —`StudyToggles`, en una
// fila que se deslizaba— salieron en F45 (paso 7b): la fuente se marca en su
// original, con las mismas fichas que la copia de Procesado.

/// Analiza lo que falta de [text], si falta algo y no se está analizando ya
/// (F36). Una sola pasada da el resumen, la síntesis y las palabras: lo ya
/// analizado no se pide de nuevo, y un análisis cortado sigue desde ahí.
///
/// Usa el modelo elegido en Ajustes; si no está listo, lo avisa con el botón
/// que lo resuelve y no baja nada solo.
Future<void> analyzeForStudyIfNeeded(
  WidgetRef ref,
  BuildContext context,
  StudyText text,
) async {
  final notifier = ref.read(studyAnalysisProvider(text.renditionId).notifier);
  if (notifier.isRunning) return;
  final study = await ref
      .read(studyRepositoryProvider)
      .watch(text.renditionId)
      .first;
  if (study.complete || !context.mounted) return;
  final ready = await ensureStudyModelReady(context, ref);
  if (!ready || !context.mounted) return;
  unawaited(
    notifier.start(
      content: text.content,
      markdown: text.markdown,
      itemId: text.itemId,
    ),
  );
}

/// Si el modelo elegido está listo para estudiar; si no, lo avisa con el
/// botón que lo resuelve.
Future<bool> ensureStudyModelReady(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  return ensureLanguageModelReady(
    context,
    ref,
    downloadMessage: l10n.studyModelRequired,
    downloadLabel: l10n.summarizeDownloadAction,
  );
}
