import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/error/failures.dart';

part 'unlock_vault_state.freezed.dart';

/// En qué anda la pantalla de desbloqueo.
///
/// Distingue tres desenlaces que para el usuario no son lo mismo: la clave
/// está mal y quedan intentos, se agotaron los intentos y hay que esperar,
/// o algo falló de verdad y ni siquiera se pudo comprobar. Como en
/// `CreateVaultState`, el éxito no necesita estado: el router se encarga.
@freezed
sealed class UnlockVaultState with _$UnlockVaultState {
  const factory UnlockVaultState.idle() = UnlockVaultIdle;

  const factory UnlockVaultState.verifying() = UnlockVaultVerifying;

  const factory UnlockVaultState.rejected({required int remainingAttempts}) =
      UnlockVaultRejected;

  const factory UnlockVaultState.lockedOut({required DateTime until}) =
      UnlockVaultLockedOut;

  /// Un fallo técnico, no una clave equivocada: el almacenamiento no
  /// responde o el credencial está dañado.
  const factory UnlockVaultState.failed(Failure failure) = UnlockVaultFailed;
}
