import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En el detalle de una fuente, dónde se la estudia (F41, decisión K): la
/// fuente queda de consulta, y su resumen, su síntesis, sus palabras clave, su
/// Mapa y sus tarjetas viven en su documento procesado.
///
/// Con documento procesado, «Estudiarlo en Procesado» lo abre —también si
/// está en la papelera: allá se ve y se restaura—.
///
/// Sin él no dibuja nada, ni el espacio de arriba: para tenerlo hay que
/// triarla, y eso se hace desde la tarjeta «Bandeja» del detalle
/// (`InboxStandingLine`), el único lugar que lo ofrece (F45, paso 7c). Antes
/// esta línea decía «Para estudiarlo, triálo» con su propio botón, y en una
/// fuente ya triada «Volver a triar» salía dos veces.
class SourceStudyLine extends ConsumerWidget {
  const SourceStudyLine({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Mientras se averigua, nada: lo mismo que sin documento.
    final processed = ref
        .watch(processedDocumentForSourceProvider(item.id))
        .valueOrNull;
    if (processed == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _Line(
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
      ),
    );
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
