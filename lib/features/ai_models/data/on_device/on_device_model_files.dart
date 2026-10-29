import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Los archivos de los modelos de imágenes del teléfono (F43, «Exigente»):
/// bajarlos, saber si están, pausarlos, cancelarlos y borrarlos.
///
/// Igual que el modelo de transcripción (`HttpWhisperModelManager`): cada
/// archivo va **fijado a un commit** de Hugging Face y se comprueba por su
/// **tamaño y su huella SHA-256** antes de tomar su nombre definitivo; uno
/// que no coincide se descarta y la descarga falla, en vez de dejar un
/// modelo distinto del verificado. La descarga la hace el
/// [ModelFileTransfer] de todos los modelos: en Android, el gestor del
/// sistema, que sigue con la app cerrada (F29) y avisa si no hay lugar.
///
/// **Qué hay en el disco**, dentro de `modelos/imagenes/`: el archivo entero
/// con su nombre de Hugging Face, y mientras baja lo que deje la
/// transferencia. Borrar un modelo borra solo eso: nada más de la app.
class OnDeviceModelFiles {
  OnDeviceModelFiles({
    required ModelFileTransfer transfer,
    required Future<Directory> Function() rootDirectory,
    @visibleForTesting
    OnDeviceModelSpec Function(OnDeviceImageModel model) specOf = _specOf,
  }) : _transfer = transfer,
       _rootDirectory = rootDirectory,
       _spec = specOf;

  static OnDeviceModelSpec _specOf(OnDeviceImageModel model) => model.spec;

  /// Qué se baja y qué tiene que llegar de cada modelo: el de su ficha; las
  /// pruebas ponen archivos chicos.
  final OnDeviceModelSpec Function(OnDeviceImageModel model) _spec;

  final ModelFileTransfer _transfer;
  final Future<Directory> Function() _rootDirectory;
  final _changes = StreamController<void>.broadcast();

  /// La carpeta, una vez resuelta: lo que se pregunta sin esperar
  /// ([isDownloadedSync]) la necesita.
  Directory? _folder;

  /// Avisa cada vez que un modelo queda bajado o se borra.
  Stream<void> changes() => _changes.stream;

  /// Si la descarga sigue con la app cerrada (la hace el sistema).
  bool get continuesWithAppClosed => _transfer.continuesWithAppClosed;

  /// Ver [ModelFileTransfer.canPause].
  bool get canPause => _transfer.canPause;

  Future<Directory> _directory() async => _folder ??= Directory(
    p.join((await _rootDirectory()).path, 'modelos', 'imagenes'),
  );

  /// Dónde queda el archivo de [model].
  Future<File> fileOf(OnDeviceImageModel model) async =>
      File(p.join((await _directory()).path, _spec(model).fileName));

  /// Un archivo cuenta como bajado si está con su tamaño exacto. La huella
  /// se comprueba al bajarlo, no cada vez: leer 2 GB antes de cada imagen
  /// costaría segundos.
  static bool _isComplete(File file, OnDeviceModelSpec spec) =>
      file.existsSync() && file.lengthSync() == spec.bytes;

  Future<bool> isDownloaded(OnDeviceImageModel model) async =>
      _isComplete(await fileOf(model), _spec(model));

  /// Lo mismo que [isDownloaded], sin esperar: `false` hasta que se resolvió
  /// la carpeta una vez ([prepare]).
  bool isDownloadedSync(OnDeviceImageModel model) {
    final folder = _folder;
    if (folder == null) return false;
    final spec = _spec(model);
    return _isComplete(File(p.join(folder.path, spec.fileName)), spec);
  }

  /// Resuelve la carpeta, para que [isDownloadedSync] responda.
  Future<void> prepare() => _directory();

  /// Cuánto quedó bajado de [model] de una descarga pausada (de 0 a 1), o
  /// `null` si no hay nada a medias.
  Future<double?> pausedProgress(OnDeviceImageModel model) async {
    final partial = InAppModelFileTransfer.partialOf(await fileOf(model));
    if (!partial.existsSync()) return null;
    return (partial.lengthSync() / _spec(model).bytes).clamp(0, 1).toDouble();
  }

  /// Si hay una descarga de [model] en curso: de esta sesión o, con el gestor
  /// del sistema, una que siguió con la app cerrada.
  Future<bool> isDownloading(OnDeviceImageModel model) async =>
      _transfer.isInFlight(await fileOf(model));

  /// Baja [model] y reporta el progreso de 0 a 1. Si ya está, emite 1 y
  /// cierra sin tocar la red. Cualquier falla llega como error del stream:
  /// [InsufficientStorageException] sin lugar, [ModelDownloadPausedException]
  /// si se pausó, [OnDeviceModelIntegrityException] si llegó distinto.
  Stream<double> download(OnDeviceImageModel model) {
    final controller = StreamController<double>();
    unawaited(_run(controller, model));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<double> controller,
    OnDeviceImageModel model,
  ) async {
    final spec = _spec(model);
    try {
      final target = await fileOf(model);
      if (!_isComplete(target, spec)) {
        target.parent.createSync(recursive: true);
        await _transfer.fetch(
          url: spec.downloadUrl,
          target: target,
          expectedBytes: spec.bytes,
          label: LongWorkDetail.imageModel,
          verify: (whole) => _verify(whole, spec),
          onProgress: (received, _) {
            if (!controller.isClosed) {
              controller.add((received / spec.bytes).clamp(0, 1).toDouble());
            }
          },
        );
        _changes.add(null);
      }
      controller.add(1);
      await controller.close();
    } on Object catch (error, stackTrace) {
      // Sin conexión, sin lugar, una huella que no coincide: como error del
      // stream, nunca como una excepción sin dueño que tumbe la pantalla.
      controller.addError(error, stackTrace);
      await controller.close();
    }
  }

  /// Que [downloaded] sea exactamente lo verificado: tamaño y huella. Si no,
  /// la transferencia lo borra y la descarga falla.
  static Future<void> _verify(File downloaded, OnDeviceModelSpec spec) async {
    final matches =
        downloaded.lengthSync() == spec.bytes &&
        (await sha256.bind(downloaded.openRead()).first).toString() ==
            spec.sha256;
    if (!matches) throw OnDeviceModelIntegrityException(spec.fileName);
  }

  /// Frena la descarga de [model] sin borrar lo bajado (ver [canPause]).
  Future<void> pause(OnDeviceImageModel model) async =>
      _transfer.pause(await fileOf(model));

  /// Corta la descarga de [model] y borra lo bajado.
  Future<void> cancel(OnDeviceImageModel model) async {
    await _transfer.cancel(await fileOf(model));
    _changes.add(null);
  }

  /// Borra [model] del teléfono: su archivo y lo que haya quedado a medias
  /// —eso lo borra cancelar, en las dos transferencias—. Nada más.
  Future<void> delete(OnDeviceImageModel model) async {
    final target = await fileOf(model);
    await _transfer.cancel(target);
    if (target.existsSync()) target.deleteSync();
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

/// El archivo de un modelo del teléfono llegó distinto de lo verificado:
/// cortado, o cambiado en el servidor. No se usa.
class OnDeviceModelIntegrityException implements Exception {
  const OnDeviceModelIntegrityException(this.fileName);

  final String fileName;

  @override
  String toString() => 'El archivo $fileName no coincide con el verificado.';
}
