import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/vault/presentation/providers/unlock_vault_notifier.dart';
import 'package:sinapsis/features/vault/presentation/providers/unlock_vault_state.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Pantalla de desbloqueo: la que se ve en cada arranque una vez creada la
/// bóveda.
class UnlockVaultScreen extends ConsumerStatefulWidget {
  const UnlockVaultScreen({super.key});

  @override
  ConsumerState<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends ConsumerState<UnlockVaultScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    // Sin validación de longitud antes de mandar: al desbloquear, una clave
    // corta es simplemente una clave equivocada. Rechazarla en la pantalla
    // le contaría a quien lo intenta algo sobre la clave guardada, y además
    // le dejaría probar infinitas claves cortas sin gastar intentos.
    if (_pinController.text.isEmpty) return;
    ref.read(unlockVaultNotifierProvider.notifier).unlock(_pinController.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(unlockVaultNotifierProvider);

    final isVerifying = state is UnlockVaultVerifying;
    final isLockedOut = state is UnlockVaultLockedOut;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    isLockedOut ? Icons.lock_clock : Icons.lock_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.vaultUnlockTitle,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  CustomTextField(
                    label: l10n.vaultPasscodeLabel,
                    controller: _pinController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    // Sin validador: el único juez de si la clave sirve es
                    // la bóveda.
                    validator: (_) => null,
                    onChanged: (_) => ref
                        .read(unlockVaultNotifierProvider.notifier)
                        .clearFeedback(),
                    onSubmitted: isLockedOut ? null : (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  _UnlockFeedback(state: state),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: l10n.vaultUnlockAction,
                    isLoading: isVerifying,
                    // Durante la espera el botón queda inerte: que se pueda
                    // seguir apretando para recibir siempre el mismo
                    // rechazo es una forma barata de frustración.
                    onPressed: isLockedOut ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El mensaje bajo el campo: qué pasó con el último intento.
class _UnlockFeedback extends StatelessWidget {
  const _UnlockFeedback({required this.state});

  final UnlockVaultState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final message = switch (state) {
      UnlockVaultIdle() || UnlockVaultVerifying() => null,
      UnlockVaultRejected(:final remainingAttempts) =>
        l10n.vaultUnlockWrongPasscode(remainingAttempts),
      UnlockVaultFailed(:final failure) => failure.localizedMessage(l10n),
      UnlockVaultLockedOut() => null,
    };

    if (state case UnlockVaultLockedOut(:final until)) {
      return _LockoutCountdown(until: until);
    }

    if (message == null) {
      // Reserva el alto del mensaje aunque no haya ninguno, para que el
      // formulario no salte hacia arriba y abajo entre intentos.
      return const SizedBox(height: 20);
    }

    return SizedBox(
      height: 20,
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Cuenta regresiva viva durante el bloqueo temporal.
///
/// Se actualiza cada segundo en vez de mostrar un texto fijo: un
/// "esperá 2 minutos" congelado obliga a adivinar cuánto pasó y a probar
/// suerte apretando el botón. Ver el número bajar dice exactamente cuándo
/// vale la pena volver.
class _LockoutCountdown extends ConsumerStatefulWidget {
  const _LockoutCountdown({required this.until});

  final DateTime until;

  @override
  ConsumerState<_LockoutCountdown> createState() => _LockoutCountdownState();
}

class _LockoutCountdownState extends ConsumerState<_LockoutCountdown> {
  Timer? _ticker;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _remainingFrom(DateTime.now());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remainingFrom(DateTime now) {
    final left = widget.until.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    if (!mounted) return;

    final left = _remainingFrom(DateTime.now());
    setState(() => _remaining = left);

    if (left == Duration.zero) {
      _ticker?.cancel();
      // Se terminó la espera: se limpia el estado para que el botón vuelva
      // a habilitarse sin que el usuario tenga que tocar nada.
      ref.read(unlockVaultNotifierProvider.notifier).clearFeedback();
    }
  }

  /// Elige la unidad más grande que todavía tenga sentido y redondea hacia
  /// arriba, para no decir "0 segundos" en el último tramo.
  String _format(AppLocalizations l10n) {
    if (_remaining.inMinutes >= 60) {
      return l10n.vaultLockedHours((_remaining.inMinutes / 60).ceil());
    }
    if (_remaining.inSeconds >= 60) {
      return l10n.vaultLockedMinutes((_remaining.inSeconds / 60).ceil());
    }
    return l10n.vaultLockedSeconds(_remaining.inSeconds.clamp(1, 59));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SizedBox(
      height: 20,
      child: Text(
        l10n.vaultUnlockLockedOut(_format(l10n)),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
