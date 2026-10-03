import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Qué memoria del proceso se mide.
enum MemoryMeasure {
  /// La memoria residente: lo que está en la RAM ahora. Es lo que reportan
  /// las cifras de rendimiento (`docs/benchmarks/`), y por eso es la de
  /// siempre.
  residentSet,

  /// La memoria propia que el proceso pidió y tiene comprometida, esté en la
  /// RAM o no. Es la que hay que mirar para saber si algo pasó entero por la
  /// memoria.
  ///
  /// En Windows la residente es el "conjunto de trabajo", y el sistema se lo
  /// recorta al proceso cuando la máquina está cargada: si el recorte cae
  /// justo antes de empezar a medir, el punto de partida queda bajo y las
  /// páginas que vuelven a entrar —que no son memoria nueva— se cuentan como
  /// crecimiento. Así falló una vez la prueba de la fusión por streaming (51
  /// MB contra un tope de 41) con otros análisis corriendo a la vez. La
  /// comprometida no se recorta.
  privateCommit,
}

/// La memoria del proceso según [measure], en bytes.
///
/// Fuera de Windows, la privada comprometida se lee como la residente: Linux
/// y macOS no le recortan la memoria a un proceso por tener otros al lado de
/// la misma forma, y en Android/iOS estas pruebas no corren.
int processMemory(MemoryMeasure measure) {
  if (measure == MemoryMeasure.privateCommit && Platform.isWindows) {
    return _windowsPrivateUsage();
  }
  return ProcessInfo.currentRss;
}

/// `PROCESS_MEMORY_COUNTERS_EX.PrivateUsage`, de `GetProcessMemoryInfo`.
///
/// La estructura, en 64 bits: dos `DWORD` (`cb`, `PageFaultCount`) y nueve
/// `SIZE_T`, el último `PrivateUsage`: 80 bytes, y `PrivateUsage` empieza en
/// el byte 72.
int _windowsPrivateUsage() {
  const size = 80;
  const privateUsageOffset = 72;
  final counters = calloc<Uint8>(size);
  try {
    counters.cast<Uint32>().value = size;
    final ok = _getProcessMemoryInfo(
      _getCurrentProcess(),
      counters.cast(),
      size,
    );
    if (ok == 0) {
      throw StateError('GetProcessMemoryInfo falló');
    }
    return (counters + privateUsageOffset).cast<Uint64>().value;
  } finally {
    calloc.free(counters);
  }
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getCurrentProcess = _kernel32
    .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');

/// `K32GetProcessMemoryInfo`: el nombre con el que `kernel32` lo exporta
/// desde Windows 7, sin tener que cargar `psapi.dll`.
final _getProcessMemoryInfo = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int)
    >('K32GetProcessMemoryInfo');
