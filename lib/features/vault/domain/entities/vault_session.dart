import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_session.freezed.dart';

/// El estado de la bóveda para toda la app: lo que el route guard consulta
/// para decidir qué puede ver el usuario.
///
/// Reemplaza al `SessionState` de tres estados que modelaba una sesión
/// contra un backend. La diferencia importante es [VaultAbsent]: con un
/// servidor, "no tengo sesión" y "no tengo cuenta" son el mismo estado
/// desde el cliente, y se resuelven en la misma pantalla de login. Acá no:
/// que no exista bóveda significa que este dispositivo está estrenándose y
/// hay que crearla, un camino completamente distinto de desbloquear una que
/// ya existe.
@freezed
sealed class VaultSession with _$VaultSession {
  /// Todavía no se leyó el almacenamiento. Es el estado inicial al
  /// arrancar, y el único en el que corresponde quedarse en el splash.
  const factory VaultSession.unknown() = VaultUnknown;

  /// No hay bóveda en este dispositivo: primer arranque.
  const factory VaultSession.absent() = VaultAbsent;

  /// Hay bóveda, cerrada. Hace falta el PIN.
  const factory VaultSession.locked() = VaultLocked;

  /// Abierta. La app está disponible.
  const factory VaultSession.unlocked() = VaultUnlocked;
}
