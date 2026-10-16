import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo está una cuenta ahora, para mostrarlo (F32).
enum AiAccountCondition { ready, exhausted, rejected }

/// La condición de [usage] en [now].
AiAccountCondition aiAccountConditionOf(AccountUsage usage, DateTime now) {
  if (!usage.isExhaustedAt(now)) return AiAccountCondition.ready;
  return usage.lastFailure == CloudModelFailure.invalidKey ||
          usage.lastFailure == CloudModelFailure.forbidden
      ? AiAccountCondition.rejected
      : AiAccountCondition.exhausted;
}

/// Las cuentas del proveedor elegido, cuál está en uso y lo gastado de cada
/// una, redibujado cuando algo cambia.
typedef AiAccountsView = ({
  List<AiAccount> accounts,
  String? activeId,
  Map<String, AccountUsage> usage,
  DateTime now,
});

final aiAccountsViewProvider = Provider.autoDispose<AiAccountsView>((ref) {
  ref.watch(aiUsageChangesProvider);
  final settings = ref.watch(aiModelSettingsProvider);
  final provider = settings.provider;
  final all = ref.watch(aiAccountsProvider).valueOrNull ?? const [];
  final accounts = [
    for (final a in all)
      if (a.provider == provider) a,
  ];
  final now = ref.watch(clockProvider)();
  final ledger = ref.watch(aiUsageLedgerProvider);
  final chosen = settings.activeAccountOf(provider);
  return (
    accounts: accounts,
    // Sin elegida, la que usa el motor: la primera.
    activeId: accounts.any((a) => a.id == chosen)
        ? chosen
        : accounts.firstOrNull?.id,
    usage: {for (final a in accounts) a.id: ledger.usageOf(a.id, now: now)},
    now: now,
  );
});

/// Un círculo con la inicial de la cuenta, de un color que la distingue de
/// las otras —siempre el mismo para la misma cuenta—.
class AiAccountAvatar extends StatelessWidget {
  const AiAccountAvatar({required this.account, this.size = 32, super.key});

  final AiAccount account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.errorContainer, scheme.onErrorContainer),
    ];
    final hash = account.id.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    final (background, foreground) = palette[hash.abs() % palette.length];
    final label = account.label.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}

/// El menú desplegable de las cuentas (F32): con un toque se cambia la que
/// escribe, y nada más cambia. Va arriba de la pantalla del modelo y en la
/// barra del chat. Sin cuentas del proveedor elegido —o con Gemma— no se
/// dibuja.
class AiAccountSwitcher extends ConsumerWidget {
  const AiAccountSwitcher({this.dense = false, super.key});

  /// En una barra: solo el círculo de la cuenta.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final provider = ref.watch(
      aiModelSettingsProvider.select((s) => s.provider),
    );
    final view = ref.watch(aiAccountsViewProvider);
    if (!provider.isCloud || view.accounts.isEmpty) {
      return const SizedBox.shrink();
    }
    final active = view.accounts.firstWhere(
      (a) => a.id == view.activeId,
      orElse: () => view.accounts.first,
    );
    final theme = Theme.of(context);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        for (final account in view.accounts)
          _AccountMenuItem(
            account: account,
            active: account.id == active.id,
            usage: view.usage[account.id]!,
            now: view.now,
            onChoose: () => unawaited(_choose(context, ref, account)),
          ),
        const Divider(height: 8),
        MenuItemButton(
          key: const Key('ai-switcher-manage'),
          leadingIcon: const Icon(Icons.manage_accounts_outlined),
          onPressed: () => unawaited(context.push(RoutePaths.languageModel)),
          child: Text(l10n.lmManageAccounts),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (dense) {
          return IconButton(
            key: const Key('ai-account-switcher'),
            tooltip: l10n.lmSwitchAccount,
            onPressed: toggle,
            icon: AiAccountAvatar(account: active, size: 28),
          );
        }
        return Tooltip(
          message: l10n.lmSwitchAccount,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('ai-account-switcher'),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AiAccountAvatar(account: active, size: 26),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        active.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    AiAccount account,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(aiModelSettingsProvider.notifier)
        .chooseAccount(account.provider, account.id);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(l10n.lmNowUsing(account.label)),
        ),
      );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    required this.account,
    required this.active,
    required this.usage,
    required this.now,
    required this.onChoose,
  });

  final AiAccount account;
  final bool active;
  final AccountUsage usage;
  final DateTime now;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final condition = aiAccountConditionOf(usage, now);
    final status = switch (condition) {
      AiAccountCondition.ready when active => l10n.lmAccountInUse,
      AiAccountCondition.ready => l10n.lmAccountUsageToday(
        usage.requests,
        aiTokens(context, usage.inputTokens + usage.outputTokens),
      ),
      AiAccountCondition.exhausted => l10n.lmAccountExhaustedUntil(
        aiResetTime(context, usage.exhaustedUntil!, now: now),
      ),
      AiAccountCondition.rejected => l10n.lmAccountKeyRejected,
    };
    final statusColor = switch (condition) {
      AiAccountCondition.ready when active => theme.colorScheme.primary,
      AiAccountCondition.ready => theme.colorScheme.onSurfaceVariant,
      AiAccountCondition.exhausted => theme.colorScheme.tertiary,
      AiAccountCondition.rejected => theme.colorScheme.error,
    };

    return MenuItemButton(
      key: Key('ai-switcher-${account.id}'),
      onPressed: onChoose,
      leadingIcon: AiAccountAvatar(account: account, size: 30),
      trailingIcon: active
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              account.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: active ? FontWeight.w600 : null,
              ),
            ),
            Text(
              status,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
            ),
          ],
        ),
      ),
    );
  }
}
