import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/on_device_image_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/daily_quota_sheet.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/hugging_face_token_sheet.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/on_device_image_models.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Ilustraciones y cuota diaria» en Ajustes → IA (F43): la entrada a «¿Qué
/// puede cada IA?», cada cuenta —las de escribir y las de Hugging Face— con
/// si puede dibujar y su cuota del día, y agregar Hugging Face. Tocar una
/// cuenta abre su cuota; el menú, probarla y lo demás.
class IllustrationSettingsSection extends ConsumerWidget {
  const IllustrationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    ref
      ..watch(illustrationStoreChangesProvider)
      ..watch(aiUsageChangesProvider);
    final text = ref.watch(aiAccountsProvider).valueOrNull ?? const [];
    final sides = {
      for (final side in ref.watch(illustrationSidesProvider))
        side.account.id: side,
    };
    final own = ref.watch(imageAccountsProvider).valueOrNull ?? const [];
    ref.watch(onDeviceImageChangesProvider);
    final onDevice = ref.watch(stableDiffusionImageEngineProvider);

    return Column(
      key: const Key('illustration-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.f43AiSettingsTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.f43AiSettingsHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                key: const Key('illustration-settings-table'),
                leading: Icon(
                  Icons.table_chart_outlined,
                  color: scheme.primary,
                ),
                title: Text(l10n.f43AiCardInfo),
                subtitle: Text(l10n.f43AiSettingsTableHint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(openAiCapabilitiesScreen(context)),
              ),
              // «Imágenes en el teléfono (Exigente)», solo si la app trae el
              // motor (F43, paso 3b).
              if (onDevice != null) ...[
                const Divider(height: 1),
                ListTile(
                  key: const Key('illustration-settings-on-device'),
                  leading: Icon(
                    Icons.smartphone_outlined,
                    color: scheme.tertiary,
                  ),
                  title: Text(l10n.f43DeviceScreenTitle),
                  subtitle: Text(onDeviceSummaryLine(l10n, onDevice)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(openOnDeviceImageScreen(context)),
                ),
              ],
              for (final account in text)
                if (account.provider.isCloud) ...[
                  const Divider(height: 1),
                  _AccountRow(
                    id: account.id,
                    label: account.label,
                    textProvider: account.provider,
                    side: sides[account.id],
                  ),
                ],
              for (final account in own) ...[
                const Divider(height: 1),
                _AccountRow(
                  id: account.id,
                  label: account.label,
                  side: sides[account.id],
                  own: account,
                ),
              ],
              const Divider(height: 1),
              ListTile(
                key: const Key('illustration-settings-add-hf'),
                leading: Icon(Icons.add, color: scheme.primary),
                title: Text(
                  l10n.f43AiAddHuggingFace,
                  style: TextStyle(color: scheme.primary),
                ),
                onTap: () => unawaited(showHuggingFaceTokenSheet(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _RowAction { quota, rename, replaceToken, delete }

/// Una cuenta: quién es, si dibuja y su cuota de hoy.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({
    required this.id,
    required this.label,
    this.textProvider,
    this.side,
    this.own,
  });

  final String id;
  final String label;

  /// El de escribir, en las de F32; `null` en las de Hugging Face.
  final AiProvider? textProvider;

  /// Lo que se sabe de ella para dibujar; `null` si no dibuja (Claude).
  final ImageSide? side;

  /// La cuenta propia de imágenes, si es una de Hugging Face.
  final IllustrationAccount? own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = ref.watch(illustrationStoreProvider);
    final now = ref.watch(clockProvider)();
    final usage = ref.watch(aiUsageLedgerProvider).usageOf(id, now: now);
    final quota = effectiveDailyQuota(store, id, textProvider: textProvider);
    final providerName =
        textProvider?.label(l10n) ??
        IllustrationProvider.huggingFace.label(l10n);
    final drawing = side;

    final capability = drawing == null
        ? l10n.f43AiTextOnly
        : imageCapabilityLine(l10n, drawing.account, drawing.capability);
    final String quotaLine;
    if (quota == null || quota.isEmpty) {
      quotaLine = l10n.f43AiQuotaUnset;
    } else {
      final share = CreationCostEstimator.quotaShare(
        accountId: id,
        label: label,
        usage: usage,
        quota: quota,
        requests: 0,
        tokens: 0,
        images: 0,
        usd: 0,
        usedUsd: CreationCostEstimator.usedUsdOf(
          usage,
          textProvider == null
              ? null
              : textModelPrice(
                  textProvider!,
                  ref.watch(aiModelSettingsProvider).modelOf(textProvider!),
                ),
        ),
      );
      final base = l10n.f43AiQuotaPerDay(dailyQuotaParts(context, quota));
      final today = l10n.f43AiQuotaTodayPercent(
        aiPercent(context, share.percentUsed ?? 0),
      );
      quotaLine = quota.isEstimate
          ? '$base (${l10n.f43AiEstimated}) · $today'
          : '$base · $today';
    }
    final canProbe = drawing != null && !drawing.capability.can;
    final stateColor = switch (drawing?.capability.state) {
      ImageCapabilityState.cannot => scheme.error,
      ImageCapabilityState.untested => scheme.tertiary,
      _ => scheme.onSurfaceVariant,
    };

    final tile = ListTile(
      key: Key('illustration-account-$id'),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(
          textProvider?.icon ?? IllustrationProvider.huggingFace.icon,
          size: 20,
        ),
      ),
      title: Text(label, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$providerName · $capability',
            style: theme.textTheme.bodySmall?.copyWith(color: stateColor),
          ),
          Text(
            quotaLine,
            key: Key('illustration-account-quota-$id'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => unawaited(
        showDailyQuotaSheet(
          context,
          accountId: id,
          label: label,
          textProvider: textProvider,
        ),
      ),
      trailing: PopupMenuButton<_RowAction>(
        key: Key('illustration-account-menu-$id'),
        tooltip: l10n.lmAccountMenu,
        onSelected: (action) => unawaited(_act(context, ref, action)),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _RowAction.quota,
            child: ListTile(
              leading: const Icon(Icons.data_usage),
              title: Text(l10n.f43AiMenuQuota),
            ),
          ),
          if (own != null) ...[
            PopupMenuItem(
              value: _RowAction.rename,
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.commonRename),
              ),
            ),
            PopupMenuItem(
              value: _RowAction.replaceToken,
              child: ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l10n.f43AiMenuReplaceToken),
              ),
            ),
            PopupMenuItem(
              value: _RowAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!canProbe) return tile;
    // «Probar ahora» va debajo, fuera de la fila: tocar la fila abre la
    // cuota, y un pedido que cuesta no se hace por error.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: ProbeImageAccountButton(side: drawing),
        ),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _RowAction action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final actions = ref.read(illustrationActionsProvider);
    final account = own;
    switch (action) {
      case _RowAction.quota:
        await showDailyQuotaSheet(
          context,
          accountId: id,
          label: label,
          textProvider: textProvider,
        );
      case _RowAction.rename:
        if (account == null) return;
        final name = await showDialog<String>(
          context: context,
          builder: (context) => _RenameDialog(initial: account.label),
        );
        if (name != null && name.trim().isNotEmpty) {
          await actions.rename(account, name.trim());
        }
      case _RowAction.replaceToken:
        if (account == null) return;
        await showHuggingFaceTokenSheet(context, replacing: account);
      case _RowAction.delete:
        if (account == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.lmAccountDeleteTitle(account.label)),
            content: Text(l10n.lmAccountDeleteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('illustration-account-delete-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        );
        if (ok ?? false) await actions.remove(account);
    }
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.commonRename),
      content: TextField(
        key: const Key('illustration-rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.lmNameLabel),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.lmSave),
        ),
      ],
    );
  }
}
