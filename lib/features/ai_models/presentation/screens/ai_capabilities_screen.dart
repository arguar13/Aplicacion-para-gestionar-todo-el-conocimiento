import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «¿Qué puede cada IA?» encima de lo que haya (una hoja de crear,
/// Ajustes → IA). Va por el `Navigator` y no por una ruta: se abre desde una
/// hoja, y al cerrarla se vuelve a la hoja tal como estaba.
Future<void> openAiCapabilitiesScreen(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const AiCapabilitiesScreen()));

/// «¿Qué puede cada IA?» (F43, «H en detalle»): qué hace cada proveedor
/// —escribir, dibujar—, cuánto cuesta y qué pide, con los precios de la
/// tabla fechada; cada cuenta de la persona marcada como **puede**, **no
/// puede** o **sin probar**, con «Probar ahora»; los modelos de código
/// abierto con su enlace, su licencia y lo que piden; y, si hay un motor
/// registrado, «Exigente — en el teléfono».
class AiCapabilitiesScreen extends ConsumerWidget {
  const AiCapabilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final engine = ref.watch(onDeviceImageEngineProvider);
    final date = DateFormat.yMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(kAiPricesVerifiedOn);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.f43AiCardInfo)),
      body: ListView(
        key: const Key('ai-capabilities-list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            key: const Key('ai-capabilities-date'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.f43AiPricesAsOf(date),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final row in const [
            AiCapabilityRow.gemma,
            AiCapabilityRow.claude,
            AiCapabilityRow.gemini,
            AiCapabilityRow.openAi,
            AiCapabilityRow.huggingFace,
          ]) ...[_ProviderCard(row: row), const SizedBox(height: 12)],
          const SizedBox(height: 12),
          _SectionTitle(
            l10n.f43AiOpenTitle,
            hint: l10n.f43AiOpenIntro,
            icon: Icons.public,
          ),
          for (final model in kOpenImageModels) ...[
            _OpenModelTile(model: model),
            const SizedBox(height: 10),
          ],
          // La sección del teléfono, solo si hay un motor registrado.
          if (engine != null) ...[
            const SizedBox(height: 16),
            _SectionTitle(
              l10n.f43AiProviderOnDevice,
              hint: l10n.f43AiOnDeviceIntro,
              icon: Icons.smartphone_outlined,
            ),
            const _ProviderCard(
              key: Key('ai-capabilities-on-device'),
              row: AiCapabilityRow.onDevice,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.icon, this.hint});

  final String title;
  final IconData icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo de cada fila, en palabras.
({String text, String images, String cost, String needs, String name})
_rowTexts(BuildContext context, AiCapabilityRow row) {
  final l10n = AppLocalizations.of(context)!;
  String cheapest() {
    final prices = row.imagePrices;
    if (prices.isEmpty) return '';
    return aiUsd(context, prices.first.usdFor(IllustrationSize.standard));
  }

  String cheapestName() {
    final prices = row.imagePrices;
    return prices.isEmpty ? '' : prices.first.displayName;
  }

  return switch (row) {
    AiCapabilityRow.gemma => (
      name: l10n.lmProviderGemma,
      text: l10n.f43AiRowGemmaText,
      images: l10n.f43AiRowGemmaImages,
      cost: l10n.f43AiRowGemmaCost,
      needs: l10n.f43AiRowGemmaNeeds,
    ),
    AiCapabilityRow.claude => (
      name: l10n.lmProviderAnthropic,
      text: l10n.f43AiRowClaudeText,
      images: l10n.f43AiRowClaudeImages,
      cost: l10n.f43AiRowClaudeCost,
      needs: l10n.f43AiRowClaudeNeeds,
    ),
    AiCapabilityRow.gemini => (
      name: l10n.lmProviderGemini,
      text: l10n.f43AiRowGeminiText,
      images: l10n.f43AiRowGeminiImages,
      cost: l10n.f43AiRowGeminiCost(cheapest(), cheapestName()),
      needs: l10n.f43AiRowGeminiNeeds,
    ),
    AiCapabilityRow.openAi => (
      name: l10n.lmProviderOpenAi,
      text: l10n.f43AiRowOpenAiText,
      images: l10n.f43AiRowOpenAiImages,
      cost: l10n.f43AiRowOpenAiCost(cheapest(), cheapestName()),
      needs: l10n.f43AiRowOpenAiNeeds,
    ),
    AiCapabilityRow.huggingFace => (
      name: l10n.f43AiProviderHuggingFace,
      text: l10n.f43AiRowHfText,
      images: l10n.f43AiRowHfImages,
      cost: l10n.f43AiRowHfCost,
      needs: l10n.f43AiRowHfNeeds,
    ),
    AiCapabilityRow.onDevice => (
      name: l10n.f43AiProviderOnDevice,
      text: l10n.f43AiRowDeviceText,
      images: l10n.f43AiRowDeviceImages,
      cost: l10n.f43AiRowDeviceCost,
      needs: l10n.f43AiRowDeviceNeeds,
    ),
  };
}

