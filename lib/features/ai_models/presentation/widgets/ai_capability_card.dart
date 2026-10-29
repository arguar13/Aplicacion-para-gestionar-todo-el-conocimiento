import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_key_sheet.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_model_picker.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/hugging_face_token_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Con tu IA actual» (F43, «H en detalle»): la tarjeta que va encima de
/// «Generar ahora» en la hoja de la Presentación y de la Infografía.
///
/// - **Qué va a poder hacer**, con ✓ y ✗: escribir con el modelo elegido y
///   dibujar las ilustraciones, o por qué no («tu cuenta de Gemini no tiene
///   facturación activa», «Claude no genera imágenes»).
/// - **Cuánto va a consumir**: los tokens de lectura y escritura, las
///   imágenes con su tamaño y precio, el total y el porcentaje de la cuota de
///   hoy («≈ 18 % de tu cuota de hoy · ya usaste 42 %»); con Gemma, el tiempo.
/// - **Si no puede dibujar, las opciones**, tocables y en orden. Elegir
///   «seguir sin ilustraciones», otra cuenta o el modelo del teléfono llama a
///   [onAlternative] (la hoja cambia lo pedido y la estimación se rehace);
///   agregar una clave abre la hoja de claves acá mismo.
/// - **ⓘ** abre «¿Qué puede cada IA?».
///
/// Sin animaciones; entra en 360 dp con el texto grande.
///
/// Con [illustrationsOnly], para rehacer o completar ilustraciones de una
/// creación ya escrita: sin la línea de escribir ni los tokens del texto, que
/// no se gastan.
class AiCapabilityCard extends ConsumerWidget {
  const AiCapabilityCard({
    required this.estimate,
    this.onAlternative,
    this.illustrationsOnly = false,
    super.key,
  });

  final CreationEstimate estimate;

  /// Si solo se dibuja: no se escribe nada.
  final bool illustrationsOnly;

  /// Se eligió una opción que cambia lo pedido: seguir sin ilustraciones,
  /// otra cuenta o el modelo del teléfono.
  final ValueChanged<IllustrationAlternative>? onAlternative;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = estimate.text;
    final writer =
        text.modelLabel ??
        (text.provider.isCloud
            ? text.provider.label(l10n)
            : watchChosenModelTitle(ref, l10n));

