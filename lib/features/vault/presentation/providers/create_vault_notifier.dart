import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/vault/domain/usecases/create_vault_usecase.dart';
import 'package:sinapsis/features/vault/presentation/providers/create_vault_state.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_session_controller.dart';

/// Orquesta la creación de la bóveda: llama al caso de uso y traduce el
/// resultado a [CreateVaultState].
///
/// Una bóveda recién creada queda abierta, sin pedir la clave otra vez:
/// acaba de escribirla dos veces, volver a pedirla sería puro trámite.
class CreateVaultNotifier extends StateNotifier<CreateVaultState> {
  CreateVaultNotifier({
    required CreateVaultUseCase createVault,
    required VaultSessionController sessionController,
    required AppLogger logger,
  }) : _createVault = createVault,
       _sessionController = sessionController,
       _logger = logger,
       super(const CreateVaultState.idle());

  final CreateVaultUseCase _createVault;
  final VaultSessionController _sessionController;
  final AppLogger _logger;

  Future<void> create({
    required String pin,
    required String confirmation,
  }) async {
    state = const CreateVaultState.creating();

    final result = await _createVault(
      CreateVaultParams(pin: pin, confirmation: confirmation),
    );

    result.match(
      (failure) {
        // El mensaje del Failure se registra pero no se muestra: la
        // pantalla lo traduce por tipo (ver FailureLocalization).
        _logger.error('No se pudo crear la bóveda.', failure);
        state = CreateVaultState.failed(failure);
      },
      (_) {
        state = const CreateVaultState.idle();
        _sessionController.markUnlocked();
      },
    );
  }
}

final createVaultNotifierProvider =
    StateNotifierProvider.autoDispose<CreateVaultNotifier, CreateVaultState>((
      ref,
    ) {
      return CreateVaultNotifier(
        createVault: ref.watch(createVaultUseCaseProvider),
        sessionController: ref.watch(vaultSessionControllerProvider.notifier),
        logger: ref.watch(appLoggerProvider),
      );
    });
