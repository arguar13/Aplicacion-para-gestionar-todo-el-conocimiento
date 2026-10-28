import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_actions.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En el detalle de una fuente, dónde se la estudia (F41, decisión K): la
/// fuente queda de consulta, y su resumen, su síntesis, sus palabras clave, su
/// Mapa y sus tarjetas viven en su documento procesado.
///
/// - **Con documento procesado**: «Estudiarlo en Procesado» lo abre —también
///   si está en la papelera: allá se ve y se restaura—.
/// - **Sin él**: «Para estudiarlo, triálo». El botón abre la hoja «¿Qué va a
///   Procesado?» por el camino de «Volver a triar» (`retriageAction`, paso
///   4), que tría también lo que todavía espera en la Bandeja, con su
///   «Deshacer» que la devuelve adonde estaba. En la Bandeja dice «Triar»; ya
///   triada o descartada, «Volver a triar». Sin texto todavía, espera
///   apagado, con su motivo, y se prende solo cuando el texto llega —ver
///   [InboxActions]—.
///
/// Lo que no tiene nada que estudiar no dibuja nada: una referencia sin texto
/// (decisión E), o lo que no pasa por la Bandeja.
class SourceStudyLine extends ConsumerWidget {
  const SourceStudyLine({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final document = ref.watch(processedDocumentForSourceProvider(item.id));
    final standing = ref.watch(inboxStandingProvider(item.id)).valueOrNull;
    // Mientras se averigua, nada: que no aparezca «Para estudiarlo, triálo»
    // para cambiar enseguida a «Estudiarlo en Procesado».
    if (!document.hasValue) return const SizedBox.shrink();

    if (document.value case final processed?) {
      return _Line(
        key: const Key('source-study-processed'),
        icon: Icons.summarize_outlined,
        message: l10n.sourceStudyInProcessed,
        action: FilledButton.tonalIcon(
          key: const Key('source-study-open'),
          onPressed: () =>
              context.push(RoutePaths.processedDocument(processed.id)),
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.sourceStudyOpen),
        ),
      );
    }

    if (standing == null || !standing.canReturn) {
      return const SizedBox.shrink();
    }
    return _Line(
      key: const Key('source-study-triage'),
      icon: Icons.school_outlined,
      message: l10n.sourceStudyTriage,
      action: _TriageButton(
        item: item,
        pending: standing.status == InboxStatus.pending,
      ),
    );
  }
}

/// «Triar» —o «Volver a triar», si ya se decidió—, con lo que la Bandeja
/// permite según el texto.
class _TriageButton extends ConsumerWidget {
  const _TriageButton({required this.item, required this.pending});

  final KnowledgeItem item;

  /// Si la fuente espera en la Bandeja.
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text =
        ref.watch(inboxPendingTextProvider(item.id)).valueOrNull ??
        PendingText.arriving;
    final ready = InboxActions.of(item, text).triage;
    final button = FilledButton.tonalIcon(
      key: const Key('source-study-triage-button'),
      onPressed: ready
          ? retriageAction(context, ref, sourceItemId: item.id)
          : null,
      icon: Icon(pending ? Icons.inbox_outlined : Icons.replay_outlined),
      label: Text(
        pending ? l10n.sourceStudyTriageAction : l10n.processedRetriage,
      ),
    );
    if (ready) return button;
    // El motivo, también para el lector de pantalla.
    return Tooltip(message: l10n.sourcePanelNeedsText, child: button);
  }
}

/// Una línea tranquila: un ícono, qué pasa y su botón.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.message,
    required this.action,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            action,
          ],
        ),
      ),
    );
  }
}
