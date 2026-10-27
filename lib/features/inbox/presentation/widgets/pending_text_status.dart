import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/reextract_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se dice lo que le falta al texto de lo que espera en la Bandeja (F41),
/// en un solo lugar: la tarjeta, la lista de la cola y la ayuda de cada acción
/// apagada lo dicen igual.
extension PendingTextPresentation on PendingText {
  /// Por qué una acción que necesita el texto está apagada, o `null` si ya
  /// lo tiene.
  String? neededReason(AppLocalizations l10n) => switch (this) {
    PendingText.ready => null,
    PendingText.arriving => l10n.inboxTextNeededArriving,
    PendingText.failed => l10n.inboxTextNeededFailed,
    PendingText.missing => l10n.inboxTextNeededMissing,
  };

  /// Lo que dice la lista de «N pendientes» junto al tipo, o `null` si ya
  /// tiene su texto. Ahí solo se sabe el tipo: una publicación con video se
  /// lee «Extrayendo el texto…», que también es cierto.
  String? queueLabel(AppLocalizations l10n, SourceKind kind) => switch (this) {
    PendingText.ready => null,
    PendingText.arriving => _arrivingLabel(
      l10n,
      kind: kind,
      transcript: switch (kind) {
        SourceKind.youtube || SourceKind.audio || SourceKind.video => true,
        _ => false,
      },
    ),
    PendingText.failed => l10n.inboxQueueTextFailed,
    PendingText.missing => l10n.inboxQueueTextMissing,
  };
}

/// Qué se está haciendo para que llegue el texto, dicho con lo que es:
/// transcribir un audio o un video, leer una foto, extraer el de lo demás.
String _arrivingLabel(
  AppLocalizations l10n, {
  required SourceKind kind,
  required bool transcript,
}) {
  if (transcript) return l10n.inboxTextTranscribing;
  if (kind == SourceKind.image) return l10n.inboxTextReadingPhoto;
  return l10n.inboxTextExtracting;
}

/// Lo que la tarjeta de la Bandeja muestra en lugar del texto mientras no lo
/// tiene (F41): todo lo nuevo entra apenas se guarda, y esto dice qué le
/// falta y qué se puede hacer.
///
/// - **Llegando** —«Transcribiendo…», «Leyendo la foto…», «Extrayendo el
///   texto…»—, con la barra si se sabe cuánto va, y que ya se puede descartar.
///   Cuando el texto llega, la tarjeta lo muestra sola: esto se va y las
///   acciones se prenden, sin tocar nada.
/// - **Falló**: el motivo real si se sabe (el mismo del detalle, F21) y el
///   único botón que lo resuelve —«Reintentar», o «Descargar el modelo» si lo
///   que falta es el modelo de transcripción—, el mismo camino que el panel
///   de la fuente.
/// - **Sin texto**: se procesó y no había —una foto sin letras—, o se dejó
///   «solo el libro» (F30). Si el original se puede volver a leer, lo ofrece.
///
/// Dice siempre que lo guardado sigue en la Biblioteca: una tarjeta sin texto
/// se lee, si no, como «no se guardó nada».
class PendingTextStatus extends ConsumerWidget {
  const PendingTextStatus({required this.item, required this.text, super.key});

  final KnowledgeItem item;

  /// Nunca [PendingText.ready]: con texto, la tarjeta muestra el texto.
  final PendingText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return switch (text) {
      PendingText.ready => const SizedBox.shrink(),
      PendingText.arriving => _Status(
        statusKey: const Key('pending-text-arriving'),
        icon: Icons.hourglass_top,
        title: _arrivingLabel(
          l10n,
          kind: item.source.kind,
          transcript: isTranscriptSource(item.source),
        ),
        hint: l10n.inboxTextArrivingHint,
        progress: switch (ref.watch(processingProgressProvider(item.id))) {
          final progress? => ProcessingProgressBar(
            progress: progress,
            kind: item.source.kind,
          ),
          null => null,
        },
      ),
      PendingText.failed => _failed(context, ref, l10n),
      PendingText.missing => _missing(context, ref, l10n),
    };
  }

  Widget _failed(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final failure = ref.watch(processingFailureProvider(item.id)).valueOrNull;
    return _Status(
      statusKey: const Key('pending-text-failed'),
      icon: Icons.error_outline,
      tone: SourcePanelTone.error,
      title: failureMessage(l10n, failure) ?? l10n.inboxTextFailed,
      action: failure == ProcessingFailureReason.transcriptionModelMissing
          // Reintentar sin el modelo volvería a fallar igual: lo que lo
          // resuelve es bajarlo, y al terminar se retoma solo.
          ? SourcePanelStatusButton(
              icon: Icons.download,
              label: l10n.failureTranscriptionModelAction,
              onPressed: () => context.push(RoutePaths.transcriptionModel),
            )
          : SourcePanelStatusButton(
              key: const Key('pending-text-retry'),
              icon: Icons.refresh,
              label: l10n.detailRetry,
              onPressed: () => unawaited(
                ref.read(processingQueueProvider.notifier).retry(item.id),
              ),
            ),
    );
  }

  Widget _missing(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    return _Status(
      statusKey: const Key('pending-text-missing'),
      icon: item.source.onlyFile ? Icons.menu_book_outlined : Icons.notes,
      title: item.source.onlyFile
          ? l10n.sourcePanelOnlyFile
          : l10n.inboxTextMissing,
      action: canReextractText(item)
          ? SourcePanelStatusButton(
              key: const Key('pending-text-reextract'),
              icon: Icons.refresh,
              label: l10n.detailReextract,
              onPressed: () => unawaited(reextractText(context, ref, item)),
            )
          : null,
    );
  }
}

/// La franja de estado de la tarjeta: el mismo lenguaje que la del panel de
/// la fuente (F26) —un ícono en un círculo suave, lo que pasa, la barra y un
/// solo botón—, con una línea de ayuda debajo y sobre una superficie propia,
/// para que se lea como lo que ocupa el lugar del texto.
class _Status extends StatelessWidget {
  const _Status({
    required this.statusKey,
    required this.icon,
    required this.title,
    this.tone = SourcePanelTone.neutral,
    this.hint,
    this.progress,
    this.action,
  });

  final Key statusKey;
  final IconData icon;
  final String title;
  final SourcePanelTone tone;
  final String? hint;
  final Widget? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: statusKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SourcePanelIconCircle(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Centrado con el círculo cuando entra en un renglón.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ),
                if (hint case final hint?)
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (progress case final progress?) ...[
                  const SizedBox(height: 10),
                  progress,
                ],
                if (action case final action?) ...[
                  const SizedBox(height: 10),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
