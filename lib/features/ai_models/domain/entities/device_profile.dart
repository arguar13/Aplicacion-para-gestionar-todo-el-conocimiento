import 'package:meta/meta.dart';

/// Lo que se sabe del teléfono para decir si un modelo de imágenes del
/// teléfono le alcanza (F43, «Exigente — en el teléfono»).
@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.android,
    required this.arm64,
    this.cpuSupported,
    this.totalRamBytes,
    this.freeStorageBytes,
  });

  /// Si es Android: el motor solo se arma para Android.
  final bool android;

  /// Si el procesador es ARM de 64 bits (`arm64-v8a`), lo único para lo que
  /// se compila el motor.
  final bool arm64;

  /// Si el procesador tiene producto punto y media precisión (ARMv8.2), con
  /// lo que se compila el motor; `null` si no se pudo leer.
  final bool? cpuSupported;

  /// La memoria total que ve el sistema (`MemTotal`); `null` si no se sabe.
  final int? totalRamBytes;

  /// El lugar libre donde se bajan los modelos; `null` si no se sabe.
  final int? freeStorageBytes;

  /// La memoria como la dice la ficha del teléfono: «12 GB». El sistema ve
  /// algo menos —el núcleo se reserva una parte: un teléfono de 12 GB dice
  /// unos 11,2—, así que se lleva a la medida comercial más chica que lo
  /// cubre. `null` si no se sabe.
  int? get ramGb {
    final bytes = totalRamBytes;
    if (bytes == null || bytes <= 0) return null;
    final gib = bytes / (1 << 30);
    for (final size in kPhoneRamSizesGb) {
      if (gib <= size) return size;
    }
    return gib.ceil();
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceProfile &&
      other.android == android &&
      other.arm64 == arm64 &&
      other.cpuSupported == cpuSupported &&
      other.totalRamBytes == totalRamBytes &&
      other.freeStorageBytes == freeStorageBytes;

  @override
  int get hashCode => Object.hash(
    android,
    arm64,
    cpuSupported,
    totalRamBytes,
    freeStorageBytes,
  );

  @override
  String toString() =>
      'DeviceProfile(android: $android, arm64: $arm64, cpu: $cpuSupported, '
      'ram: $ramGb GB, free: $freeStorageBytes)';
}

/// Las memorias con que se venden los teléfonos, en GB.
const kPhoneRamSizesGb = [1, 2, 3, 4, 6, 8, 10, 12, 16, 18, 24, 32];