    return Container(
      key: const Key('ai-capability-card'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: scheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.f43AiCardTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('ai-capability-info'),
                tooltip: l10n.f43AiCardInfo,
                onPressed: () => unawaited(openAiCapabilitiesScreen(context)),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!illustrationsOnly)
                  _CheckLine(
                    key: const Key('ai-capability-text'),
                    ok: estimate.canWriteText,
                    text: estimate.canWriteText
                        ? l10n.f43AiWriteWith(writer)
                        : l10n.f43AiWriteBlocked(
                            textProblemReason(l10n, estimate.textProblem!),
                          ),
                  ),
                if (estimate.wantsIllustrations) ...[
                  if (!illustrationsOnly) const SizedBox(height: 6),
                  _illustrationLine(l10n),
                ],
                const SizedBox(height: 12),
                _Consumption(
                  estimate: estimate,
                  illustrationsOnly: illustrationsOnly,
                ),
                ..._quotaLines(context, l10n),
                if (estimate.alternatives.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    l10n.f43AiAltTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final (i, alternative)
                      in estimate.alternatives.indexed) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _AlternativeRow(
                      number: i + 1,
                      alternative: alternative,
                      writer: writer,
                      onTap: () =>
                          unawaited(_choose(context, ref, alternative)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _illustrationLine(AppLocalizations l10n) {
    final side = estimate.imageSide;
    if (!estimate.canIllustrate) {
      return _CheckLine(
        key: const Key('ai-capability-images'),
        ok: false,
        text: l10n.f43AiIllustrateBlocked(
          illustrationReason(
            l10n,
            estimate.illustrateReason!,
            account: side?.account.label,
            textProvider: estimate.text.provider,
          ),
        ),
      );
    }
    final model =
        side!.modelLabel ?? side.model ?? side.account.provider.label(l10n);
    final account = side.account.provider.isOnDevice
        ? model
        : '$model · ${side.account.label}';
    return _CheckLine(
      key: const Key('ai-capability-images'),
      ok: true,
      untested: side.capability.untested,
      text: l10n.f43AiIllustrateWith(estimate.images, account),
      detail: side.capability.untested ? l10n.f43AiIllustrateUntested : null,
    );
  }

  List<Widget> _quotaLines(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final lines = <Widget>[];
    final two = estimate.quota.length > 1;
    for (final share in estimate.quota) {
      final String line;
      if (!share.hasQuota) {
        line = two
            ? '${share.accountLabel}: ${l10n.f43AiQuotaNone}'
            : l10n.f43AiQuotaNone;
      } else {
        final estimateText = aiPercent(context, share.percentOfQuota!);
        final used = aiPercent(context, share.percentUsed ?? 0);
        final base = two
            ? l10n.f43AiQuotaShareOf(share.accountLabel, estimateText, used)
            : l10n.f43AiQuotaShare(estimateText, used);
        line = share.quotaIsEstimate ? '$base (${l10n.f43AiEstimated})' : base;
      }
      lines
        ..add(const SizedBox(height: 8))
        ..add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.data_usage,
                size: 16,
                color: share.wouldExceed ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  share.wouldExceed
                      ? '$line. ${l10n.f43AiQuotaWouldExceed}'
                      : line,
                  key: Key('ai-capability-quota-${share.accountId}'),
                  style: share.wouldExceed
                      ? style?.copyWith(color: scheme.error)
                      : style,
                ),
              ),
            ],
          ),
        );
    }
    final local = estimate.localTime;
    if (local != null) {
      final drawsHere =
          estimate.canIllustrate &&
          (estimate.imageSide?.account.provider.isOnDevice ?? false);
      final time = aiDuration(l10n, local);
      lines
        ..add(const SizedBox(height: 8))
        ..add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.smartphone_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    l10n.f43AiLocalTime(
                      estimate.localTimeIsEstimate
                          ? '$time (${l10n.f43AiEstimated})'
                          : time,
                    ),
                    if (drawsHere) l10n.f43AiLocalHeat,
                  ].join('. '),
                  key: const Key('ai-capability-local'),
                  style: style,
                ),
              ),
            ],
          ),
        );
    }
    return lines;
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    IllustrationAlternative alternative,
  ) async {
    switch (alternative) {
      case ContinueWithoutIllustrations() ||
          UseOtherImageAccount() ||
          UseOnDeviceModel():
        onAlternative?.call(alternative);
      case AddImageKey(:final provider):
        final text = provider.textProvider!;
        if (!await ensureAiPrivacyAccepted(context, ref, text)) return;
        if (!context.mounted) return;
        await showAiKeySheet(context, provider: text);
      case AddHuggingFaceToken():
        await showHuggingFaceTokenSheet(context);
    }
  }
}

/// Una línea con ✓ o ✗ (o el ✓ tenue de «sin probar»).
class _CheckLine extends StatelessWidget {
  const _CheckLine({
    required this.ok,
    required this.text,
    this.untested = false,
    this.detail,
    super.key,
  });

  final bool ok;
  final bool untested;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success =
        theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    final color = !ok
        ? scheme.error
        : untested
        ? scheme.tertiary
        : success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            ok
                ? (untested ? Icons.help_outline : Icons.check_circle)
                : Icons.cancel,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: theme.textTheme.bodyMedium),
              if (detail != null)
                Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Las fichas de lo que consume: tokens, imágenes y costo.
class _Consumption extends StatelessWidget {
  const _Consumption({required this.estimate, this.illustrationsOnly = false});

