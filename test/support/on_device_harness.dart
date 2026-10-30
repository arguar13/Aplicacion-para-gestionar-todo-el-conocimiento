import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/ai_models/data/on_device/device_probe.dart';
import 'package:sinapsis/features/ai_models/data/on_device/on_device_model_files.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_runtime.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/on_device_image_providers.dart';

/// Lo de mentira para el modelo de imágenes del teléfono (F43, paso 3b): el
/// teléfono, la descarga y el motor nativo. Nada sale a internet ni carga
/// una biblioteca nativa.

const kGiB = 1 << 30;

/// Lo que «se baja» de cada modelo en las pruebas: unos bytes con su huella,
/// en vez de 1 o 2 GB.
String fakeModelContent(OnDeviceImageModel model) =>
    'modelo de prueba ${model.spec.id}';

/// La ficha de [model] con el archivo chico de [fakeModelContent].
OnDeviceModelSpec fakeSpecOf(OnDeviceImageModel model) {
  final bytes = utf8.encode(fakeModelContent(model));
  final real = model.spec;
  return OnDeviceModelSpec(
    id: real.id,
    displayName: real.displayName,
    officialRepo: real.officialRepo,
    downloadRepo: real.downloadRepo,
    commit: real.commit,
    fileName: real.fileName,
    bytes: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    license: real.license,
    steps: real.steps,
    cfg: real.cfg,
    minRamGb: real.minRamGb,
    recommendedRamGb: real.recommendedRamGb,
    estimatedSecondsPerImage: real.estimatedSecondsPerImage,
  );
}

/// Un teléfono Android de 64 bits con [ramGb] GB (como lo ve el sistema: un
/// poco menos) y [freeGb] libres.
DeviceProfile phoneWith({
  int? ramGb = 12,
  int? freeGb = 40,
  bool android = true,
  bool arm64 = true,
  bool? cpu = true,
}) => DeviceProfile(
  android: android,
  arm64: arm64,
  cpuSupported: cpu,
  // El sistema ve algo menos de lo que dice la ficha.
  totalRamBytes: ramGb == null ? null : (ramGb * kGiB * 0.93).round(),
  freeStorageBytes: freeGb == null ? null : freeGb * kGiB,
);

class FakeDeviceProbe implements DeviceProbe {
  FakeDeviceProbe([DeviceProfile? profile]) : profile = profile ?? phoneWith();

  DeviceProfile profile;
  int reads = 0;

  @override
  Future<DeviceProfile> read() async {
    reads++;
    return profile;
  }
}

/// Una descarga en curso de [FakeModelTransfer].
class FakeFetch {
  FakeFetch(this.target, this.verify, this.onProgress, this.expectedBytes);

  final File target;
  final Future<void> Function(File whole)? verify;
  final void Function(int received, int? total)? onProgress;
  final int? expectedBytes;
  final done = Completer<int>();
  bool paused = false;
}

/// Una transferencia de mentira que se maneja desde la prueba: avanza,
/// termina, pausa o falla cuando se le dice, y escribe en el disco lo que
/// escribiría la de verdad (`<destino>.descargando` mientras baja).
class FakeModelTransfer implements ModelFileTransfer {
  FakeModelTransfer({
    this.canPause = true,
    this.continuesWithAppClosed = false,
  });

  @override
  final bool canPause;

  @override
  final bool continuesWithAppClosed;

  final fetches = <String, FakeFetch>{};
  final urls = <String>[];
  final labels = <String?>[];

  /// Si se pone, `fetch` falla con esto en el acto.
  Object? failWith;

  @override
  Future<int> fetch({
    required String url,
    required File target,
    Map<String, String> headers = const {},
    int? expectedBytes,
    String? label,
    Future<void> Function(File whole)? verify,
    void Function(int received, int? total)? onProgress,
  }) {
    urls.add(url);
    labels.add(label);
    if (failWith case final error?) return Future.error(error);
    final fetch = FakeFetch(target, verify, onProgress, expectedBytes);
    fetches[target.path] = fetch;
    return fetch.done.future;
  }

  FakeFetch fetchOf(String fileName) =>
      fetches.values.lastWhere((f) => f.target.path.endsWith(fileName));

  /// Lo bajado hasta ahora: [received] de lo que pesa.
  void progress(String fileName, int received) {
    final fetch = fetchOf(fileName);
    final partial = InAppModelFileTransfer.partialOf(fetch.target);
    partial.parent.createSync(recursive: true);
    partial.writeAsBytesSync(Uint8List(received));
    fetch.onProgress?.call(received, fetch.expectedBytes);
  }

