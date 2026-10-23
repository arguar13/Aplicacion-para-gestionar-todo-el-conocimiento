import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto se calla un aviso igual a uno que se acaba de mostrar: la IA de
/// fondo y la persona pueden toparse con lo mismo a la vez, y dos avisos
/// iguales seguidos no dicen nada nuevo.
const kAiNoticeRepeatWindow = Duration(seconds: 20);

/// Muestra los avisos de la IA en la nube (F32, decisión B: «la mayor
/// retroalimentación posible») estén en la pantalla que estén: qué cuenta se
/// agotó, a cuál se pasó y cuándo vuelve; que no queda ninguna; que hay que
/// esperar el tope por minuto; que una clave no anda; por qué falló un
/// pedido. Va en el `builder` de `MaterialApp`, como `GlobalErrorListener`.
class AiNoticeListener extends ConsumerStatefulWidget {
  const AiNoticeListener({
    required this.child,
    required this.onOpenAccounts,
    this.now = DateTime.now,
    super.key,
  });

  final Widget child;

  /// Lleva a la pantalla del modelo, con las cuentas.
  final VoidCallback onOpenAccounts;

  final DateTime Function() now;

  @override
  ConsumerState<AiNoticeListener> createState() => _AiNoticeListenerState();
}

class _AiNoticeListenerState extends ConsumerState<AiNoticeListener> {
  StreamSubscription<AiNotice>? _notices;
  String? _lastKey;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    _notices = ref.read(aiNoticeBusProvider).notices.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    super.dispose();
  }

  /// Qué hace que dos avisos sean «el mismo».
  static String _keyOf(AiNotice notice) => switch (notice) {
    AccountSwitchedNotice(:final from, :final to) =>
      'switch:${from.id}:${to.id}',
    AllAccountsExhaustedNotice(:final provider) => 'all:${provider.name}',
    RateLimitWaitNotice(:final account) => 'rate:${account.id}',
    AccountKeyRejectedNotice(:final account) => 'key:${account.id}',
    BackgroundCapReachedNotice() => 'cap',
    AiRequestFailedNotice(:final failure) => 'failed:${failure.name}',
    AiRetryNotice() || AiRetryEndedNotice() => 'retry',
  };

  void _show(AiNotice notice) {
    if (!mounted) return;
    // Los reintentos no son un aviso de arriba de todo: los muestra, en el
    // lugar, quien está esperando la respuesta («Reintentando (2 de 4)…»).
    if (notice is AiRetryNotice || notice is AiRetryEndedNotice) return;
    final key = _keyOf(notice);
    final now = widget.now();
    final last = _lastAt;
    if (key == _lastKey &&
        last != null &&
        now.difference(last) < kAiNoticeRepeatWindow) {
      return;
    }
    _lastKey = key;
    _lastAt = now;

    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    String at(DateTime time) => aiResetTime(context, time, now: now);

    final (
      IconData icon,
      Color tone,
      String title,
      String body,
      Duration duration,
      bool accounts,
    ) = switch (notice) {
      AccountSwitchedNotice(:final from, :final to, :final reason) => (
        Icons.swap_horiz,
        scheme.primary,
        l10n.noticeSwitchedTitle(to.label),
        notice.fromResetsAt == null
            ? l10n.noticeSwitchedBodyNoTime(
                from.label,
                aiFailureReason(l10n, reason),
              )
            : l10n.noticeSwitchedBody(
                from.label,
                aiFailureReason(l10n, reason),
                at(notice.fromResetsAt!),
              ),
        const Duration(seconds: 7),
        true,
      ),
      AllAccountsExhaustedNotice(:final resetsAt) => (
        Icons.hourglass_bottom,
        scheme.tertiary,
        l10n.noticeAllExhaustedTitle,
        resetsAt == null
            ? l10n.noticeAllExhaustedBodyNoTime
            : l10n.noticeAllExhaustedBody(at(resetsAt)),
        const Duration(seconds: 10),
        true,
      ),
      RateLimitWaitNotice(:final wait) => (
        Icons.timer_outlined,
        scheme.secondary,
        l10n.noticeRateWaitTitle,
        l10n.noticeRateWaitBody(wait.inSeconds.clamp(1, 999)),
        wait < const Duration(seconds: 4) ? const Duration(seconds: 4) : wait,
        false,
      ),
      AccountKeyRejectedNotice(:final account, :final reason) => (
        Icons.key_off_outlined,
        scheme.error,
        l10n.noticeKeyRejectedTitle(account.label),
        capitalized(aiFailureReason(l10n, reason)),
        const Duration(seconds: 8),
        true,
      ),
      BackgroundCapReachedNotice(:final cap, :final resetsAt) => (
        Icons.nights_stay_outlined,
        scheme.secondary,
        l10n.noticeBackgroundCapTitle,
        l10n.noticeBackgroundCapBody(
          cap,
          resetsAt == null ? '—' : at(resetsAt),
        ),
        const Duration(seconds: 7),
        false,
      ),
      AiRequestFailedNotice(:final failure) => (
        Icons.cloud_off_outlined,
        scheme.error,
        l10n.noticeRequestFailedTitle,
        aiFailureHelp(l10n, failure),
        const Duration(seconds: 9),
        false,
      ),
      // Ya se descartaron arriba: no llegan a mostrarse.
      AiRetryNotice() || AiRetryEndedNotice() => throw StateError(
        'Un reintento se muestra en el lugar, no arriba de todo.',
      ),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: Key('ai-notice-$key'),
          behavior: SnackBarBehavior.floating,
          duration: duration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          content: _NoticeContent(
            icon: icon,
            tone: tone,
            title: title,
            body: body,
          ),
          action: accounts
              ? SnackBarAction(
                  label: l10n.noticeActionAccounts,
                  onPressed: widget.onOpenAccounts,
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NoticeContent extends StatelessWidget {
  const _NoticeContent({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // El aviso se pinta sobre `inverseSurface`: los colores van a su
    // contraste, no al de la pantalla.
    final onBar = theme.colorScheme.onInverseSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(tone, theme.colorScheme.inverseSurface, 0.55),
          ),
          child: Icon(icon, size: 20, color: onBar),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(color: onBar),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onBar.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
