import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';
import 'package:sinapsis/features/vault/domain/usecases/unlock_vault_usecase.dart';
import 'package:sinapsis/features/vault/presentation/providers/unlock_vault_state.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_session_controller.dart';

/// Orquesta el desbloqueo: llama al caso de uso y traduce el
/// [UnlockResult] a [UnlockVaultState].
class UnlockVaultNotifier extends StateNotifier<UnlockVaultState> {
  UnlockVaultNotifier({
    required UnlockVaultUseCase unlockVault,
    required VaultSessionController sessionController,
    required AppLogger logger,
  }) : _unlockVault = unlockVault,
       _sessionController = sessionController,
       _logger = logger,
       super(const UnlockVaultState.idle());

  final UnlockVaultUseCase _unlockVault;
  final VaultSessionController _sessionController;
  final AppLogger _logger;

  Future<void> unlock(String pin) async {
    state = const UnlockVaultState.verifying();

    final result = await _unlockVault(UnlockVaultParams(pin: pin));

    result.match(
      (failure) {
        _logger.error('No se pudo comprobar la clave de la bóveda.', failure);
        state = UnlockVaultState.failed(failure);
      },
      (outcome) {
        switch (outcome) {
          case UnlockGranted():
            state = const UnlockVaultState.idle();
            _sessionController.markUnlocked();
          case UnlockRejected(:final remainingAttempts):
            // A propósito no se registra nada del intento fallido: ni la
            // clave, ni su longitud, ni un fragmento. Un registro de
            // "intento fallido con 4 caracteres" ya es información sobre
            // la clave real.
            _logger.warning('Clave incorrecta al abrir la bóveda.');
            state = UnlockVaultState.rejected(
              remainingAttempts: remainingAttempts,
            );
          case UnlockLockedOut(:final until):
            _logger.warning('Bóveda bloqueada temporalmente hasta $until.');
            state = UnlockVaultState.lockedOut(until: until);
        }
      },
    );
  }

  /// Vuelve al estado neutro cuando el usuario empieza a escribir de nuevo,
  /// para que el mensaje del intento anterior no quede colgado mientras
  /// tipea.
  void clearFeedback() {
    if (state is UnlockVaultRejected || state is UnlockVaultFailed) {
      state = const UnlockVaultState.idle();
    }
  }
}

final unlockVaultNotifierProvider =
    StateNotifierProvider.autoDispose<UnlockVaultNotifier, UnlockVaultState>((
      ref,
    ) {
      return UnlockVaultNotifier(
        unlockVault: ref.watch(unlockVaultUseCaseProvider),
        sessionController: ref.watch(vaultSessionControllerProvider.notifier),
        logger: ref.watch(appLoggerProvider),
      );
    });
