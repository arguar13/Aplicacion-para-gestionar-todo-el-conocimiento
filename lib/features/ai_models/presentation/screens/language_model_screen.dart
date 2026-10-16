import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_account_switcher.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_key_sheet.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las opciones del tope diario de la IA de fondo; la última es «sin tope».
const kBackgroundCapChoices = [
  25,
  50,
  100,
  200,
  500,
  AiModelSettings.maxDailyCap,
];

/// Si ya se mostró el aviso de qué sale del teléfono para [provider].
String aiPrivacySeenKey(AiProvider provider) =>
    'ai_cloud_privacy_seen_${provider.storageKey}';

/// Un solo lugar para la IA (F32): quién escribe —Gemini, Gemma en el
/// teléfono, OpenAI o Claude—, con qué cuenta, qué modelo y cuánta cuota.
/// Cambiar algo acá vale para todo lo de la IA desde el próximo pedido; la
/// bóveda y el resto de la configuración no cambian.
class LanguageModelScreen extends ConsumerWidget {
  const LanguageModelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final provider = ref.watch(
      aiModelSettingsProvider.select((s) => s.provider),
    );
    final wires = ref.watch(cloudWiresProvider);
    final offered = [
      AiProvider.gemini,
      AiProvider.gemma,
      for (final p in [AiProvider.openAi, AiProvider.anthropic])
        if (wires.containsKey(p)) p,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatModelTooltip)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _StatusHeader(),
          const SizedBox(height: 28),
          _SectionTitle(l10n.lmWhoWrites, hint: l10n.lmWhoWritesHint),
          for (final p in offered)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProviderCard(provider: p, selected: p == provider),
            ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey(provider),
              child: provider.isCloud
                  ? _CloudSections(provider: provider)
                  : const _GemmaSection(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
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

/// Arriba de todo: quién escribe, con qué modelo, dónde corre y si puede
/// contestar ahora; y, en la nube, el menú de cuentas.
class _StatusHeader extends ConsumerWidget {
  const _StatusHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(aiModelSettingsProvider);
    final provider = settings.provider;
    final status = ref.watch(languageModelStatusProvider);

    final String model;
    if (provider.isCloud) {
      final models = ref.watch(cloudModelsProvider(provider));
      final id =
          settings.modelOf(provider) ??
          ref.watch(cloudModelCatalogProvider).recommended(provider);
      model = id == null
          ? l10n.lmModelRecommendedPlain
          : models.where((m) => m.id == id).firstOrNull?.displayName ?? id;
    } else {
      model = _gemmaTitle(l10n, ref.watch(chatModelOptionNotifierProvider));
    }

    return Container(
      key: const Key('lm-header'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(scheme.primaryContainer, scheme.tertiaryContainer, 0.7)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface.withValues(alpha: 0.7),
                ),
                child: Icon(provider.icon, color: scheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label(l10n),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model,
                      key: const Key('lm-header-model'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                icon: provider.isCloud
                    ? Icons.cloud_outlined
                    : Icons.smartphone_outlined,
                label: provider.isCloud ? l10n.lmBadgeCloud : l10n.lmBadgeLocal,
              ),
              _Badge(
                icon: provider.hasFreeTier
                    ? Icons.volunteer_activism_outlined
                    : Icons.credit_card_outlined,
                label: provider.hasFreeTier
                    ? l10n.lmBadgeFree
                    : l10n.lmBadgePaid,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _StatusLine(
              key: ValueKey(status.valueOrNull.runtimeType),
              status: status.valueOrNull,
            ),
          ),
          if (provider.isCloud) ...[
            const SizedBox(height: 14),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: AiAccountSwitcher(),
            ),
          ],
        ],
      ),
    );
  }
}

