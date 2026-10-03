import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La línea de cada elemento (F27), dentro del panel de la fuente: «✨ La IA
/// organizó esto — 4 vínculos · 6 tarjetas · 3 temas», con «Ver», el botón
/// para deshacer lo de la IA y, si dejó dudas, cuántas hay para revisar. Si
/// lo último que hizo se deshizo, lo dice y ofrece «Volver a organizar»: la
/// IA no lo vuelve a tocar sola, y este es el lugar donde se nota.
///
/// Cuenta solo lo que sigue en pie: lo que la persona editó ya es suyo y lo
/// que borró no está. Quien la pone decide si va —ver
/// `AiItemSummary.isVisible`—, porque el panel separa sus franjas con una
/// línea y una franja vacía dejaría la línea sola.
///
/// No usa `ListTile` ni `FilterChip`: el detalle los cuenta en sus pruebas
/// para saber qué vínculos y qué chips muestra.
class AiOrganizedLine extends ConsumerStatefulWidget {
  const AiOrganizedLine({
    required this.itemId,
    required this.itemTitle,
    required this.summary,
    super.key,
  });

  final String itemId;
  final String itemTitle;
  final AiItemSummary summary;

  @override
  ConsumerState<AiOrganizedLine> createState() => _AiOrganizedLineState();
}

class _AiOrganizedLineState extends ConsumerState<AiOrganizedLine> {
  var _undoing = false;

  void _see() =>
      unawaited(context.push(RoutePaths.aiActivityFor(widget.itemId)));

  void _reorganize() =>
      unawaited(organizeNowWithAi(context, ref, itemId: widget.itemId));

  Future<void> _undoAll() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAiUndo(
      context,
      itemTitle: widget.itemTitle,
      tally: widget.summary.remaining,
      wholeItem: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _undoing = true);
    final result = await ref
        .read(aiRunRepositoryProvider)
        .undoItem(widget.itemId);
    // Los vínculos y las tarjetas del elemento avisan solos que cambiaron;
    // las pasadas no son una consulta que se mire, y la que se deshizo tiene
    // que dejar de contar ya.
    ref.invalidate(aiItemRunsProvider(widget.itemId));
    if (mounted) setState(() => _undoing = false);
    showAiUndoResult(messenger, l10n, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = widget.summary;
    final organized = !summary.remaining.isEmpty;
    // Lo que sigue en pie manda: si se deshizo solo la última pasada, la
    // línea sigue contando lo de antes, y además ofrece volver a organizar.
    final title = organized
        ? l10n.aiItemLineTitle
        : summary.undone
        ? l10n.aiItemLineUndoneTitle
        : l10n.aiItemLineReviewOnly;
    final detail = organized
        ? aiTallyText(l10n, summary.remaining)
        : summary.undone
        ? l10n.aiItemLineUndoneMessage
        : null;
    final compact = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );

    return Padding(
      key: const Key('ai-organized-line'),
      padding: const EdgeInsets.fromLTRB(
        sourcePanelInset,
        14,
        sourcePanelInset - 8,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiSparkCircle(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (detail != null)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            detail,
                            key: ValueKey(detail),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (summary.reviewCount > 0)
                      _ReviewPill(count: summary.reviewCount, onTap: _see),
                    TextButton(
                      key: const Key('ai-organized-line-see'),
                      style: compact,
                      onPressed: _see,
                      child: Text(l10n.aiItemLineSee),
                    ),
                    if (organized)
                      TextButton.icon(
                        key: const Key('ai-organized-line-undo-all'),
                        style: compact,
                        onPressed: _undoing ? null : _undoAll,
                        icon: const Icon(Icons.undo, size: 18),
                        label: Text(l10n.aiItemUndoAll),
                      ),
                    if (summary.undone)
                      TextButton.icon(
                        key: const Key('ai-organized-line-reorganize'),
                        style: compact,
                        onPressed: _reorganize,
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: Text(l10n.aiItemReorganize),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «2 para revisar», en el color de la IA: lo único de la línea que pide
/// algo de la persona.
class _ReviewPill extends StatelessWidget {
  const _ReviewPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      key: const Key('ai-organized-line-review'),
      color: scheme.tertiaryContainer,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.aiReviewPendingCount(count),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
