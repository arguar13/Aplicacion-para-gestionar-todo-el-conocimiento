import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/vault/data/datasources/vault_local_data_source.dart';
import 'package:sinapsis/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:sinapsis/features/vault/data/services/method_channel_device_boot.dart';
import 'package:sinapsis/features/vault/data/services/pbkdf2_pin_hasher.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';
import 'package:sinapsis/features/vault/domain/services/device_boot.dart';
import 'package:sinapsis/features/vault/domain/services/pin_hasher.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_exists_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_open_this_boot_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/create_vault_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/lock_vault_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/unlock_vault_usecase.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_session_controller.dart';

/// Cascada de inyección del feature: DataSource -> Repository -> UseCase.
/// La capa de presentación solo depende de los casos de uso, nunca de
/// `vaultRepositoryProvider`.
final vaultLocalDataSourceProvider = Provider<VaultLocalDataSource>((ref) {
  return SecureVaultLocalDataSource();
});

final pinHasherProvider = Provider<PinHasher>((ref) {
  return Pbkdf2PinHasher();
});

/// El encendido del dispositivo, para pedir la clave una vez por encendido.
/// Solo Android lo da; en el resto se pide cada vez que se abre la app.
final deviceBootProvider = Provider<DeviceBoot>(
  (ref) => kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? unknownDeviceBoot
      : androidDeviceBoot,
);

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  return VaultRepositoryImpl(
    localDataSource: ref.watch(vaultLocalDataSourceProvider),
    pinHasher: ref.watch(pinHasherProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    deviceBoot: ref.watch(deviceBootProvider),
  );
});

final checkVaultExistsUseCaseProvider = Provider<CheckVaultExistsUseCase>((
  ref,
) {
  return CheckVaultExistsUseCase(ref.watch(vaultRepositoryProvider));
});

final createVaultUseCaseProvider = Provider<CreateVaultUseCase>((ref) {
  return CreateVaultUseCase(ref.watch(vaultRepositoryProvider));
});

final unlockVaultUseCaseProvider = Provider<UnlockVaultUseCase>((ref) {
  return UnlockVaultUseCase(ref.watch(vaultRepositoryProvider));
});

final checkVaultOpenThisBootUseCaseProvider =
    Provider<CheckVaultOpenThisBootUseCase>((ref) {
      return CheckVaultOpenThisBootUseCase(ref.watch(vaultRepositoryProvider));
    });

final lockVaultUseCaseProvider = Provider<LockVaultUseCase>((ref) {
  return LockVaultUseCase(ref.watch(vaultRepositoryProvider));
});

/// Deliberadamente NO autoDispose: el estado de la bóveda tiene que
/// sobrevivir mientras la app esté abierta, sin importar qué pantalla esté
/// montada. Si se descartara al desmontarse la última pantalla que lo
/// observa, la bóveda se "cerraría" sola al navegar.
final vaultSessionControllerProvider =
    StateNotifierProvider<VaultSessionController, VaultSession>((ref) {
      return VaultSessionController(
        checkVaultExists: ref.watch(checkVaultExistsUseCaseProvider),
        checkOpenThisBoot: ref.watch(checkVaultOpenThisBootUseCaseProvider),
        lockVault: ref.watch(lockVaultUseCaseProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });
