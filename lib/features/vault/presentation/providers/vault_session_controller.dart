import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_exists_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_open_this_boot_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/lock_vault_usecase.dart';

/// Única fuente de verdad de en qué estado está la bóveda, para toda la
/// app. El router la observa (vía `refreshListenable`) y decide qué puede
/// verse; las pantallas de crear y desbloquear le avisan cuando lo logran.
///
/// Ninguna pantalla navega por su cuenta: cambian este estado y el router
/// reacciona. Es el mismo patrón que tenía la app con sesiones remotas, y
/// se conserva porque funcionaba bien — lo que cambió es qué significa
/// cada estado.
class VaultSessionController extends StateNotifier<VaultSession> {
  VaultSessionController({
    required CheckVaultExistsUseCase checkVaultExists,
    required CheckVaultOpenThisBootUseCase checkOpenThisBoot,
    required LockVaultUseCase lockVault,
    required AppLogger logger,
  }) : _checkVaultExists = checkVaultExists,
       _checkOpenThisBoot = checkOpenThisBoot,
       _lockVault = lockVault,
       _logger = logger,
       super(const VaultSession.unknown());

  final CheckVaultExistsUseCase _checkVaultExists;
  final CheckVaultOpenThisBootUseCase _checkOpenThisBoot;
  final LockVaultUseCase _lockVault;
  final AppLogger _logger;

  /// Se llama una sola vez al arrancar, desde el splash. Averigua si este
  /// dispositivo ya tiene bóveda para saber si hay que crearla o abrirla, y
  /// si quedó abierta en este encendido del dispositivo: entonces se entra
  /// sin pedir la clave, que se pide una vez por encendido —al apagar o
  /// reiniciar el teléfono— o después de "Bloquear bóveda".
  Future<void> resolveInitialState() async {
    if (state is! VaultUnknown) return;

    final result = await _checkVaultExists(const NoParams());

    final resolved = result.match(
      (failure) {
        // Si no se puede leer el almacenamiento, se asume que la bóveda
        // existe y está cerrada. Es el lado seguro del error: dar por
        // sentado lo contrario llevaría a alguien a la pantalla de crear
        // una bóveda nueva, sugiriendo que su conocimiento guardado ya no
        // está. El repositorio igual se niega a sobrescribir una bóveda
        // existente, pero el susto sería gratis.
        _logger.error(
          'No se pudo determinar si existe una bóveda; se asume que sí.',
          failure,
        );
        return const VaultSession.locked();
      },
      (exists) =>
          exists ? const VaultSession.locked() : const VaultSession.absent(),
    );
    if (resolved is! VaultLocked) {
      state = resolved;
      return;
    }

    final open = await _checkOpenThisBoot(const NoParams());
    state = open.match(
      (failure) {
        // Sin saber si quedó abierta, se pide la clave: el lado seguro.
        _logger.error(
          'No se pudo saber si la bóveda quedó abierta; se pide la clave.',
          failure,
        );
        return const VaultSession.locked();
      },
      (isOpen) =>
          isOpen ? const VaultSession.unlocked() : const VaultSession.locked(),
    );
  }

  /// La bóveda quedó abierta: recién creada o recién desbloqueada.
  void markUnlocked() => state = const VaultSession.unlocked();

  /// "Bloquear bóveda": la cierra ya, y la próxima vez que se abra la app
  /// pide la clave aunque el teléfono no se haya reiniciado. No borra nada:
  /// el credencial sigue donde estaba y el mismo PIN vuelve a abrirla.
  ///
  /// Se cierra en pantalla aunque no se pueda borrar la sesión guardada:
  /// quien toca "Bloquear" la quiere cerrada ahora. Ese fallo se registra.
  Future<void> lock() async {
    state = const VaultSession.locked();
    final result = await _lockVault(const NoParams());
    result.match(
      (failure) => _logger.error(
        'No se pudo cerrar la sesión guardada: la próxima vez podría '
        'entrar sin la clave.',
        failure,
      ),
      (_) {},
    );
  }
}
