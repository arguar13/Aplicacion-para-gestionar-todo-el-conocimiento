import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto corto de una insignia para lo que está en curso, según su
/// avance: "Esperando turno" detrás de otro trabajo largo, "Procesando…
/// 40 %" si ya se sabe cuánto va, o `null` para seguir con la insignia de
/// siempre.
String? progressBadgeLabel(
  AppLocalizations l10n,
  ProcessingProgress? progress,
) {
  if (progress == null) return null;
  if (progress.lane == ProcessingLane.waitingForLong) {
    return l10n.processingWaitingForLong;
  }
  final fraction = progress.fraction;
  if (fraction == null) return null;
  return l10n.processingProgressLabel((fraction * 100).floor());
}

/// Por qué falló, dicho para quien usa la app: la causa real, sin jerga, y
/// siempre aclarando que lo guardado sigue ahí. `null` para un motivo
/// desconocido: se muestra el mensaje genérico de siempre.
String? failureMessage(
  AppLocalizations l10n,
  ProcessingFailureReason? reason,
) => switch (reason) {
  ProcessingFailureReason.transcriptionModelMissing =>
    l10n.failureTranscriptionModelMissing,
  ProcessingFailureReason.timedOut => l10n.failureTimedOut,
  ProcessingFailureReason.network => l10n.failureNetwork,
  ProcessingFailureReason.unavailable => l10n.failureUnavailable,
  ProcessingFailureReason.noArticle => l10n.failureNoArticle,
  ProcessingFailureReason.unreadableDocument => l10n.failureUnreadableDocument,
  ProcessingFailureReason.missingOriginalFile =>
    l10n.failureMissingOriginalFile,
  ProcessingFailureReason.interrupted => l10n.failureInterrupted,
  ProcessingFailureReason.unknown || null => null,
};

/// La barra de avance de un elemento en curso, con su leyenda. Indeterminada
/// mientras el trabajo todavía no dijo cuánto hay.
class ProcessingProgressBar extends StatelessWidget {
  const ProcessingProgressBar({required this.progress, this.kind, super.key});

  final ProcessingProgress progress;

  /// Qué se está procesando, para decir qué es el trabajo largo: en un
  /// documento, reconocer sus páginas escaneadas —"12 de 400"—; en un audio
  /// o un video, transcribirlo.
  final SourceKind? kind;

  /// Qué es el trabajo largo en curso, dicho con lo que es: páginas en un
  /// documento, transcripción en un audio o un video. `null` si no se sabe.
  String? _longWorkLabel(AppLocalizations l10n) {
    final fraction = progress.fraction;
    if (progress.lane != ProcessingLane.long || fraction == null) return null;
    return switch (kind) {
      SourceKind.document => l10n.processingRecognizingPages(
        progress.done,
        progress.total,
      ),
      SourceKind.audio ||
      SourceKind.video => l10n.processingTranscribing((fraction * 100).floor()),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final waiting = progress.lane == ProcessingLane.waitingForLong;
    final fraction = progress.fraction;

    final label = waiting
        ? l10n.processingWaitingForLongDetail
        : _longWorkLabel(l10n) ??
              l10n.processingProgressLabel(((fraction ?? 0) * 100).floor());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            // Esperando turno no avanza: la barra queda vacía, no animada,
            // para no sugerir un trabajo que todavía no empezó.
            value: waiting ? 0 : fraction,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