  final CreationEstimate estimate;
  final bool illustrationsOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <String>[];
    final textUsd = estimate.textUsd;
    if (!illustrationsOnly) {
      chips
        ..add(l10n.f43AiTokensRead(aiTokens(context, estimate.inputTokens)))
        ..add(l10n.f43AiTokensWrite(aiTokens(context, estimate.outputTokens)));
      if (textUsd == null) {
        chips.add(l10n.f43AiTextCostUnknown);
      } else if (textUsd == 0) {
        chips.add(l10n.f43AiTextFree);
      } else {
        chips.add(l10n.f43AiTextCost(aiUsd(context, textUsd)));
      }
    }
    if (estimate.wantsIllustrations && estimate.canIllustrate) {
      final size = illustrationSizeLabel(l10n, estimate.imageSize);
      final side = estimate.imageSide!;
      final usd = estimate.imagesUsd;
      if (side.account.provider.isOnDevice) {
        chips.add(l10n.f43AiImagesFree(estimate.images));
      } else if (usd == null) {
        chips.add(l10n.f43AiImagesCredits(estimate.images, size));
      } else {
        chips.add(
          l10n.f43AiImagesCost(estimate.images, size, aiUsd(context, usd)),
        );
      }
    }
    final total = estimate.totalUsd;
    final showTotal =
        !illustrationsOnly &&
        total != null &&
        total > 0 &&
        estimate.canIllustrate &&
        (estimate.textUsd ?? 0) > 0;
    if (showTotal) chips.add(l10n.f43AiTotalCost(aiUsd(context, total)));

    return Wrap(
      key: const Key('ai-capability-consumption'),
      spacing: 6,
      runSpacing: 6,
      children: [for (final chip in chips) _Chip(chip)],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}

/// Una opción tocable, con su número.
class _AlternativeRow extends StatelessWidget {
  const _AlternativeRow({
    required this.number,
    required this.alternative,
    required this.writer,
    required this.onTap,
  });

  final int number;
  final IllustrationAlternative alternative;
  final String writer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (title, hint, icon) = switch (alternative) {
      ContinueWithoutIllustrations() => (
        l10n.f43AiAltWithout,
        l10n.f43AiAltWithoutHint,
        Icons.dashboard_customize_outlined,
      ),
      UseOtherImageAccount(:final account, :final untested, :final imagesUsd) =>
        (
          l10n.f43AiAltUseAccount(account.provider.label(l10n), account.label),
          [
            l10n.f43AiAltUseAccountHint(writer),
            if (imagesUsd != null) '≈ ${aiUsd(context, imagesUsd)}',
            if (untested) l10n.f43AiAltUntested,
          ].join(' · '),
          account.provider.icon,
        ),
      UseOnDeviceModel(
        :final time,
        :final needsDownload,
        :final timeMeasured,
      ) =>
        (
          l10n.f43AiAltOnDevice,
          needsDownload
              ? l10n.f43AiAltOnDeviceDownload
              : timeMeasured
              ? l10n.f43AiAltOnDeviceHint(aiDuration(l10n, time))
              : l10n.f43DeviceAltHintEstimated(aiDuration(l10n, time)),
          IllustrationProvider.onDevice.icon,
        ),
      AddImageKey(provider: IllustrationProvider.openAi) => (
        l10n.f43AiAltAddOpenAi,
        l10n.f43AiAltAddOpenAiHint,
        AiProvider.openAi.icon,
      ),
      AddImageKey() => (
        l10n.f43AiAltAddGemini,
        l10n.f43AiAltAddGeminiHint,
        AiProvider.gemini.icon,
      ),
      AddHuggingFaceToken() => (
        l10n.f43AiAltHuggingFace,
        l10n.f43AiAltHuggingFaceHint,
        IllustrationProvider.huggingFace.icon,
      ),
    };
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('ai-alternative-$number'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(icon, size: 16, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. $title',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
