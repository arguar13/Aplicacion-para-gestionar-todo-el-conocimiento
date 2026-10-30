import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_analysis_start.dart';
import 'package:sinapsis/features/study/presentation/study_progress_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo va el análisis: la parte que va y «Parar»; si se cortó,
/// «Reintentar»; si una parte no se pudo leer, cuántas. Sin nada que
/// contar, no ocupa lugar.
///
/// La misma en los botones de estudio del original de un documento procesado
/// (`OriginalStudyBar`) y en el visor de lo extraído en Repasar
/// (`ExtractViewer`). Nació en la tarjeta «Estudiar el documento» de la
/// Biblioteca (F36), que salió en F45 (paso 3).
class StudyProgressStrip extends ConsumerWidget {
  const StudyProgressStrip({required this.text, super.key});

  final StudyText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(studyAnalysisProvider(text.renditionId));
    final notifier = ref.read(studyAnalysisProvider(text.renditionId).notifier);

    return switch (state) {
      StudyAnalysisIdle() || StudyAnalysisDone(unreadParts: 0) =>
        const SizedBox(width: double.infinity),
      final StudyAnalysisRunning running => _Strip(
        key: const Key('study-progress'),
        message: studyRunningMessage(l10n, running),
        running: true,
        progress: running.progress == null || running.progress!.partsTotal == 0
            ? null
            : running.progress!.partsDone / running.progress!.partsTotal,
        action: l10n.studyStop,
        onAction: notifier.stop,
      ),
      StudyAnalysisDone(:final unreadParts) => _Strip(
        key: const Key('study-unread'),
        message: l10n.studyUnreadParts(unreadParts),
        action: l10n.studyUnreadAcknowledge,
        onAction: notifier.acknowledge,
      ),
      final StudyAnalysisFailed failed => _Strip(
        key: const Key('study-failed'),
        message: studyFailedMessage(l10n, failed),
        action: l10n.studyRetry,
        onAction: () {
          notifier.acknowledge();
          unawaited(analyzeForStudyIfNeeded(ref, context, text));
        },
      ),
    };
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.message,
    required this.action,
    required this.onAction,
    this.running = false,
    this.progress,
    super.key,
  });

  final String message;

  /// Si está analizando: lleva la barra. Un aviso va sin ella.
  final bool running;

  /// Cuánto va, de 0 a 1; `null`, sin saber todavía.
  final double? progress;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: onAction, child: Text(action)),
            ],
          ),
          if (running)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
        ],
      ),
    );
  }
}
