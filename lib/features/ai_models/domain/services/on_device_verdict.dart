import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';

/// Lo que se le dice a la persona de su teléfono y un modelo (F43, «Tu
/// teléfono: puede / justo / no alcanza»).
enum OnDeviceVerdictLevel {
  /// Le sobra: la memoria recomendada o más.
  can,

  /// Anda, pero justo: entre la memoria mínima y la recomendada, o no se
  /// supo cuánta tiene. Puede tardar más y conviene cerrar otras apps.
  tight,

  /// No: falta memoria, lugar o lo que pide el procesador, o se cerró la
  /// última vez.
  cannot,
}

/// Cada porqué del veredicto, con lo que hace falta para decirlo.
sealed class OnDeviceVerdictReason {
  const OnDeviceVerdictReason();
}

/// No es Android: el motor solo existe ahí.
final class NotAndroid extends OnDeviceVerdictReason {
  const NotAndroid();
}

/// No es ARM de 64 bits.
final class Not64BitArm extends OnDeviceVerdictReason {
  const Not64BitArm();
}

/// El procesador no tiene producto punto ni media precisión (ARMv8.2): el
/// motor se cerraría al dibujar.
final class CpuTooOld extends OnDeviceVerdictReason {
  const CpuTooOld();
}

/// La memoria del teléfono ([ramGb]) y la que pide el modelo, la mínima y la
/// recomendada.
final class RamFacts extends OnDeviceVerdictReason {
  const RamFacts({
    required this.ramGb,
    required this.minGb,
    required this.recommendedGb,
  });

  /// `null` si no se pudo saber.
  final int? ramGb;
  final int minGb;
  final int recommendedGb;
}

/// No hay lugar para bajarlo: hacen falta [neededBytes] y quedan
/// [freeBytes].
final class StorageShort extends OnDeviceVerdictReason {
  const StorageShort({required this.neededBytes, required this.freeBytes});

  final int neededBytes;
  final int freeBytes;
}

/// La última vez que dibujó con este modelo la app se cerró —casi seguro,
/// Android la cerró por falta de memoria—: se apagó solo.
final class ClosedLastTime extends OnDeviceVerdictReason {
  const ClosedLastTime();
}

/// El veredicto de un modelo en este teléfono, con sus porqués.
@immutable
class OnDeviceVerdict {
  const OnDeviceVerdict(this.level, this.reasons);

  final OnDeviceVerdictLevel level;

  /// Lo que se le muestra a la persona, en orden: lo que impide primero.
  final List<OnDeviceVerdictReason> reasons;

  bool get cannot => level == OnDeviceVerdictLevel.cannot;

  /// La falla de imagen que corresponde a que no alcance, o `null` si
  /// alcanza (puede o justo).
  ImageFailure? get failure {
    if (!cannot) return null;
    for (final reason in reasons) {
      switch (reason) {
        case NotAndroid() || Not64BitArm() || CpuTooOld():
          return ImageFailure.unsupportedDevice;
        case ClosedLastTime():
          return ImageFailure.notEnoughMemory;
        case StorageShort():
          return ImageFailure.deviceTooSmall;
        case RamFacts(:final ramGb?, :final minGb) when ramGb < minGb:
          return ImageFailure.deviceTooSmall;
        case RamFacts():
          break;
      }
    }
    return ImageFailure.deviceTooSmall;
  }
}

/// Lo que se deja libre además del modelo al bajarlo: el teléfono no puede
/// quedarse sin lugar para lo demás.
const kOnDeviceStorageMargin = 300 * 1024 * 1024;

/// Si [model] le alcanza a [device]. [downloaded]: ya está en el teléfono
/// (el lugar libre deja de importar). [closedLastTime]: la app se cerró la
/// última vez que dibujó con él.
OnDeviceVerdict onDeviceVerdict(
  OnDeviceImageModel model,
  DeviceProfile device, {
  required bool downloaded,
  bool closedLastTime = false,
}) {
  final spec = model.spec;
  final blocking = <OnDeviceVerdictReason>[
    if (!device.android) const NotAndroid(),
    if (device.android && !device.arm64) const Not64BitArm(),
    if (device.android && device.arm64 && device.cpuSupported == false)
      const CpuTooOld(),
  ];
  if (blocking.isNotEmpty) {
    return OnDeviceVerdict(OnDeviceVerdictLevel.cannot, blocking);
  }
  final ram = device.ramGb;
  final ramFacts = RamFacts(
    ramGb: ram,
    minGb: spec.minRamGb,
    recommendedGb: spec.recommendedRamGb,
  );
  final reasons = <OnDeviceVerdictReason>[
    if (closedLastTime) const ClosedLastTime(),
  ];
  var level = closedLastTime
      ? OnDeviceVerdictLevel.cannot
      : OnDeviceVerdictLevel.can;

  if (ram != null && ram < spec.minRamGb) {
    level = OnDeviceVerdictLevel.cannot;
  } else if ((ram == null || ram < spec.recommendedRamGb) &&
      level == OnDeviceVerdictLevel.can) {
    level = OnDeviceVerdictLevel.tight;
  }
  reasons.add(ramFacts);

  final free = device.freeStorageBytes;
  final needed = spec.bytes + kOnDeviceStorageMargin;
  if (!downloaded && free != null && free < needed) {
    level = OnDeviceVerdictLevel.cannot;
    reasons.add(StorageShort(neededBytes: needed, freeBytes: free));
  }
  // Lo que impide, primero.
  reasons.sort((a, b) => _rank(a, ram).compareTo(_rank(b, ram)));
  return OnDeviceVerdict(level, List.unmodifiable(reasons));
}

int _rank(OnDeviceVerdictReason reason, int? ram) => switch (reason) {
  ClosedLastTime() => 0,
  RamFacts(:final minGb) when ram != null && ram < minGb => 1,
  StorageShort() => 2,
  _ => 3,
};
