import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Uso de IA» (F43, la hoja de personalizar): una barra con lo ya usado hoy
/// en la cuenta y, más oscuro, lo que estima esta creación. Con Gemma no hay
/// cuota: dice cuánto puede tardar. Sin cuota fijada, lo dice.
///
/// Mide contra la cuota que más aprieta de la cuenta que más gasta
/// ([CreationEstimate.quota]); el detalle de cada cuenta lo da la tarjeta
/// «Con tu IA actual».
class AiUsageBar extends StatelessWidget {
  const AiUsageBar({required this.estimate, super.key});

  final CreationEstimate estimate;

  /// La cuota que se muestra: la que quedaría más llena.
  static QuotaShare? mainShare(CreationEstimate estimate) {
    QuotaShare? best;
    for (final share in estimate.quota) {
      if (!share.hasQuota) continue;
      final total = (share.percentUsed ?? 0) + share.percentOfQuota!;
      final bestTotal = best == null
          ? -1
          : (best.percentUsed ?? 0) + best.percentOfQuota!;
      if (total > bestTotal) best = share;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final share = mainShare(estimate);
    final local = estimate.localTime;

    final String detail;
    if (share != null) {
      final estimated = share.quotaIsEstimate
          ? ' (${l10n.f43AiEstimated})'
          : '';
      final today = aiPercent(context, share.percentUsed ?? 0);
      final mine = aiPercent(context, share.percentOfQuota!);
      detail =
          '${l10n.f43AiUsageLegendToday(today)} · '
          '${l10n.f43AiUsageLegendThis(mine)}$estimated';
    } else if (local != null && estimate.quota.isEmpty) {
      detail = l10n.f43AiLocalTime(aiDuration(l10n, local));
    } else {
      detail = l10n.f43AiUsageNoQuota;
    }

    return Semantics(
      container: true,
      label: share == null
          ? '${l10n.f43AiUsageTitle}: $detail'
          : l10n.f43AiUsageSemantics(
              aiPercent(context, share.percentUsed ?? 0),
              aiPercent(context, share.percentOfQuota!),
            ),
      excludeSemantics: true,
      child: Column(
        key: const Key('ai-usage-bar'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.f43AiUsageTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                detail,
                key: const Key('ai-usage-detail'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: share != null && share.wouldExceed
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (share != null) ...[
            const SizedBox(height: 8),
            _TwoToneBar(
              used: (share.percentUsed ?? 0) / 100,
              estimate: share.percentOfQuota! / 100,
              exceeds: share.wouldExceed,
            ),
          ],
        ],
      ),
    );
  }
}

/// La barra en dos tonos: lo usado, claro; lo de esta creación, a
/// continuación y más oscuro (rojo si se pasa).
class _TwoToneBar extends StatelessWidget {
  const _TwoToneBar({
    required this.used,
    required this.estimate,
    required this.exceeds,
  });

  final double used;
  final double estimate;
  final bool exceeds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usedPart = used.clamp(0.0, 1.0);
    final estimatePart = estimate.clamp(0.0, 1.0 - usedPart);
    final strong = exceeds ? scheme.error : scheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: scheme.surfaceContainerHighest),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * usedPart,
                  child: ColoredBox(
                    key: const Key('ai-usage-used'),
                    color: strong.withValues(alpha: 0.38),
                  ),
                ),
                Positioned(
                  left: width * usedPart,
                  top: 0,
                  bottom: 0,
                  // Siempre se ve un poco: una creación chica no es «nada».
                  width: estimate > 0
                      ? math.min(width, math.max(3, width * estimatePart))
                      : 0,
                  child: ColoredBox(
                    key: const Key('ai-usage-estimate'),
                    color: strong,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