String _gemmaTitle(AppLocalizations l10n, ChatModelOption option) =>
    switch (option) {
      ChatModelOption.gemma4E4b => l10n.chatModelOptionGemma4Title,
      ChatModelOption.gemma3nE4b => l10n.chatModelOptionGemma3nTitle,
      ChatModelOption.gemma412b => l10n.chatModelOptionGemma412bTitle,
    };

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Si el modelo puede contestar, con un punto de color: verde si sí, del
/// color de la IA si falta algo, rojo si las claves no andan.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, super.key});

  final LanguageModelStatus? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = theme.extension<AppSemanticColors>()?.success;
    final (text, color) = switch (status) {
      null => (l10n.lmStatusChecking, scheme.outline),
      LanguageModelReady() => (l10n.lmStatusReady, ok ?? scheme.primary),
      LanguageModelNeedsDownload() => (
        l10n.lmStatusNeedsDownload,
        scheme.tertiary,
      ),
      LanguageModelNeedsAccount(:final provider) => (
        l10n.lmStatusNeedsAccount(provider.label(l10n)),
        scheme.tertiary,
      ),
      LanguageModelOutOfQuota(keysRejected: true) => (
        l10n.lmStatusKeysRejected,
        scheme.error,
      ),
      LanguageModelOutOfQuota(:final resetsAt?) => (
        l10n.lmStatusOutOfQuota(aiResetTime(context, resetsAt)),
        scheme.tertiary,
      ),
      LanguageModelOutOfQuota() => (
        l10n.lmStatusOutOfQuotaUnknown,
        scheme.tertiary,
      ),
      // La pantalla pregunta por la persona, no por la IA de fondo.
      LanguageModelBackgroundCapReached() => (
        l10n.lmStatusReady,
        ok ?? scheme.primary,
      ),
    };
    return Row(
      key: const Key('lm-status'),
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Una tarjeta por proveedor: se elige con un toque. La primera vez que se
/// elige uno en la nube, antes se explica qué sale del teléfono.
class _ProviderCard extends ConsumerWidget {
  const _ProviderCard({required this.provider, required this.selected});

  final AiProvider provider;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('lm-provider-${provider.storageKey}'),
          borderRadius: BorderRadius.circular(18),
          onTap: selected ? null : () => unawaited(_choose(context, ref)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                  ),
                  child: Icon(
                    provider.icon,
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.label(l10n),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _MiniTag(
                            provider.hasFreeTier
                                ? l10n.lmBadgeFree
                                : l10n.lmBadgePaid,
                            highlighted: provider.hasFreeTier,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        provider.detail(l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    key: ValueKey(selected),
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    if (!await _privacySeen(context, ref, provider)) return;
    await ref.read(aiModelSettingsProvider.notifier).chooseProvider(provider);
  }
}

/// Si la persona ya sabe qué sale del teléfono con [provider]: la primera vez
/// —al elegirlo o al cargar su primera clave, porque Gemini viene elegido de
/// fábrica— se le explica y tiene que aceptarlo. `false` si no aceptó.
Future<bool> _privacySeen(
  BuildContext context,
  WidgetRef ref,
  AiProvider provider,
) async {
  if (!provider.isCloud) return true;
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(aiPrivacySeenKey(provider)) ?? false) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _PrivacyDialog(provider: provider),
  );
  if (ok != true) return false;
  await prefs.setBool(aiPrivacySeenKey(provider), true);
  return true;
}

/// Carga una cuenta de [provider], con el aviso de privacidad antes si
/// todavía no se vio.
Future<void> _addAccount(
  BuildContext context,
  WidgetRef ref,
  AiProvider provider,
) async {
  if (!await _privacySeen(context, ref, provider)) return;
  if (!context.mounted) return;
  await showAiKeySheet(context, provider: provider);
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.label, {required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: highlighted
              ? scheme.onTertiaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Qué sale del teléfono con un proveedor en la nube, antes de elegirlo.
class _PrivacyDialog extends StatelessWidget {
  const _PrivacyDialog({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.lmPrivacyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lmPrivacyBody),
          const SizedBox(height: 12),
          Text(
            provider.hasFreeTier ? l10n.lmPrivacyFreeTier : l10n.lmPrivacyPaid,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('lm-privacy-continue'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.lmPrivacyContinue(provider.label(l10n))),
        ),
      ],
    );
  }
}

class _GemmaSection extends StatelessWidget {
  const _GemmaSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('lm-gemma-manage'),
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(l10n.lmGemmaManage),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(context.push(RoutePaths.chatModel)),
          ),
        ),
        const SizedBox(height: 12),
        _Note(icon: Icons.lock_outline, text: l10n.lmGemmaHint),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.extra});

  final IconData icon;
  final String text;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: theme.textTheme.bodySmall),
                if (extra != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    extra!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuentas, modelo, cuota y privacidad de un proveedor en la nube.
class _CloudSections extends StatelessWidget {
  const _CloudSections({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountsSection(provider: provider),
        const SizedBox(height: 28),
        _ModelSection(provider: provider),
        const SizedBox(height: 28),
        _SectionTitle(l10n.lmQuotaTitle),
        _QuotaSection(provider: provider),
        const SizedBox(height: 20),
        _Note(
          icon: Icons.shield_outlined,
          text: l10n.lmPrivacyBody,
          extra: provider.hasFreeTier
              ? l10n.lmPrivacyFreeTier
              : l10n.lmPrivacyPaid,
        ),
      ],
    );
  }
}

