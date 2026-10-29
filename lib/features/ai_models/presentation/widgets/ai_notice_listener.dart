import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
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
///
/// Cada aviso lleva su ✕ y se cierra en el acto (F43, M1). El de la espera
/// del tope por minuto cuenta hacia atrás en vivo y se va solo cuando la IA
/// sigue.
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

  /// Los segundos que faltan para que la IA siga sola, en el aviso del tope
  /// por minuto: bajan de a uno, en vivo.
  final _rateSeconds = ValueNotifier<int>(0);
  Timer? _rateTicker;

  /// El aviso de la espera mientras está abierto; `null` si no hay ninguno.
  /// Siempre es el de ahora: cada aviso de la IA cierra el anterior antes de
  /// abrirse, y lo que muestre otra pantalla después espera detrás de él.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _rateNotice;

  @override
  void initState() {
    super.initState();
    _notices = ref.read(aiNoticeBusProvider).notices.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    _rateTicker?.cancel();
    _rateSeconds.dispose();
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
    // Otra espera con el aviso de la espera abierto: no se abre otro, se
    // corrige la cuenta del que está.
    if (notice is RateLimitWaitNotice && _rateNotice != null) {
      _countDown(notice);
      return;
    }
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
      Widget body,
      Duration duration,
      bool accounts,
    ) = switch (notice) {
      AccountSwitchedNotice(:final from, :final to, :final reason) => (
        Icons.swap_horiz,
        scheme.primary,
        l10n.noticeSwitchedTitle(to.label),
        _NoticeBody(
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
        ),
        const Duration(seconds: 7),
        true,
      ),
      AllAccountsExhaustedNotice(:final resetsAt) => (
        Icons.hourglass_bottom,
        scheme.tertiary,
        l10n.noticeAllExhaustedTitle,
        _NoticeBody(
          resetsAt == null
              ? l10n.noticeAllExhaustedBodyNoTime
              : l10n.noticeAllExhaustedBody(at(resetsAt)),
        ),
        const Duration(seconds: 10),
        true,
      ),
      // Se va cuando la IA sigue: lo cierra la cuenta atrás (`_countDown`),
      // no un tiempo fijo.
      RateLimitWaitNotice() => (
        Icons.timer_outlined,
        scheme.secondary,
        l10n.noticeRateWaitTitle,
        ValueListenableBuilder<int>(
          valueListenable: _rateSeconds,
          builder: (context, seconds, _) =>
              _NoticeBody(l10n.noticeRateWaitBody(seconds.clamp(1, 999))),
        ),
        kSnackBarDefaultDuration,
        false,
      ),
      AccountKeyRejectedNotice(:final account, :final reason) => (
        Icons.key_off_outlined,
        scheme.error,
        l10n.noticeKeyRejectedTitle(account.label),
        _NoticeBody(capitalized(aiFailureReason(l10n, reason))),
        const Duration(seconds: 8),
        true,
      ),
      BackgroundCapReachedNotice(:final cap, :final resetsAt) => (
        Icons.nights_stay_outlined,
        scheme.secondary,
        l10n.noticeBackgroundCapTitle,
        _NoticeBody(
          l10n.noticeBackgroundCapBody(
            cap,
            resetsAt == null ? '—' : at(resetsAt),
          ),
        ),
        const Duration(seconds: 7),
        false,
      ),
      AiRequestFailedNotice(:final failure) => (
        Icons.cloud_off_outlined,
        scheme.error,
        l10n.noticeRequestFailedTitle,
        _NoticeBody(aiFailureHelp(l10n, failure)),
        const Duration(seconds: 9),
        false,
      ),
      // Ya se descartaron arriba: no llegan a mostrarse.
      AiRetryNotice() || AiRetryEndedNotice() => throw StateError(
        'Un reintento se muestra en el lugar, no arriba de todo.',
      ),
    };

    final rate = notice is RateLimitWaitNotice;
    final controller = (ScaffoldMessenger.of(context)..hideCurrentSnackBar())
        .showSnackBar(
          AppSnackBar(
            key: Key('ai-notice-$key'),
            behavior: SnackBarBehavior.floating,
            duration: duration,
            // El de la espera se queda hasta que la IA sigue; el resto, lo
            // que dice cada uno, también el que tiene el botón de las
            // cuentas: con botón, un aviso se quedaría para siempre.
            persist: rate,
            // Todos con su ✕ (F43, M1), también los cortos: un aviso de la
            // IA puede tapar lo que la persona está mirando, y no tiene por
            // qué esperar a que se vaya.
            showCloseIcon: true,
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
    if (notice is RateLimitWaitNotice) {
      _rateNotice = controller;
      _countDown(notice);
      unawaited(
        controller.closed.then((reason) {
          if (_rateNotice != controller) return;
          _rateNotice = null;
          _rateTicker?.cancel();
          // Se fue porque la IA siguió: si vuelve a tener que esperar, es
          // algo nuevo y se avisa. Cerrado con su ✕, en cambio, se calla
          // como cualquier aviso repetido.
          if (reason == SnackBarClosedReason.timeout && _lastKey == key) {
            _lastKey = null;
          }
        }),
      );
    }
  }

  /// Pone la cuenta atrás del aviso de la espera en lo que falta para que la
  /// IA siga sola, y la hace bajar de a un segundo. En cero la IA ya siguió:
  /// el aviso se va.
  void _countDown(RateLimitWaitNotice notice) {
    final left = notice.at.add(notice.wait).difference(widget.now());
    // Hacia arriba: «sigue en 1 segundo» mientras falte algo.
    _rateSeconds.value = (left.inMilliseconds / 1000).ceil().clamp(1, 999);
    _rateTicker?.cancel();
    _rateTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rateSeconds.value > 1) {
        _rateSeconds.value--;
        return;
      }
      timer.cancel();
      _rateSeconds.value = 0;
      _closeRateNotice();
    });
  }

  /// Cierra el aviso de la espera, si sigue abierto.
  void _closeRateNotice() {
    if (_rateNotice == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
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
  final Widget body;

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
              body,
            ],
          ),
        ),
      ],
    );
  }
}

/// El texto de un aviso, debajo de su título.
class _NoticeBody extends StatelessWidget {
  const _NoticeBody(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onInverseSurface.withValues(alpha: 0.85),
      ),
    );
  }
}
