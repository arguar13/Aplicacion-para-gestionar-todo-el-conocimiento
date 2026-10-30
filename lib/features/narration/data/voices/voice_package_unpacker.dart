import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Abre un paquete de voz de sherpa-onnx (`.tar.bz2`) en una carpeta (F47,
/// paso 3).
///
/// Los paquetes vienen así, y no sueltos como los archivos de Whisper, porque
/// cada voz trae cientos de archivos —los datos de espeak-ng con que
/// pronuncia—: bajarlos de a uno serían cientos de descargas. Se baja el
/// paquete entero, verificado por su huella, y se abre acá.
// ignore: one_member_abstracts
abstract interface class VoicePackageUnpacker {
  /// Abre [archive] dentro de [into], que no existe o está vacía. Falla con lo
  /// que falle el disco —sin lugar, `FileSystemException`— o con
  /// `ArchiveException` si el paquete no se puede abrir: nunca deja un archivo
  /// cortado como si estuviera entero.
  Future<void> unpack(File archive, Directory into);
}

/// Lo abre en un isolate aparte: descomprimir cien megas de bzip2 lleva
/// decenas de segundos, y no puede trabar la pantalla.
class IsolateVoicePackageUnpacker implements VoicePackageUnpacker {
  const IsolateVoicePackageUnpacker();

  @override
  Future<void> unpack(File archive, Directory into) {
    final archivePath = archive.path;
    final intoPath = into.path;
    return Isolate.run(() => unpackTarBz2(archivePath, intoPath));
  }
}

/// Abre el `.tar.bz2` de [archivePath] en [intoPath], de a un archivo por vez
/// y sin tenerlo entero en memoria: primero el bzip2 a un `.tar` al lado —en
/// la misma carpeta, que es la del mismo disco que los modelos—, después cada
/// archivo del `.tar` a su lugar, y al final se borra el `.tar`.
///
/// A diferencia de `extractFileToDisk` de `archive`, **no se traga ningún
/// error**: si el disco se llena a mitad de un archivo, falla, en vez de dejar
/// el archivo cortado y seguir con el próximo. Tampoco escribe afuera de
/// [intoPath] —un nombre con `..`— ni crea enlaces: un paquete de voz no los
/// necesita.
void unpackTarBz2(String archivePath, String intoPath) {
  final into = p.normalize(p.absolute(intoPath));
  Directory(into).createSync(recursive: true);
  final tarPath = p.join(into, '.paquete.tar');

  final compressed = InputFileStream(archivePath);
  final tar = OutputFileStream(tarPath);
  try {
    BZip2Decoder().decodeStream(compressed, tar, verify: true);
  } finally {
    compressed.closeSync();
    tar.closeSync();
  }

  final input = InputFileStream(tarPath);
  try {
    for (final entry in TarDecoder().decodeStream(input)) {
      final target = p.normalize(p.join(into, entry.name));
      if (!p.isWithin(into, target) || entry.isSymbolicLink) continue;
      if (!entry.isFile) {
        Directory(target).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(target)).createSync(recursive: true);
      final output = OutputFileStream(target);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
    File(tarPath).deleteSync();
  }
}
