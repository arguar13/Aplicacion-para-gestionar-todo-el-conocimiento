import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/transform/data/services/whisper_model_spec.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El modelo Whisper multilingüe "small", cuantizado a int8: unos 375 MB en
/// total. Se prefiere a "base" —bastante más liviano, ~160 MB— porque en
/// español, que es el idioma principal de quien usa esta app, la ganancia
/// de precisión de "base" a "small" es notoria, y el dispositivo hace el
/// trabajo una sola vez por transcripción, no en tiempo real. Ver la
/// decisión 8 en docs/arquitectura.md.
///
/// Qué se baja y de dónde lo dice [WhisperModelSpec]: desde F23, la
/// exportación que permite saber cuándo se dice cada palabra. Los archivos
/// se traen sueltos de Hugging Face —no un paquete .tar.bz2— para no tener
/// que descomprimir bzip2 en el dispositivo, y **cada uno se comprueba por
/// su tamaño y su huella SHA-256** antes de usarlo: uno que no coincide se
/// descarta y la descarga falla, en vez de dejar un modelo a medias o
/// distinto del verificado.
///
/// La descarga la hace un [ModelFileTransfer]: en Android, el gestor de
/// descargas del sistema, que sigue con la app cerrada (F29). Lo que quedó
/// entero en `earlierRoots` —antes de F29 se bajaba a la carpeta interna de
/// la app, donde el sistema no puede escribir— se sigue usando donde está.
class HttpWhisperModelManager implements WhisperModelManager {
  HttpWhisperModelManager({
    required ModelFileTransfer transfer,
    required Future<Directory> Function() rootDirectory,
    List<Future<Directory> Function()> earlierRoots = const [],
    WhisperModelSpec spec = WhisperModelSpec.smallWithAttention,
  }) : _transfer = transfer,
       _rootDirectory = rootDirectory,
       _earlierRoots = earlierRoots,
       _spec = spec;

  final ModelFileTransfer _transfer;
  final Future<Directory> Function() _rootDirectory;
  final List<Future<Directory> Function()> _earlierRoots;
  final WhisperModelSpec _spec;

  Future<Directory> _modelDirectoryIn(
    Future<Directory> Function() root,
  ) async => Directory(p.join((await root()).path, 'modelos', _spec.folder));

  Future<Directory> _modelDirectory() => _modelDirectoryIn(_rootDirectory);

  /// Un archivo cuenta como bajado si está con su tamaño exacto. La huella
  /// se comprueba al bajarlo, no cada vez: leer 375 MB antes de cada
  /// transcripción costaría segundos.
  static bool _isComplete(File file, WhisperModelFile spec) =>
      file.existsSync() && file.lengthSync() == spec.bytes;

  bool _hasAllFiles(Directory dir) =>
      _spec.files.every((f) => _isComplete(File(p.join(dir.path, f.name)), f));

  /// La carpeta donde está el modelo entero: la de ahora o una de antes;
  /// `null` si no está entero en ninguna.
  Future<Directory?> _readyDirectory() async {
    for (final root in [_rootDirectory, ..._earlierRoots]) {
      final dir = await _modelDirectoryIn(root);
      if (_hasAllFiles(dir)) return dir;
    }
    return null;
  }

  @override
  Future<bool> isReady() async => await _readyDirectory() != null;

  @override
  Future<WhisperModelPaths> paths() async {
    final dir = await _readyDirectory() ?? await _modelDirectory();
    return WhisperModelPaths(
      encoder: p.join(dir.path, _spec.encoder.name),
      decoder: p.join(dir.path, _spec.decoder.name),
      tokens: p.join(dir.path, _spec.tokens.name),
    );
  }

  /// Se sabe de antemano —los tamaños están verificados—: sin preguntarle
  /// nada al servidor, también sin conexión.
  @override
  Future<int?> downloadSizeInBytes() async => _spec.totalBytes;