class _AccountsSection extends ConsumerWidget {
  const _AccountsSection({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final view = ref.watch(aiAccountsViewProvider);
    final auto = ref.watch(
      aiModelSettingsProvider.select((s) => s.autoSwitchAccounts),
    );
    final name = provider.label(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          l10n.lmAccountsTitle,
          hint: view.accounts.isEmpty
              ? null
              : (auto ? l10n.lmAccountsHint : l10n.lmAccountsHintManual),
        ),
        if (view.accounts.isEmpty)
          Container(
            key: const Key('lm-accounts-empty'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.key_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  provider.hasFreeTier
                      ? l10n.lmAccountsEmpty(name)
                      : l10n.lmAccountsEmptyPaid(name),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('lm-add-account'),
                      onPressed: () =>
                          unawaited(_addAccount(context, ref, provider)),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.lmAddAccount),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(openKeysPage(context, provider)),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l10n.lmGetKey),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final account in view.accounts) ...[
                  _AccountTile(
                    account: account,
                    active: account.id == view.activeId,
                    view: view,
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  key: const Key('lm-add-account'),
                  leading: Icon(Icons.add, color: theme.colorScheme.primary),
                  title: Text(
                    l10n.lmAddAccount,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  onTap: () => unawaited(_addAccount(context, ref, provider)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _AccountAction { test, rename, replaceKey, delete }

class _AccountTile extends ConsumerWidget {
  const _AccountTile({
    required this.account,
    required this.active,
    required this.view,
  });

  final AiAccount account;
  final bool active;
  final AiAccountsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final usage = view.usage[account.id]!;
    final condition = aiAccountConditionOf(usage, view.now);
    final spent = l10n.lmAccountUsageToday(
      usage.requests,
      aiTokens(context, usage.inputTokens + usage.outputTokens),
    );
    final until = usage.exhaustedUntil;
    final exhausted = until == null
        ? ''
        : l10n.lmAccountExhaustedUntil(
            aiResetTime(context, until, now: view.now),
          );
    final (status, color) = switch (condition) {
      AiAccountCondition.ready => (spent, scheme.onSurfaceVariant),
      AiAccountCondition.exhausted => ('$exhausted · $spent', scheme.tertiary),
      AiAccountCondition.rejected => (l10n.lmAccountKeyRejected, scheme.error),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: active ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: ListTile(
        key: Key('lm-account-${account.id}'),
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        leading: AiAccountAvatar(account: account, size: 40),
        title: Row(
          children: [
            Flexible(
              child: Text(
                account.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: active ? FontWeight.w600 : null),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              _MiniTag(l10n.lmAccountInUse, highlighted: true),
            ],
          ],
        ),
        subtitle: Text(
          status,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
        onTap: active
            ? null
            : () => unawaited(
                ref
                    .read(aiModelSettingsProvider.notifier)
                    .chooseAccount(account.provider, account.id),
              ),
        trailing: PopupMenuButton<_AccountAction>(
          key: Key('lm-account-menu-${account.id}'),
          tooltip: l10n.lmAccountMenu,
          onSelected: (action) => unawaited(_act(context, ref, action)),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _AccountAction.test,
              child: ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(l10n.lmAccountTest),
              ),
            ),
            PopupMenuItem(
              value: _AccountAction.rename,
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.commonRename),
              ),
            ),
            PopupMenuItem(
              value: _AccountAction.replaceKey,
              child: ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l10n.lmAccountReplaceKey),
              ),
            ),
            PopupMenuItem(
              value: _AccountAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _AccountAction action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(aiAccountActionsProvider);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );

    switch (action) {
      case _AccountAction.test:
        say(l10n.lmTesting);
        try {
          say(l10n.lmTestOk(await actions.test(account)));
        } on CloudModelException catch (error) {
          say(l10n.lmTestFailed(aiFailureReason(l10n, error.failure)));
        }
      case _AccountAction.rename:
        final label = await showDialog<String>(
          context: context,
          builder: (context) => _RenameDialog(initial: account.label),
        );
        if (label != null && label.trim().isNotEmpty) {
          await actions.rename(account, label.trim());
        }
      case _AccountAction.replaceKey:
        await showAiKeySheet(
          context,
          provider: account.provider,
          replacing: account,
        );
      case _AccountAction.delete:
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
                key: const Key('lm-account-delete-confirm'),
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
        key: const Key('lm-rename-field'),
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

/// El modelo, de la lista que da el proveedor; por defecto, el recomendado.
class _ModelSection extends ConsumerStatefulWidget {
  const _ModelSection({required this.provider});

  final AiProvider provider;

  @override
  ConsumerState<_ModelSection> createState() => _ModelSectionState();
}

class _ModelSectionState extends ConsumerState<_ModelSection> {
  var _refreshing = false;

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _refreshing = true);
    try {
      await ref.read(aiAccountActionsProvider).refreshModels(widget.provider);
    } on CloudModelException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            l10n.lmTestFailed(aiFailureReason(l10n, error.failure)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = widget.provider;
    final models = ref.watch(cloudModelsProvider(provider));
    final chosen = ref.watch(
      aiModelSettingsProvider.select((s) => s.modelOf(provider)),
    );
    final recommended = ref
        .watch(cloudModelCatalogProvider)
        .recommended(provider);
    final hasAccounts = ref.watch(aiAccountsViewProvider).accounts.isNotEmpty;
    String nameOf(String id) =>
        models.where((m) => m.id == id).firstOrNull?.displayName ?? id;

    final ids = {
      for (final m in models) m.id,
      // Lo elegido aunque la lista ya no lo traiga: que se vea qué se usa.
      ?chosen,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          l10n.lmModelTitle,
          hint: l10n.lmModelHint(provider.label(l10n)),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: const Key('lm-model'),
                initialValue: chosen,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.memory_outlined),
                ),
                items: [
                  DropdownMenuItem(
                    child: Text(
                      recommended == null
                          ? l10n.lmModelRecommendedPlain
                          : l10n.lmModelRecommended(nameOf(recommended)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final id in ids)
                    DropdownMenuItem(
                      value: id,
                      child: Text(nameOf(id), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => unawaited(
                  ref
                      .read(aiModelSettingsProvider.notifier)
                      .chooseModel(provider, value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('lm-model-refresh'),
              tooltip: l10n.lmModelRefresh,
              onPressed: _refreshing || !hasAccounts
                  ? null
                  : () => unawaited(_refresh()),
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuotaSection extends ConsumerWidget {
  const _QuotaSection({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(aiModelSettingsProvider);
    final view = ref.watch(aiAccountsViewProvider);
    final used = view.usage.values.fold<int>(
      0,
      (sum, u) => sum + u.backgroundRequests,
    );
    final cap = settings.backgroundDailyCap;
    final choices = {...kBackgroundCapChoices, cap}.toList()..sort();
    String capLabel(int value) => value >= AiModelSettings.maxDailyCap
        ? l10n.lmBackgroundCapUnlimited
        : l10n.lmBackgroundCapValue(value);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('lm-auto-switch'),
            secondary: const Icon(Icons.swap_horiz),
            title: Text(l10n.lmAutoSwitchTitle),
            subtitle: Text(l10n.lmAutoSwitchSubtitle),
            value: settings.autoSwitchAccounts,
            onChanged: (on) => unawaited(
              ref.read(aiModelSettingsProvider.notifier).setAutoSwitch(on: on),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.nights_stay_outlined),
            title: Text(l10n.lmBackgroundCapTitle),
            subtitle: Text(
              l10n.lmBackgroundCapSubtitle(
                used,
                cap >= AiModelSettings.maxDailyCap ? used : cap,
              ),
            ),
            trailing: DropdownButton<int>(
              key: const Key('lm-background-cap'),
              value: cap,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(16),
              items: [
                for (final value in choices)
                  DropdownMenuItem(value: value, child: Text(capLabel(value))),
              ],
              onChanged: (value) {
                if (value == null) return;
                unawaited(
                  ref
                      .read(aiModelSettingsProvider.notifier)
                      .setBackgroundDailyCap(value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
