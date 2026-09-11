import 'package:json_annotation/json_annotation.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';

part 'lockout_state.g.dart';

/// Cuántas veces seguidas se erró el PIN y hasta cuándo hay que esperar.
///
/// Se persiste junto al credencial, y no en memoria, justamente porque el
/// ataque obvio contra un límite de intentos es cerrar la app y volver a
/// abrirla. Si el contador viviera en RAM, la espera se esquivaría con un
/// gesto.
@JsonSerializable()
class LockoutState {
  const LockoutState({
    this.failedAttempts = 0,
    this.completedRounds = 0,
    this.lockedUntil,
  });

  factory LockoutState.fromJson(Map<String, dynamic> json) =>
      _$LockoutStateFromJson(json);

  /// El estado de quien nunca falló, o de quien acaba de entrar bien.
  static const initial = LockoutState();

  /// Fallos acumulados dentro de la tanda actual.
  final int failedAttempts;

  /// Tandas ya agotadas. Es el índice del que sale la duración de la
  /// próxima espera (ver [PinPolicy.lockoutFor]): cuantas más lleve, más
  /// larga.
  final int completedRounds;

  /// Hasta cuándo no se aceptan intentos. `null` si no hay espera vigente.
  final DateTime? lockedUntil;

  Map<String, dynamic> toJson() => _$LockoutStateToJson(this);

  /// Si la espera sigue corriendo en [now].
  ///
  /// Recibe el instante en vez de leer el reloj por su cuenta para que los
  /// tests puedan simular el paso del tiempo sin esperarlo de verdad.
  bool isLockedAt(DateTime now) {
    final until = lockedUntil;
    return until != null && now.isBefore(until);
  }

  /// Intentos que quedan antes de la próxima espera.
  int get remainingAttempts =>
      PinPolicy.maxAttemptsBeforeLockout - failedAttempts;

  /// El estado después de un fallo más.
  ///
  /// Mientras queden intentos, solo sube el contador. Cuando se agotan,
  /// arranca la espera, se cierra la tanda y el contador vuelve a cero para
  /// que la siguiente empiece limpia — con una espera más larga.
  LockoutState afterFailedAttempt(DateTime now) {
    final attempts = failedAttempts + 1;

    if (attempts < PinPolicy.maxAttemptsBeforeLockout) {
      return LockoutState(
        failedAttempts: attempts,
        completedRounds: completedRounds,
        lockedUntil: lockedUntil,
      );
    }

    return LockoutState(
      completedRounds: completedRounds + 1,
      lockedUntil: now.add(PinPolicy.lockoutFor(completedRounds)),
    );
  }
}
