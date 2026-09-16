import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

/// Baja el archivo de un modelo de Hugging Face ya resuelto —ver
/// `FlutterGemma.resolveHuggingFace`— con reanudación de verdad, en vez de
/// dejar la descarga en manos de `background_downloader` (lo que usa
/// `flutter_gemma` por dentro para `fromHuggingFace`/`fromNetwork`).
///
/// Ese camino pasa por WorkManager en Android, que corta cualquier tarea a
/// los ~9 minutos; retoma sola si el servidor lo permite, pero Hugging Face
/// sirve ETags débiles y no cumple lo que `background_downloader` necesita
/// para confiar en una reanudación, así que ahí la tarea "falla derecho" en
/// vez de pausarse. En una conexión que no alcance a bajar el archivo
/// entero —varios cientos de megas, a veces unos pocos gigas— en esos 9
/// minutos, la descarga nunca llega a terminar por más reintentos que haga:
/// cada intento vuelve a arrancar de cero y se corta en el mismo punto.
///
/// Acá, en cambio, la descarga corre en el propio proceso de la app, sin
/// ningún límite de tiempo por intento, y si se corta retoma desde el byte
/// donde se quedó con un pedido HTTP Range — no desde cero. El costo es el
/// de siempre para una descarga así: la app tiene que seguir abierta
/// mientras dura, igual que ya le pasa a la del modelo de transcripción
/// (`HttpWhisperModelManager`). A cambio, una conexión lenta ya no es un
/// techo de tiempo que la descarga nunca puede cruzar: es, como corresponde,
/// solo una cuestión de paciencia.
class HttpGemmaModelDownloader {
  HttpGemmaModelDownloader({
    required Dio dio,
    required Future<Directory> Function() rootDirectory,
  }) : _dio = dio,
       _rootDirectory = rootDirectory;

  final Dio _dio;
  final Future<Directory> Function() _rootDirectory;

  /// Cuántas veces se reintenta un corte transitorio —la conexión se cae un
  /// instante, el servidor contesta 5xx— antes de rendirse. Más alto que el
  /// de Whisper a propósito: acá cada intento retoma desde donde se quedó
  /// —ver la clase—, así que un reintento de más no vuelve a pagar el costo
  /// de lo ya bajado, y una conexión inestable se beneficia de insistir.
  static const _maxAttempts = 8;

  /// Dónde queda el archivo bajado, sin depender de que la descarga haya
  /// terminado — para poder instalarlo con `fromFile()` una vez que sí lo
  /// esté.
  Future<File> targetFile(String fileName) async {
    final root = await _rootDirectory();
    return File(p.join(root.path, 'modelos', 'gemma', fileName));
  }

  /// El archivo donde queda anotada la URL con la que se bajó —o se está
  /// bajando— [targetFile]. Antes de retomar una descarga a medias se
  /// compara contra la URL pedida ahora: si el modelo resolvió a una
  /// variante distinta desde la última vez —el dispositivo cambió, el
  /// manifiesto se actualizó—, seguir agregándole bytes de la URL nueva a
  /// un archivo que empezó con la vieja produciría un archivo corrupto en
  /// vez de, como acá, empezar de nuevo.
  Future<File> _sourceMarkerFile(String fileName) async {
    final target = await targetFile(fileName);
    return File('${target.path}.source');
  }

  /// Baja [url] a un archivo local y reporta el progreso como una fracción
  /// de 0 a 1. Emite un error del stream si se agotan los reintentos —nunca
  /// una excepción sin dueño— y cierra el stream al terminar.
  Stream<double> download({
    required String url,
    required String fileName,
    String? token,
    int? expectedSizeBytes,
  }) {
    final controller = StreamController<double>();
    unawaited(_run(controller, url, fileName, token, expectedSizeBytes));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<double> controller,
    String url,
    String fileName,
    String? token,
    int? expectedSizeBytes,
  ) async {
    try {
      final file = await targetFile(fileName);
      await file.parent.create(recursive: true);
      await _discardIfSourceChanged(file, fileName, url);

      for (var attempt = 1; ; attempt++) {
        try {
          await _attempt(file, url, token, expectedSizeBytes, controller);
          break;
          // Un 401/403 —repositorio protegido, token vencido— o un 404 —el
          // archivo ya no está ahí— no se arreglan solos reintentando: es
          // el mismo motivo por el que `SmartDownloader` (el que usa
          // `flutter_gemma` por dentro) tampoco los reintenta.
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403 || status == 404) rethrow;
          if (attempt >= _maxAttempts) rethrow;
          await Future<void>.delayed(Duration(seconds: attempt * 3));
        }
      }

      controller.add(1);
      await controller.close();
      // Catch-all deliberado, mismo motivo que en `HttpWhisperModelManager`:
      // cualquier fallo tiene que llegar como error del stream, nunca como
      // una excepción sin dueño que tumbe la pantalla de descarga.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
      await controller.close();
    }
  }

  Future<void> _discardIfSourceChanged(
    File file,
    String fileName,
    String url,
  ) async {
    final marker = await _sourceMarkerFile(fileName);
    final previousUrl = marker.existsSync() ? marker.readAsStringSync() : null;

    if (previousUrl != null && previousUrl != url && file.existsSync()) {
      await file.delete();
    }
    await marker.writeAsString(url);
  }

  Future<void> _attempt(
    File file,
    String url,
    String? token,
    int? expectedSizeBytes,
    StreamController<double> controller,
  ) async {
    final existingBytes = file.existsSync() ? file.lengthSync() : 0;

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          if (existingBytes > 0) 'range': 'bytes=$existingBytes-',
          if (token != null && token.isNotEmpty)
            'authorization': 'Bearer $token',
        },
      ),
    );

    // Un servidor que no soporta reanudar contesta 200 igual —el archivo
    // entero, desde el principio— en vez de 206: ahí hay que empezar de
    // cero, no agregarle el archivo nuevo al que ya había a medias.
    final resumed = existingBytes > 0 && response.statusCode == 206;
    final total =
        expectedSizeBytes ?? _contentLengthOf(response, resumed, existingBytes);

    final sink = file.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var received = resumed ? existingBytes : 0;

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          controller.add((received / total).clamp(0, 1));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// El tamaño total, a partir de la cabecera de la respuesta cuando el
  /// manifiesto no lo trajo de antemano. Un 206 informa en
  /// `Content-Length` solo lo que falta —no el archivo entero—, así que
  /// hay que sumarle lo que ya se tenía para que el progreso no arranque
  /// mintiendo un total más chico que el real.
  int? _contentLengthOf(
    Response<ResponseBody> response,
    bool resumed,
    int existingBytes,
  ) {
    final header = response.headers.value(Headers.contentLengthHeader);
    final length = header == null ? null : int.tryParse(header);
    if (length == null) return null;
    return resumed ? length + existingBytes : length;
  }
}