IconData _rowIcon(AiCapabilityRow row) =>
    row.textProvider?.icon ?? row.illustrationProvider!.icon;

/// La tarjeta de un proveedor: sus cuatro datos y las cuentas de la persona.
class _ProviderCard extends ConsumerWidget {
  const _ProviderCard({required this.row, super.key});

  final AiCapabilityRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final texts = _rowTexts(context, row);
    // Un acento distinto por proveedor, del tema elegido.
    final accents = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
    ];
    final (accent, onAccent) = accents[row.index % accents.length];

    return Container(
      key: Key('ai-capability-row-${row.name}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
                child: Icon(_rowIcon(row), color: onAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texts.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Fact(label: l10n.f43AiColText, value: texts.text, ok: row.writes),
          _Fact(
            label: l10n.f43AiColImages,
            value: texts.images,
            ok: row.illustrates,
          ),
          _Fact(label: l10n.f43AiColCost, value: texts.cost),
          _Fact(label: l10n.f43AiColNeeds, value: texts.needs),
          _Accounts(row: row),
        ],
      ),
    );
  }
}

/// Un dato de la fila: el rótulo arriba y lo que dice abajo, para que entre
/// en 360 dp con el texto grande.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.ok});

  final String label;
  final String value;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success =
        theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: ok == null
                ? Icon(Icons.circle, size: 6, color: scheme.outline)
                : Icon(
                    ok! ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: ok! ? success : scheme.error,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Las cuentas de la persona de esta fila, con su estado.
class _Accounts extends ConsumerWidget {
  const _Accounts({required this.row});

  final AiCapabilityRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final drawing = row.illustrationProvider;
    final sides = [
      for (final side in ref.watch(illustrationSidesProvider))
        if (side.account.provider == drawing) side,
    ];
    final textOnly = row == AiCapabilityRow.claude
        ? [
            for (final a
                in ref.watch(aiAccountsProvider).valueOrNull ??
                    const <AiAccount>[])
              if (a.provider == AiProvider.anthropic) a,
          ]
        : const <AiAccount>[];
    if (sides.isEmpty && textOnly.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          l10n.f43AiYourAccounts,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final account in textOnly)
          _AccountLine(
            label: account.label,
            state: l10n.f43AiTextOnly,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        for (final side in sides) _ImageAccountLine(side: side),
      ],
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({
    required this.label,
    required this.state,
    required this.color,
    this.detail,
    this.trailing,
    super.key,
  });

  final String label;
  final String state;
  final Color color;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  state,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Una cuenta que dibuja: puede / no puede (con su porqué) / sin probar, y
/// «Probar ahora» si no se sabe que puede.
class _ImageAccountLine extends StatelessWidget {
  const _ImageAccountLine({required this.side});

  final ImageSide side;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success =
        theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    final capability = side.capability;
    final account = side.account;
    final (state, color) = switch (capability.state) {
      ImageCapabilityState.can => (l10n.f43AiStateCan, success),
      ImageCapabilityState.cannot => (l10n.f43AiStateCannot, scheme.error),
      ImageCapabilityState.untested => (
        l10n.f43AiStateUntested,
        scheme.tertiary,
      ),
    };
    final String? detail;
    if (account.provider.isOnDevice) {
      detail = capability.cannot
          ? capitalized(
              illustrationReason(
                l10n,
                capability.reason ?? ImageFailure.unknown,
              ),
            )
          : side.timePerImage == null
          ? l10n.f43AiOnDeviceReady
          : side.timeMeasured
          ? l10n.f43DeviceTimeLineMeasured(aiDuration(l10n, side.timePerImage!))
          : l10n.f43DeviceTimeLineEstimated(
              aiDuration(l10n, side.timePerImage!),
            );
    } else if (capability.cannot) {
      detail = capitalized(
        illustrationReason(
          l10n,
          capability.reason ?? ImageFailure.unknown,
          account: account.label,
        ),
      );
    } else {
      detail = side.modelLabel;
    }
    return _AccountLine(
      key: Key('ai-capability-account-${account.id}'),
      label: account.label,
      state: state,
      color: color,
      detail: detail,
      trailing: account.provider.isOnDevice || capability.can
          ? null
          : ProbeImageAccountButton(side: side),
    );
  }
}

/// «Probar ahora»: un solo pedido de una imagen chica, solo cuando se toca.
class ProbeImageAccountButton extends ConsumerStatefulWidget {
  const ProbeImageAccountButton({required this.side, super.key});

  final ImageSide side;

  @override
  ConsumerState<ProbeImageAccountButton> createState() =>
      _ProbeImageAccountButtonState();
}

class _ProbeImageAccountButtonState
    extends ConsumerState<ProbeImageAccountButton> {
  var _probing = false;

  Future<void> _probe() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final account = widget.side.account;
    void say(String text) => messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );
    setState(() => _probing = true);
    try {
      final result = await ref.read(illustrationActionsProvider).probe(account);
      say(
        result.can
            ? l10n.f43AiProbeOk(account.label)
            : l10n.f43AiProbeCannot(
                account.label,
                illustrationReason(
                  l10n,
                  result.reason ?? ImageFailure.unknown,
                  account: account.label,
                ),
              ),
      );
    } on ImageGenerationException catch (error) {
      say(
        l10n.f43AiProbeError(
          illustrationReason(l10n, error.failure, account: account.label),
        ),
      );
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final side = widget.side;
    final cost = imageCostOf(
      side.account.provider,
      model: side.model ?? '',
      size: IllustrationSize.small,
    ).usd;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: Key('ai-probe-${side.account.id}'),
            onPressed: _probing ? null : () => unawaited(_probe()),
            icon: _probing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(_probing ? l10n.f43AiProbing : l10n.f43AiProbe),
          ),
          Text(
            cost == null
                ? l10n.f43AiProbeHintFree
                : l10n.f43AiProbeHint(aiUsd(context, cost)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un modelo de código abierto: su nombre, «por Hugging Face (en la nube)»,
/// su licencia en una línea, qué pide y el enlace a su ficha.
class _OpenModelTile extends StatelessWidget {
  const _OpenModelTile({required this.model});

  final OpenImageModel model;

  Future<void> _open(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await launchExternalUrl(model.url)) return;
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: SelectableText(l10n.f43AiOpenLinkFailed(model.url)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final params = NumberFormat('0.#', locale).format(model.billionParameters);
    final license = openModelLicenseLine(l10n, model.license);
    final needs = [
      l10n.f43AiOpenParams(params),
      if (model.minVideoMemoryGb case final gb?) l10n.f43AiOpenVram(gb),
    ].join(' · ');
    return Container(
      key: Key('ai-open-model-${model.key}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            model.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            l10n.f43AiOpenViaHf,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(height: 6),
          _Line(icon: Icons.gavel_outlined, text: license),
          _Line(icon: Icons.developer_board_outlined, text: needs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('ai-open-model-link-${model.key}'),
              onPressed: () => unawaited(_open(context)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.f43AiOpenLink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Lo que se sabe de [account] para mostrarlo en una línea: «puede»,
/// «no puede: …» o «sin probar». Para Ajustes → IA.
String imageCapabilityLine(
  AppLocalizations l10n,
  IllustrationAccount account,
  ImageCapability capability,
) {
  switch (capability.state) {
    case ImageCapabilityState.can:
      return l10n.f43AiStateCan;
    case ImageCapabilityState.untested:
      return l10n.f43AiStateUntested;
    case ImageCapabilityState.cannot:
      final reason = illustrationReason(
        l10n,
        capability.reason ?? ImageFailure.unknown,
        account: account.label,
      );
      return '${l10n.f43AiStateCannot}: $reason';
  }
}
