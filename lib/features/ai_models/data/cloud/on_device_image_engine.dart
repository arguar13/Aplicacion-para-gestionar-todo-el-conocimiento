import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// Un modelo de imágenes que corre en el teléfono (F43, «Exigente — en el
/// teléfono»): chico (SDXS-512, SD-Turbo), en la CPU, a 512 px, descargado a
/// pedido como Gemma.
///
/// Es un [ImageWire] más —`provider` es `IllustrationProvider.onDevice`, y
/// `generate` dibuja sin clave (el `ImageWireAccess` llega vacío)—, con lo
/// que el teléfono necesita además:
///
/// - **No cuesta dinero ni tiene cuota**: lo que cuesta es tiempo
///   ([estimatedTimePerImage]) y batería, y eso se muestra en vez del precio.
/// - **Puede o no puede según el teléfono** ([readiness]): la memoria, el
///   lugar libre y si el modelo ya se descargó.
///
/// Esta fase no trae ninguno. Para enchufarlo alcanza con sobrescribir
/// `onDeviceImageEngineProvider` con el motor: aparecen solos la fila y la
/// sección de «¿Qué puede cada IA?», la cuenta «del teléfono» que el
/// servicio de ilustraciones sabe usar, y la alternativa «Usar el modelo del
/// teléfono (Exigente)» del aviso, con su tiempo.
abstract interface class OnDeviceImageEngine implements ImageWire {
  /// Su nombre para mostrar: «SDXS 512».
  String get displayName;

  /// Si puede dibujar ahora en este teléfono, y si no, por qué
  /// (`ImageFailure.modelNotDownloaded` o `ImageFailure.deviceTooSmall`).
  Future<OnDeviceImageReadiness> readiness();

  /// Cuánto tarda una imagen de [size], como lo midió o lo estima el motor.
  Duration estimatedTimePerImage(IllustrationSize size);
}

/// Si el modelo del teléfono puede dibujar.
@immutable
class OnDeviceImageReadiness {
  const OnDeviceImageReadiness.ready() : reason = null, downloadBytes = null;

  const OnDeviceImageReadiness.notReady(
    ImageFailure this.reason, {
    this.downloadBytes,
  });

  /// `null` si está listo.
  final ImageFailure? reason;

  /// Cuánto hay que bajar, si falta descargarlo.
  final int? downloadBytes;

  bool get isReady => reason == null;
}
