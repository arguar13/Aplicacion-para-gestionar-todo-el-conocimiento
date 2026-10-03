import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Baja un archivo de la biblioteca de ejemplo a un lugar temporal, para
/// capturarlo después como si el usuario lo hubiera elegido.
///
/// A disco y no a memoria: entre los ejemplos hay libros enteros y audios
/// de más de media hora, y la captura los copia por partes al almacén
/// (F21) —cargarlos enteros acá desharía eso—.
abstract interface class SampleFileDownloader {
  /// Baja [resource]. Lanza [SampleDownloadException] si no se pudo, y
  /// [ProcessingCancelledException] si [cancellation] pidió cortar —sin
  /// dejar nada a medias en el disco—.
  Future<DownloadedSample> download(
    SampleFile resource, {
    required CancellationSignal cancellation,
  });

  /// Borra lo que haya quedado de una pasada anterior: si la app se cerró a
  /// mitad de una bajada, el temporal quedó en el disco y nadie más lo va a
  /// borrar. Se llama al empezar cada pasada.
  Future<void> clearLeftovers();
}

/// Un archivo ya bajado, listo para capturar, y cómo borrarlo después.
class DownloadedSample {
  const DownloadedSample({required this.file, required this.discard});

  final CapturedFile file;

  /// Borra la copia temporal. Se llama siempre, se haya guardado o no: lo
  /// que queda en la biblioteca es la copia del almacén, no esta.
  final Future<void> Function() discard;
}

/// No se pudo bajar un archivo de ejemplo: el servidor no respondió, dio un
/// error o no se pudo escribir el temporal.
class SampleDownloadException implements Exception {
  const SampleDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
