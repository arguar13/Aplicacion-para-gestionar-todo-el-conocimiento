import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que le falta al modelo elegido, dicho para quien iba a pedir algo
/// (F32). Con Gemma sin bajar, [downloadMessage] —lo de cada pantalla, que
/// dice para qué hace falta— si lo hay.
String languageModelMissingMessage(
  BuildContext context,
  LanguageModelStatus status, {
  String? downloadMessage,
}) {
  final l10n = AppLocalizations.of(context)!;
  return switch (status) {
    LanguageModelReady() || LanguageModelBackgroundCapReached() => '',
    LanguageModelNeedsDownload() => downloadMessage ?? l10n.lmMissingDownload,
    LanguageModelNeedsAccount(:final provider) =>
      provider.hasFreeTier
          ? l10n.lmMissingAccount(provider.label(l10n))
          : l10n.lmMissingAccountPaid(provider.label(l10n)),
    LanguageModelOutOfQuota(keysRejected: true) => l10n.lmMissingKeys,
    LanguageModelOutOfQuota(:final resetsAt?) => l10n.lmMissingQuota(
      aiResetTime(context, resetsAt),
    ),
    LanguageModelOutOfQuota() => l10n.lmMissingQuotaNoTime,
  };
}

/// El botón que resuelve lo que falta: bajar Gemma, cargar una clave o ir a
/// las cuentas.
({String label, String route}) languageModelMissingAction(
  AppLocalizations l10n,
  LanguageModelStatus status, {
  String? downloadLabel,
}) => switch (status) {
  LanguageModelNeedsDownload() => (
    label: downloadLabel ?? l10n.lmActionDownload,
    route: RoutePaths.chatModel,
  ),
  LanguageModelNeedsAccount() => (
    label: l10n.lmActionAddKey,
    route: RoutePaths.languageModel,
  ),
  _ => (label: l10n.noticeActionAccounts, route: RoutePaths.languageModel),
};

/// Muestra lo que le falta al modelo, con el botón que lo resuelve.
void showLanguageModelMissing(
  BuildContext context,
  LanguageModelStatus status, {
  String? downloadMessage,
  String? downloadLabel,
}) {
  final l10n = AppLocalizations.of(context)!;
  final action = languageModelMissingAction(
    l10n,
    status,
    downloadLabel: downloadLabel,
  );
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Text(
          languageModelMissingMessage(
            context,
            status,
            downloadMessage: downloadMessage,
          ),
        ),
        action: SnackBarAction(
          label: action.label,
          onPressed: () => unawaited(context.push(action.route)),
        ),
      ),
    );
}

/// Si el modelo elegido puede contestar ahora; si no, lo dice
/// ([showLanguageModelMissing]) y devuelve `false`. Lo usan los botones que
/// le piden algo a la IA, antes de pedirlo.
Future<bool> ensureLanguageModelReady(
  BuildContext context,
  WidgetRef ref, {
  String? downloadMessage,
  String? downloadLabel,
}) async {
  final status = await ref.read(languageModelStatusCheckProvider)();
  if (status.isReady) return true;
  if (context.mounted) {
    showLanguageModelMissing(
      context,
      status,
      downloadMessage: downloadMessage,
      downloadLabel: downloadLabel,
    );
  }
  return false;
}

/// Lo que le falta al modelo, dentro de una hoja (las tarjetas con IA, llenar
/// un cuaderno): el mensaje y el botón que lo resuelve, que cierra la hoja
/// antes de ir.
class LanguageModelMissingBanner extends StatelessWidget {
  const LanguageModelMissingBanner({
    required this.status,
    this.downloadMessage,
    this.downloadLabel,
    super.key,
  });

  final LanguageModelStatus status;
  final String? downloadMessage;
  final String? downloadLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final action = languageModelMissingAction(
      l10n,
      status,
      downloadLabel: downloadLabel,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            status is LanguageModelNeedsDownload
                ? Icons.download_for_offline_outlined
                : Icons.key_outlined,
            color: scheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              languageModelMissingMessage(
                context,
                status,
                downloadMessage: downloadMessage,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              unawaited(router.push(action.route));
            },
            child: Text(action.label),
          ),
        ],
      ),
    );
  }
}
