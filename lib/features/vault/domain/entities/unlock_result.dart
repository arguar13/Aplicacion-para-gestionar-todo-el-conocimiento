import 'package:freezed_annotation/freezed_annotation.dart';

part 'unlock_result.freezed.dart';

/// Cómo terminó un intento de desbloquear la bóveda.
///
/// No es un `bool` porque "no entraste" tiene dos formas muy distintas para
/// quien está del otro lado: *el PIN no es ese* (y te quedan tantos
/// intentos) y *dejá de probar por ahora* (y falta tanto). Una pantalla que
/// solo supiera "falló" no podría decir ninguna de las dos cosas, y la
/// diferencia entre ambas es justamente lo que evita que alguien siga
/// probando a ciegas.
///
/// Un fallo *técnico* —el almacén no responde, el credencial está
/// corrupto— no es ninguno de estos tres casos: eso viaja como
/// `Left(Failure)`, porque no es un resultado del intento sino la
/// imposibilidad de llevarlo a cabo.
@freezed
sealed class UnlockResult with _$UnlockResult {
  /// PIN correcto. La bóveda queda abierta y el contador de intentos
  /// fallidos vuelve a cero.
  const factory UnlockResult.granted() = UnlockGranted;

  /// PIN incorrecto, y todavía quedan intentos antes de la espera
  /// obligatoria.
  const factory UnlockResult.rejected({required int remainingAttempts}) =
      UnlockRejected;

  /// Se agotaron los intentos: hay que esperar hasta [until] antes de poder
  /// volver a probar. El PIN ni siquiera se comprobó.
  const factory UnlockResult.lockedOut({required DateTime until}) =
      UnlockLockedOut;
}
