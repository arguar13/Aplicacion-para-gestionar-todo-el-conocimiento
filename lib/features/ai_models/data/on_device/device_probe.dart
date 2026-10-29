import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';

/// Lo que se le pregunta al teléfono para saber si le alcanza un modelo de
/// imágenes (F43): la memoria, el procesador y el lugar libre. Detrás de una
/// interfaz porque el teléfono real no se puede simular: las pruebas le
/// ponen uno de mentira.
// ignore: one_member_abstracts
abstract interface class DeviceProbe {
  Future<DeviceProfile> read();
}

/// [DeviceProbe] del teléfono de verdad, sin canal propio:
///
/// - **la memoria**, de `/proc/meminfo` (`MemTotal`), que cualquier app de
///   Android puede leer: es lo mismo que `ActivityManager.MemoryInfo.totalMem`;
/// - **el procesador**, de `/proc/cpuinfo` (`Features`): `asimddp` es el
///   producto punto y `asimdhp`/`fphp`, la media precisión;
/// - **ARM de 64 bits**, de lo que dice Dart del proceso ([Abi.current]);
/// - **el lugar libre**, de lo que se le pasa al crearla: el del lugar donde
///   se bajan los modelos.
///
/// Lo que no se pueda leer queda `null` («no se sabe»), nunca cero.
class SystemDeviceProbe implements DeviceProbe {
  SystemDeviceProbe({
    required Future<int?> Function() freeBytes,
    this.meminfo = '/proc/meminfo',
    this.cpuinfo = '/proc/cpuinfo',
    bool? android,
    Abi? abi,
  }) : _freeBytes = freeBytes,
       _android =
           android ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _abi = abi ?? Abi.current();

  final Future<int?> Function() _freeBytes;
  final bool _android;
  final Abi _abi;

  /// Dónde leer; las pruebas los apuntan a archivos propios.
  final String meminfo;
  final String cpuinfo;

  @override
  Future<DeviceProfile> read() async {
    if (!_android) {
      return const DeviceProfile(android: false, arm64: false);
    }
    int? free;
    try {
      free = await _freeBytes();
    } on Object {
      free = null;
    }
    return DeviceProfile(
      android: true,
      arm64: _abi == Abi.androidArm64,
      cpuSupported: cpuFeaturesSupported(await _readOrNull(cpuinfo)),
      totalRamBytes: memTotalBytes(await _readOrNull(meminfo)),
      freeStorageBytes: free,
    );
  }

  static Future<String?> _readOrNull(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }
}

/// `MemTotal` de [meminfo] (en kB) en bytes, o `null` si no está.
@visibleForTesting
int? memTotalBytes(String? meminfo) {
  if (meminfo == null) return null;
  final match = RegExp(
    r'^MemTotal:\s*(\d+)\s*kB',
    multiLine: true,
  ).firstMatch(meminfo);
  final kb = int.tryParse(match?.group(1) ?? '');
  return kb == null || kb <= 0 ? null : kb * 1024;
}

/// Si todos los núcleos de [cpuinfo] tienen producto punto (`asimddp`) y
/// media precisión (`asimdhp` o `fphp`): con eso se compila el motor. `null`
/// si no dice nada de eso (no se sabe).
@visibleForTesting
bool? cpuFeaturesSupported(String? cpuinfo) {
  if (cpuinfo == null) return null;
  final lines = RegExp(
    r'^Features\s*:\s*(.*)$',
    multiLine: true,
  ).allMatches(cpuinfo).map((m) => m.group(1)!.split(RegExp(r'\s+')).toSet());
  if (lines.isEmpty) return null;
  return lines.every(
    (features) =>
        features.contains('asimddp') &&
        (features.contains('asimdhp') || features.contains('fphp')),
  );
}
