import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_exists_usecase.dart';

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
    required AppLogger logger,
  }) : _checkVaultExists = checkVaultExists,
       _logger = logger,
       super(const VaultSession.unknown());

  final CheckVaultExistsUseCase _checkVaultExists;
  final AppLogger _logger;

  /// Se llama una sola vez al arrancar, desde el splash. Averigua si este
  /// dispositivo ya tiene bóveda para saber si hay que crearla o abrirla.
  Future<void> resolveInitialState() async {
    if (state is! VaultUnknown) return;

    final result = await _checkVaultExists(const NoParams());

    state = result.match(
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
  }

  /// La bóveda quedó abierta: recién creada o recién desbloqueada.
  void markUnlocked() => state = const VaultSession.unlocked();

  /// Vuelve a cerrarla. No borra nada: el credencial sigue donde estaba y
  /// el mismo PIN vuelve a abrirla.
  void lock() => state = const VaultSession.locked();

  /// La app se cerró —su ventana se destruyó, por ejemplo al deslizarla
  /// fuera de "recientes"— pero Dart sigue andando (F29: el motor sobrevive
  /// para que el trabajo largo termine). Cerrar la app siempre cerró la
  /// bóveda, porque se iba todo Dart con ella; ahora hay que cerrarla a
  /// propósito, o al volver a abrirla se entraría sin el PIN.
  ///
  /// Solo una bóveda abierta pasa a cerrada: a mitad de crearla, o antes de
  /// saber si existe, no hay nada que cerrar. El trabajo en curso no se
  /// toca: el PIN cuida lo que se ve, no la base, que sigue abierta.
  void lockOnClose() {
    if (state is VaultUnlocked) state = const VaultSession.locked();
  }
}
