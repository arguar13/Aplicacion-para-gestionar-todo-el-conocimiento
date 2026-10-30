import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/narration/data/voices/voice_package_unpacker.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Los paquetes de las voces sin conexión en el teléfono (F47, paso 3):
/// bajarlos **solo a pedido**, saber cuáles están, pausarlos, cancelarlos y
/// borrarlos.
///
/// Igual que los modelos de imágenes del teléfono (`OnDeviceModelFiles`):
/// cada paquete se comprueba por su **tamaño y su huella SHA-256** antes de
/// tomar su nombre definitivo, y la descarga la hace el [ModelFileTransfer]
/// de todos los modelos —en Android, el gestor del sistema, que sigue con la
/// app cerrada (F29)—. Después se abre (ver [VoicePackageUnpacker]) y se
/// borra el comprimido: queda solo lo que la voz usa.
///
/// **Qué hay en el disco**, dentro de `modelos/voces/`:
///
/// - `<paquete>/`, la voz abierta, con su ficha `.voz.json` —qué modelo es y
///   dónde están sus archivos—, que se escribe **al final**: una carpeta sin
///   ficha es una voz que no terminó de abrirse, y no cuenta;
/// - mientras baja, `<paquete>.tar.bz2` (y lo que deje la transferencia), y
///   mientras se abre, `.<paquete>.abriendo/`.
///
/// Borrar una voz borra solo eso: nada más de la app.
class OfflineVoiceFiles {
  OfflineVoiceFiles({
    required ModelFileTransfer transfer,
    required Future<Directory> Function() rootDirectory,
    VoicePackageUnpacker unpacker = const IsolateVoicePackageUnpacker(),
  }) : _transfer = transfer,
       _rootDirectory = rootDirectory,
       _unpacker = unpacker;

  /// Lo que la descarga cuenta hasta tener el paquete; abrirlo es el resto.
  static const downloadShare = 0.9;

  static const _manifestName = '.voz.json';

  final ModelFileTransfer _transfer;
  final Future<Directory> Function() _rootDirectory;
  final VoicePackageUnpacker _unpacker;

  final _changes = StreamController<void>.broadcast();
  Directory? _folder;

  /// Avisa cada vez que una voz queda en el teléfono o se borra.
  Stream<void> changes() => _changes.stream;

  /// Ver [ModelFileTransfer.canPause].
  bool get canPause => _transfer.canPause;

  Future<Directory> _directory() async => _folder ??= Directory(
    p.join((await _rootDirectory()).path, 'modelos', 'voces'),
  );

  Future<File> _archiveOf(OfflineVoicePackage package) async =>
      File(p.join((await _directory()).path, package.archiveName));

  Future<Directory> _installedFolderOf(OfflineVoicePackage package) async =>
      Directory(p.join((await _directory()).path, package.id));

  Future<Directory> _stagingOf(OfflineVoicePackage package) async =>
      Directory(p.join((await _directory()).path, '.${package.id}.abriendo'));

  /// Si [package] está en el teléfono, abierto y listo.
  Future<bool> isInstalled(OfflineVoicePackage package) async => File(
    p.join((await _installedFolderOf(package)).path, _manifestName),
  ).existsSync();

  /// Los paquetes de [packages] —los del catálogo— que están en el teléfono.
  Future<Set<String>> installedPackageIds([
    Iterable<OfflineVoicePackage> packages = OfflineVoiceCatalog.packages,
  ]) async {
    return {
      for (final package in packages)
        if (await isInstalled(package)) package.id,
    };
  }

  /// Cuánto ocupa [package] abierto, o `null` si no está.
  Future<int?> installedBytes(OfflineVoicePackage package) async {
    final folder = await _installedFolderOf(package);
    if (!await isInstalled(package)) return null;
    var bytes = 0;
    for (final entry in folder.listSync(recursive: true)) {
      if (entry is File) bytes += entry.lengthSync();
    }
    return bytes;
  }

  /// Dónde están los archivos de [voice], para armar su motor; `null` si su
  /// paquete no está.
  Future<OfflineVoiceEngineConfig?> engineConfigOf(OfflineVoice voice) async {
    final folder = await _installedFolderOf(voice.package);
    final manifest = File(p.join(folder.path, _manifestName));
    if (!manifest.existsSync()) return null;
    final files = OfflineVoiceManifest.decode(manifest.readAsStringSync());
    final base = p.join(folder.path, files.base);
    final kokoro = voice.kokoroPhonemes;
    return OfflineVoiceEngineConfig(
      family: voice.package.family,
      model: p.join(base, files.model),
      tokens: p.join(base, 'tokens.txt'),
      dataDir: p.join(base, 'espeak-ng-data'),
      voices: voice.package.family == OfflineVoiceFamily.kokoro
          ? p.join(base, 'voices.bin')
          : null,
      lexicon: kokoro?.lexicon == null ? null : p.join(base, kokoro!.lexicon),
      espeakVoice: kokoro?.espeakVoice,
    );
  }

