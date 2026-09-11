import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/error/failures.dart';

part 'create_vault_state.freezed.dart';

/// En qué anda la pantalla de creación de la bóveda.
///
/// El caso de éxito no tiene estado propio a propósito: cuando la bóveda
/// queda creada, el controlador de sesión pasa a `unlocked` y el router se
/// lleva al usuario de esta pantalla. Un `CreateVaultState.success` se
/// quedaría siempre sin que nadie lo mire.
@freezed
sealed class CreateVaultState with _$CreateVaultState {
  const factory CreateVaultState.idle() = CreateVaultIdle;

  /// Derivando la clave. Puede tardar: es intencionalmente costoso (ver
  /// `Pbkdf2PinHasher`), así que la pantalla tiene que mostrar que está
  /// trabajando.
  const factory CreateVaultState.creating() = CreateVaultCreating;

  /// Guarda el [Failure] entero, no un texto ya armado: la traducción
  /// necesita el `AppLocalizations` de la pantalla, que este notifier no
  /// tiene. Así el idioma lo resuelve quien puede.
  const factory CreateVaultState.failed(Failure failure) = CreateVaultFailed;
}
