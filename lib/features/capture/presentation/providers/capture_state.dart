import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/error/failures.dart';

part 'capture_state.freezed.dart';

/// En qué anda la pantalla de captura.
///
/// El éxito no tiene estado propio: cuando algo queda guardado, la pantalla
/// se cierra y vuelve a la biblioteca, donde el elemento ya aparece —el
/// stream de la lista lo trae solo—. Un `success` que nadie llega a ver sería
/// un estado de más.
@freezed
sealed class CaptureState with _$CaptureState {
  const factory CaptureState.idle() = CaptureIdle;
  const factory CaptureState.saving() = CaptureSaving;
  const factory CaptureState.failed(Failure failure) = CaptureFailed;
}