  /// Termina con [content] (lo verificado, si no se dice otra cosa): pasa
  /// por la comprobación y toma su nombre definitivo, o se borra.
  Future<void> finish(String fileName, String content) =>
      finishBytes(fileName, utf8.encode(content));

  /// Lo mismo que [finish], con un archivo binario: un paquete comprimido
  /// (F47, paso 3).
  Future<void> finishBytes(String fileName, List<int> content) async {
    final fetch = fetchOf(fileName);
    final partial = InAppModelFileTransfer.partialOf(fetch.target);
    partial.parent.createSync(recursive: true);
    partial.writeAsBytesSync(content);
    try {
      await fetch.verify?.call(partial);
    } on Object catch (error) {
      if (partial.existsSync()) partial.deleteSync();
      fetch.done.completeError(error);
      fetches.remove(fetch.target.path);
      return;
    }
    partial.renameSync(fetch.target.path);
    fetches.remove(fetch.target.path);
    fetch.done.complete(content.length);
  }

  @override
  Future<bool> isInFlight(File target) async =>
      fetches.containsKey(target.path);

  @override
  Future<void> pause(File target) async {
    final fetch = fetches.remove(target.path);
    if (fetch == null) return;
    fetch.done.completeError(const ModelDownloadPausedException());
  }

  @override
  Future<void> cancel(File target) async {
    final fetch = fetches.remove(target.path);
    fetch?.done.completeError(const ModelDownloadCancelledException());
    final partial = InAppModelFileTransfer.partialOf(target);
    if (partial.existsSync()) partial.deleteSync();
  }
}

/// El motor de mentira: «dibuja» un PNG chico, o falla como se le diga.
class FakeStableDiffusionRuntime implements StableDiffusionRuntime {
  final jobs = <StableDiffusionJob>[];
  int cancels = 0;
  int releases = 0;
  var _loaded = false;

  /// Lo que tarda cada imagen y la carga, según lo «medido».
  Duration drawTime = const Duration(seconds: 17);
  Duration loadTime = const Duration(seconds: 4);

  /// Si se pone, `generate` falla con esto.
  StableDiffusionFailure? failure;

  /// Si se pone, `generate` espera esto antes de contestar.
  Completer<void>? gate;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<StableDiffusionImage> generate(StableDiffusionJob job) async {
    jobs.add(job);
    final loads = !_loaded;
    _loaded = true;
    if (gate case final gate?) await gate.future;
    if (failure case final failure?) {
      throw StableDiffusionException(failure);
    }
    return StableDiffusionImage(
      png: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
      width: job.width,
      height: job.height,
      drawTime: drawTime,
      loadTime: loads ? loadTime : null,
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (gate case final gate? when !gate.isCompleted) {
      failure = StableDiffusionFailure.cancelled;
      gate.complete();
    }
  }

  @override
  Future<void> release() async {
    releases++;
    _loaded = false;
  }
}

/// Lo de mentira, armado: el teléfono, la descarga, el motor y la carpeta
/// donde «se bajan» los modelos.
class OnDeviceFakes {
  OnDeviceFakes({
    required this.root,
    DeviceProfile? phone,
    bool canPause = true,
    bool systemDownload = false,
  }) : probe = FakeDeviceProbe(phone),
       transfer = FakeModelTransfer(
         canPause: canPause,
         continuesWithAppClosed: systemDownload,
       );

  final Directory root;
  final FakeDeviceProbe probe;
  final FakeModelTransfer transfer;
  final runtime = FakeStableDiffusionRuntime();

  late final files = OnDeviceModelFiles(
    transfer: transfer,
    rootDirectory: () async => root,
    specOf: fakeSpecOf,
  );

  /// Dónde queda [model] entero.
  File fileOf(OnDeviceImageModel model) => File(
    '${root.path}${Platform.pathSeparator}modelos'
    '${Platform.pathSeparator}imagenes'
    '${Platform.pathSeparator}${model.spec.fileName}',
  );

  /// Deja [model] bajado y verificado, sin pasar por la descarga.
  void placeDownloaded(OnDeviceImageModel model) {
    final file = fileOf(model);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(fakeModelContent(model));
  }

  List<Override> get overrides => [
    stableDiffusionRuntimeProvider.overrideWithValue(runtime),
    deviceProbeProvider.overrideWithValue(probe),
    onDeviceModelFilesProvider.overrideWithValue(files),
  ];
}