  @override
  Future<bool> isDownloading() async {
    final dir = await _modelDirectory();
    for (final file in _spec.files) {
      if (await _transfer.isInFlight(File(p.join(dir.path, file.name)))) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> cancelDownload() async {
    final dir = await _modelDirectory();
    for (final file in _spec.files) {
      await _transfer.cancel(File(p.join(dir.path, file.name)));
    }
  }

  @override
  Stream<double> download() {
    final controller = StreamController<double>();
    unawaited(_runDownload(controller));
    return controller.stream;
  }

  Future<void> _runDownload(StreamController<double> controller) async {
    try {
      if (await isReady()) {
        controller.add(1);
        await controller.close();
        return;
      }
      final dir = await _modelDirectory();
      await dir.create(recursive: true);

      // El total de los tres archivos juntos, para que el progreso avance
      // parejo. Los tres a la vez y no uno detrás del otro: con el gestor
      // del sistema la descarga sigue con la app cerrada, y lo que todavía
      // no se pidió no la seguiría.
      final total = _spec.totalBytes;
      final received = <String, int>{};
      void report() {
        if (controller.isClosed) return;
        final done = received.values.fold(0, (sum, bytes) => sum + bytes);
        controller.add(done / total);
      }

      await Future.wait([
        for (final file in _spec.files)
          _fetchFile(dir, file, (bytes) {
            received[file.name] = bytes;
            report();
          }),
      ]);

      await _deleteReplacedModels();
      controller.add(1);
      await controller.close();
    } on Object catch (e, stackTrace) {
      // Cualquier cosa que salga mal acá —sin conexión, disco lleno, el
      // archivo ya no está en el servidor— tiene que llegar como error del
      // stream, nunca como una excepción sin dueño que tumbe la pantalla que
      // está mirando el progreso.
      controller.addError(e, stackTrace);
      await controller.close();
    }
  }

  /// Trae [file] a [dir], salvo que ya esté entero de un intento anterior:
  /// reintentar después de un corte retoma desde el archivo que falló, no
  /// desde el primero de los tres.
  Future<void> _fetchFile(
    Directory dir,
    WhisperModelFile file,
    void Function(int received) onReceived,
  ) async {
    final target = File(p.join(dir.path, file.name));
    if (_isComplete(target, file)) {
      onReceived(file.bytes);
      return;
    }
    await _adoptOldPartial(dir, file);
    await _transfer.fetch(
      url: _spec.urlOf(file),
      target: target,
      expectedBytes: file.bytes,
      label: LongWorkDetail.transcriptionModel,
      // Lo que se pegue mal o llegue distinto lo descarta la huella.
      verify: (whole) => _verify(whole, file),
      onProgress: (received, _) => onReceived(received),
    );
    onReceived(file.bytes);
  }

  /// Hasta F29, lo bajado a medias se llamaba `.<nombre>.descargando`.
  /// Donde se sigue bajando —en el escritorio, la misma carpeta— se retoma
  /// con su nombre nuevo; en la carpeta de antes, ya no se va a retomar y se
  /// borra para no ocupar lugar.
  Future<void> _adoptOldPartial(Directory dir, WhisperModelFile file) async {
    final current = File(p.join(dir.path, '.${file.name}.descargando'));
    final adopted = InAppModelFileTransfer.partialOf(
      File(p.join(dir.path, file.name)),
    );
    if (current.existsSync() &&
        !_transfer.continuesWithAppClosed &&
        !adopted.existsSync()) {
      await current.rename(adopted.path);
    }
    for (final root in [_rootDirectory, ..._earlierRoots]) {
      final earlierDir = await _modelDirectoryIn(root);
      final old = File(p.join(earlierDir.path, '.${file.name}.descargando'));
      if (old.existsSync()) await old.delete();
    }
  }

  /// Que [downloaded] sea exactamente [expected]: tamaño y huella. Si no,
  /// se borra —no queda nada a medias que `isReady()` pudiera aceptar— y
  /// la descarga falla.
  Future<void> _verify(File downloaded, WhisperModelFile expected) async {
    final matches =
        downloaded.lengthSync() == expected.bytes &&
        (await sha256.bind(downloaded.openRead()).first).toString() ==
            expected.sha256;
    if (matches) return;
    await downloaded.delete();
    throw WhisperModelIntegrityException(expected.name);
  }

  /// El modelo de antes, ya reemplazado por uno entero y verificado: sus
  /// 375 MB no sirven más. También lo que haya quedado en la carpeta de
  /// antes de F29 del mismo modelo, ahora que está entero en la nueva.
  Future<void> _deleteReplacedModels() async {
    final current = await _modelDirectory();
    for (final root in [_rootDirectory, ..._earlierRoots]) {
      final models = Directory(p.join((await root()).path, 'modelos'));
      for (final folder in [..._spec.replaces, _spec.folder]) {
        final old = Directory(p.join(models.path, folder));
        if (p.equals(old.path, current.path)) continue;
        if (old.existsSync()) await old.delete(recursive: true);
      }
    }
  }
}