  /// Si hay una descarga de [package] en curso: de esta sesión o, con el
  /// gestor del sistema, una que siguió con la app cerrada.
  Future<bool> isDownloading(OfflineVoicePackage package) async =>
      _transfer.isInFlight(await _archiveOf(package));

  /// Baja [package] y lo abre, con el avance de 0 a 1: hasta [downloadShare]
  /// la descarga, y el resto abrirlo. Si ya está, emite 1 y cierra sin tocar
  /// la red; si el comprimido quedó entero de una vez anterior —la app se
  /// cerró mientras se abría—, lo abre sin volver a bajarlo. Cualquier falla
  /// llega como error del stream: [InsufficientStorageException] sin lugar,
  /// [ModelDownloadPausedException] si se pausó,
  /// [OfflineVoiceIntegrityException] si llegó distinto.
  Stream<double> download(OfflineVoicePackage package) {
    final controller = StreamController<double>();
    unawaited(_run(controller, package));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<double> controller,
    OfflineVoicePackage package,
  ) async {
    void report(double progress) {
      if (!controller.isClosed) controller.add(progress);
    }

    try {
      if (!await isInstalled(package)) {
        final archive = await _archiveOf(package);
        if (!_isWhole(archive, package)) {
          archive.parent.createSync(recursive: true);
          await _transfer.fetch(
            url: package.url,
            target: archive,
            expectedBytes: package.bytes,
            label: LongWorkDetail.voiceModel,
            verify: (whole) => _verify(whole, package),
            onProgress: (received, _) =>
                report((received / package.bytes).clamp(0, 1) * downloadShare),
          );
        }
        report(downloadShare);
        await _install(package, archive);
        _changes.add(null);
      }
      report(1);
      await controller.close();
    } on Object catch (error, stackTrace) {
      // Sin conexión, sin lugar, una huella que no coincide: como error del
      // stream, nunca como una excepción sin dueño que tumbe la pantalla.
      controller.addError(error, stackTrace);
      await controller.close();
    }
  }

  /// Un comprimido cuenta como entero si está con su tamaño exacto: solo
  /// toma su nombre después de pasar la huella.
  static bool _isWhole(File archive, OfflineVoicePackage package) =>
      archive.existsSync() && archive.lengthSync() == package.bytes;

  Future<void> _verify(File downloaded, OfflineVoicePackage package) async {
    final matches =
        downloaded.lengthSync() == package.bytes &&
        (await sha256.bind(downloaded.openRead()).first).toString() ==
            package.sha256;
    if (!matches) throw OfflineVoiceIntegrityException(package.id);
  }

  /// Abre [archive] aparte, busca sus archivos, escribe la ficha y recién
  /// entonces le da su nombre a la carpeta: nunca queda una voz a medias con
  /// el nombre de una entera. El comprimido se borra al final.
  ///
  /// Si falla, se borra lo abierto a medias. El comprimido queda si faltó
  /// lugar —está verificado, y se abre sin volver a bajarlo cuando haya—, y
  /// se borra si el paquete no sirve: no se puede abrir o no trae lo que la
  /// voz necesita. Guardarlo sería ocupar lugar para volver a fallar.
  Future<void> _install(OfflineVoicePackage package, File archive) async {
    final staging = await _stagingOf(package);
    final folder = await _installedFolderOf(package);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    try {
      await _unpacker.unpack(archive, staging);
      final manifest = locateVoiceFiles(staging, package.family);
      File(
        p.join(staging.path, _manifestName),
      ).writeAsStringSync(manifest.encode(), flush: true);
      if (folder.existsSync()) folder.deleteSync(recursive: true);
      staging.renameSync(folder.path);
    } on FileSystemException catch (error) {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      if (_isDiskFull(error)) throw const InsufficientStorageException();
      rethrow;
    } on Object {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      if (archive.existsSync()) archive.deleteSync();
      rethrow;
    }
    if (archive.existsSync()) archive.deleteSync();
  }

