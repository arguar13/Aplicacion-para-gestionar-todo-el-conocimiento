import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/on_device/device_probe.dart';
import 'package:sinapsis/features/ai_models/data/on_device/on_device_model_files.dart';
import 'package:sinapsis/features/ai_models/data/on_device/prefs_on_device_image_store.dart';
import 'package:sinapsis/features/ai_models/data/on_device/sd_native.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_runtime.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/vault/data/services/disk_space_plus_free_space_probe.dart';

/// `libsinapsis_sd.so`, si la app la trae: solo en Android, y solo si se
/// armó con `-Psinapsis.imagenesEnElTelefono=true` (F43, paso 3b).
final sdNativeLibraryProvider = Provider<SdNativeLibrary?>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  return SdNativeLibrary.open();
});

/// El motor que dibuja en el teléfono, en su isolate; `null` sin la
/// biblioteca. Las pruebas lo sobrescriben con uno de mentira.
final stableDiffusionRuntimeProvider = Provider<StableDiffusionRuntime?>((ref) {
  final library = ref.watch(sdNativeLibraryProvider);
  if (library == null) return null;
  final runtime = IsolateStableDiffusionRuntime(library);
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
});

/// Los archivos de los modelos del teléfono: donde viven los demás modelos,
/// con la misma transferencia (el gestor del sistema en Android, F29).
final onDeviceModelFilesProvider = Provider<OnDeviceModelFiles>((ref) {
  final files = OnDeviceModelFiles(
    transfer: ref.watch(modelFileTransferProvider),
    rootDirectory: ref.watch(modelStorageProvider).root,
  );
  ref.onDispose(() => unawaited(files.dispose()));
  return files;
});

/// Lo que se le pregunta al teléfono: memoria, procesador y el lugar libre
/// donde se bajan los modelos (lo dice el gestor del sistema si está; si no,
/// el volumen de la carpeta de los modelos).
final deviceProbeProvider = Provider<DeviceProbe>((ref) {
  final system = ref.watch(systemDownloadsProvider);
  final storage = ref.watch(modelStorageProvider);
  return SystemDeviceProbe(
    freeBytes: () async {
      if (system != null) return system.freeBytes();
      final root = await storage.root();
      return const DiskSpacePlusFreeSpaceProbe().freeBytesAt(root.path);
    },
  );
});

/// Lo medido y lo apagado de cada modelo del teléfono.
final onDeviceImageStoreProvider = Provider<PrefsOnDeviceImageStore>((ref) {
  final store = PrefsOnDeviceImageStore(
    prefs: ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(() => unawaited(store.dispose()));
  return store;
});

/// El modelo de imágenes del teléfono (ver [StableDiffusionImageEngine]);
/// `null` si la app no trae el motor. Es lo que da
/// `onDeviceImageEngineProvider`.
final stableDiffusionImageEngineProvider =
    Provider<StableDiffusionImageEngine?>((ref) {
      final runtime = ref.watch(stableDiffusionRuntimeProvider);
      if (runtime == null) return null;
      final illustrations = ref.watch(illustrationStoreProvider);
      final engine = StableDiffusionImageEngine(
        runtime: runtime,
        files: ref.watch(onDeviceModelFilesProvider),
        probe: ref.watch(deviceProbeProvider),
        store: ref.watch(onDeviceImageStoreProvider),
        chosenModel: () =>
            illustrations.chosenImageModelOf(kOnDeviceIllustrationAccountId),
        chosenChanges: illustrations.changes(),
        clock: ref.watch(clockProvider),
      );
      unawaited(engine.start());
      ref.onDispose(() => unawaited(engine.dispose()));
      return engine;
    });

/// Lo último leído del teléfono, para las tarjetas; `null` sin motor.
final onDeviceProfileProvider = FutureProvider.autoDispose<DeviceProfile?>((
  ref,
) async {
  ref.watch(onDeviceImageChangesProvider);
  final engine = ref.watch(stableDiffusionImageEngineProvider);
  if (engine == null) return null;
  return engine.cachedProfile ?? await engine.profile(refresh: true);
});

/// La descarga de cada modelo del teléfono, viva aparte de su tarjeta (ver
/// [ModelDownloadNotifier]). NO autoDispose: sigue aunque nadie la mire.
final onDeviceModelDownloadProvider =
    StateNotifierProvider.family<
      ModelDownloadNotifier,
      ModelDownloadState,
      OnDeviceImageModel
    >(
      (ref, model) => ModelDownloadNotifier(
        keeper: modelDownloadKeeper(ref),
        detail: LongWorkDetail.imageModel,
      ),
    );

/// Bajar, pausar, cancelar, borrar, medir y elegir los modelos del teléfono.
final onDeviceImageActionsProvider = Provider<OnDeviceImageActions?>((ref) {
  final engine = ref.watch(stableDiffusionImageEngineProvider);
  if (engine == null) return null;
  return OnDeviceImageActions(
    engine: engine,
    files: ref.watch(onDeviceModelFilesProvider),
    download: (model) =>
        ref.read(onDeviceModelDownloadProvider(model).notifier),
    choose: (model) => ref
        .read(illustrationStoreProvider)
        .chooseImageModel(kOnDeviceIllustrationAccountId, model?.spec.id),
  );
});

class OnDeviceImageActions {
  OnDeviceImageActions({
    required StableDiffusionImageEngine engine,
    required OnDeviceModelFiles files,
    required ModelDownloadNotifier Function(OnDeviceImageModel model) download,
    required Future<void> Function(OnDeviceImageModel? model) choose,
  }) : _engine = engine,
       _files = files,
       _download = download,
       _choose = choose;

  final StableDiffusionImageEngine _engine;
  final OnDeviceModelFiles _files;
  final ModelDownloadNotifier Function(OnDeviceImageModel model) _download;
  final Future<void> Function(OnDeviceImageModel? model) _choose;

  /// Si se puede pausar una descarga (ver `ModelFileTransfer.canPause`).
  bool get canPause => _files.canPause;

  /// «Bajar» (o «Seguir», si estaba pausada: retoma desde donde quedó).
  bool download(OnDeviceImageModel model) =>
      _download(model).start(() => _files.download(model));

  Future<void> pause(OnDeviceImageModel model) =>
      _download(model).pause(() => _files.pause(model));

  /// Corta la descarga y borra lo bajado: la que corre o la pausada.
  Future<void> cancel(OnDeviceImageModel model) async {
    final notifier = _download(model);
    await notifier.cancel(() => _files.cancel(model));
    // Pausada no corre nada, pero queda lo bajado a medias.
    await _files.cancel(model);
    notifier.clearError();
  }

  /// «Borrar»: el archivo del modelo, nada más. Si era el elegido, se vuelve
  /// a elegir solo.
  Future<void> delete(OnDeviceImageModel model) async {
    await _engine.releaseNow();
    await _files.delete(model);
    if (_engine.chosenModel == model) await _choose(null);
  }

  /// «Usar este» para las ilustraciones.
  Future<void> use(OnDeviceImageModel model) => _choose(model);

  /// «Medir en mi teléfono» (y «Probar de nuevo», si quedó apagado).
  Future<OnDeviceMeasurement> measure(
    OnDeviceImageModel model, {
    CancelToken? cancel,
  }) => _engine.measure(model, cancel: cancel);

  /// Cuánto quedó de una descarga pausada, para mostrarlo.
  Future<double?> pausedProgress(OnDeviceImageModel model) =>
      _files.pausedProgress(model);
}