  /// `ENOSPC` en Android y Linux; `ERROR_DISK_FULL` y `ERROR_HANDLE_DISK_FULL`
  /// en Windows.
  static bool _isDiskFull(FileSystemException error) =>
      const {28, 39, 112}.contains(error.osError?.errorCode);

  /// Frena la descarga de [package] sin borrar lo bajado (ver [canPause]).
  Future<void> pause(OfflineVoicePackage package) async =>
      _transfer.pause(await _archiveOf(package));

  /// Corta la descarga de [package] y borra lo bajado.
  Future<void> cancel(OfflineVoicePackage package) async {
    final archive = await _archiveOf(package);
    await _transfer.cancel(archive);
    final partial = InAppModelFileTransfer.partialOf(archive);
    if (partial.existsSync()) partial.deleteSync();
    _changes.add(null);
  }

  /// Borra [package] del teléfono: la voz abierta, el comprimido si quedó y
  /// lo bajado a medias. Nada más.
  Future<void> delete(OfflineVoicePackage package) async {
    await cancel(package);
    final archive = await _archiveOf(package);
    if (archive.existsSync()) archive.deleteSync();
    for (final folder in [
      await _installedFolderOf(package),
      await _stagingOf(package),
    ]) {
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    }
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

/// Qué hay adentro de una voz abierta: la carpeta del paquete ([base], la que
/// trae `tokens.txt`) y el nombre de su modelo. Lo demás tiene nombre fijo en
/// sherpa-onnx: `tokens.txt`, `espeak-ng-data/` y, en Kokoro, `voices.bin` y
/// sus léxicos.
@immutable
class OfflineVoiceManifest {
  const OfflineVoiceManifest({required this.base, required this.model});

  factory OfflineVoiceManifest.decode(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    return OfflineVoiceManifest(
      base: map['base']! as String,
      model: map['model']! as String,
    );
  }

  /// Relativa a la carpeta de la voz.
  final String base;
  final String model;

  String encode() => jsonEncode({'base': base, 'model': model});

  @override
  bool operator ==(Object other) =>
      other is OfflineVoiceManifest &&
      other.base == base &&
      other.model == model;

  @override
  int get hashCode => Object.hash(base, model);
}

/// Busca en [folder] —un paquete recién abierto— lo que su motor necesita, y
/// falla con [OfflineVoicePackageException] si falta algo: un paquete sin
/// modelo, o con dos, no se da por bueno.
///
/// Los paquetes de sherpa-onnx traen todo en una carpeta con su nombre
/// (`vits-piper-es_AR-daniela-high/`); no se supone el nombre del modelo
/// (`es_AR-daniela-high.onnx`, `model.int8.onnx`), se busca.
OfflineVoiceManifest locateVoiceFiles(
  Directory folder,
  OfflineVoiceFamily family,
) {
  File? tokens;
  for (final entry in folder.listSync(recursive: true)) {
    if (entry is! File || p.basename(entry.path) != 'tokens.txt') continue;
    if (tokens == null || entry.path.length < tokens.path.length) {
      tokens = entry;
    }
  }
  if (tokens == null) {
    throw const OfflineVoicePackageException('sin tokens.txt');
  }
  final base = tokens.parent;
  final models = [
    for (final entry in base.listSync())
      if (entry is File && entry.path.endsWith('.onnx')) entry,
  ];
  if (models.length != 1) {
    throw OfflineVoicePackageException('${models.length} modelos');
  }
  if (!Directory(p.join(base.path, 'espeak-ng-data')).existsSync()) {
    throw const OfflineVoicePackageException('sin espeak-ng-data');
  }
  if (family == OfflineVoiceFamily.kokoro &&
      !File(p.join(base.path, 'voices.bin')).existsSync()) {
    throw const OfflineVoicePackageException('sin voices.bin');
  }
  return OfflineVoiceManifest(
    base: p.relative(base.path, from: folder.path),
    model: p.basename(models.single.path),
  );
}

/// El paquete de una voz llegó distinto de lo verificado: cortado, o cambiado
/// en el servidor. No se usa.
class OfflineVoiceIntegrityException implements Exception {
  const OfflineVoiceIntegrityException(this.packageId);

  final String packageId;

  @override
  String toString() => 'El paquete $packageId no coincide con el verificado.';
}

/// El paquete de una voz se abrió, pero no trae lo que su motor necesita.
class OfflineVoicePackageException implements Exception {
  const OfflineVoicePackageException(this.detail);

  /// Solo para el registro, nunca para mostrar.
  final String detail;

  @override
  String toString() => 'Paquete de voz incompleto: $detail.';
}
