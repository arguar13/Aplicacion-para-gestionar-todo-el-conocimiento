import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/on_device_image_engine.dart';
import 'package:sinapsis/features/ai_models/data/on_device/device_probe.dart';
import 'package:sinapsis/features/ai_models/data/on_device/on_device_model_files.dart';
import 'package:sinapsis/features/ai_models/data/on_device/prefs_on_device_image_store.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_runtime.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/domain/services/on_device_verdict.dart';

/// La descripción de «Medir en mi teléfono»: una ilustración simple, como las
/// que va a dibujar.
const kOnDeviceMeasurePrompt =
    'Una lamparita amarilla sobre fondo celeste, ilustración plana y simple.';

/// Cuánto se deja el modelo en la memoria sin dibujar antes de soltarlo:
/// lo bastante para las ilustraciones de una misma creación —una detrás de
/// otra, sin volver a cargarlo—, y lo bastante poco para no dejar 1 o 2 GB
/// ocupados mientras se hace otra cosa.
const kOnDeviceReleaseAfter = Duration(minutes: 2);

/// El modelo de imágenes del teléfono (F43, paso 3b): SDXS-512 o SD-Turbo con
/// stable-diffusion.cpp, en el procesador, a 512 px.
///
/// - **Con qué modelo dibuja** ([activeModel]): el que eligió la persona, si
///   está bajado y el teléfono puede; si no, el mejor de los bajados que el
///   teléfono puede (SD-Turbo solo si le sobra memoria); sin ninguno bajado,
///   el que habría que bajar primero (SDXS, el más liviano).
/// - **Si puede** ([readiness]): lo dice [onDeviceVerdict] con lo que se lee
///   del teléfono, más si está bajado.
/// - **Cuánto tarda** ([estimatedTimePerImage]): lo medido con
///   [measure] o, hasta medirlo, lo estimado de su ficha.
/// - **Si el teléfono no da**: sin memoria, o la app se cerró mientras
///   dibujaba (lo sabe la marca de «dibujando» que deja
///   `PrefsOnDeviceImageStore`), el modelo se apaga solo y lo dice; nunca
///   deja una creación a medias, porque la falla llega como
///   [ImageGenerationException] y la ilustración queda con su lugar dibujado.
///
/// Dibuja de a una imagen, fuera del isolate de la pantalla
/// ([StableDiffusionRuntime]), y suelta el modelo de la memoria pasado
/// [releaseAfter] sin dibujar o cuando Android avisa que falta ([releaseNow]).
class StableDiffusionImageEngine implements OnDeviceImageEngine {
  StableDiffusionImageEngine({
    required StableDiffusionRuntime runtime,
    required OnDeviceModelFiles files,
    required DeviceProbe probe,
    required PrefsOnDeviceImageStore store,
    required String? Function() chosenModel,
    required Stream<void> chosenChanges,
    required Clock clock,
    this.releaseAfter = kOnDeviceReleaseAfter,
  }) : _runtime = runtime,
       _files = files,
       _probe = probe,
       _store = store,
       _chosenModel = chosenModel,
       _clock = clock {
    _subscriptions = [
      for (final stream in [files.changes(), store.changes(), chosenChanges])
        stream.listen((_) => _changes.add(null)),
    ];
  }

  final StableDiffusionRuntime _runtime;
  final OnDeviceModelFiles _files;
  final DeviceProbe _probe;
  final PrefsOnDeviceImageStore _store;
  final String? Function() _chosenModel;
  final Clock _clock;

  /// Ver [kOnDeviceReleaseAfter].
  final Duration releaseAfter;

  final _changes = StreamController<void>.broadcast();
  late final List<StreamSubscription<void>> _subscriptions;

  /// Lo último leído del teléfono: lo que no puede esperar ([displayName],
  /// [activeModel]) usa esto.
  DeviceProfile? _profile;

  Timer? _releaseTimer;

  /// De a una imagen: la marca de «dibujando» cubre exactamente la que se
  /// está dibujando.
  Future<void> _turn = Future.value();

  @override
  IllustrationProvider get provider => IllustrationProvider.onDevice;

  @override
  Stream<void> changes() => _changes.stream;

  /// Al abrir la app: resuelve la carpeta de los modelos y, si la app se
  /// cerró dibujando la vez anterior, apaga ese modelo.
  Future<void> start() async {
    await _files.prepare();
    await _store.recoverFromClosedDrawing();
    await profile(refresh: true);
    _changes.add(null);
  }

  /// Lo que se sabe del teléfono; [refresh] lo vuelve a leer (el lugar libre
  /// cambia).
  Future<DeviceProfile> profile({bool refresh = false}) async {
    if (!refresh && _profile != null) return _profile!;
    final read = await _probe.read();
    if (read != _profile) {
      _profile = read;
      _changes.add(null);
    }
    return read;
  }

  /// Lo último leído del teléfono, sin esperar; `null` si nunca se leyó.
  DeviceProfile? get cachedProfile => _profile;

  bool isDownloaded(OnDeviceImageModel model) => _files.isDownloadedSync(model);

  OnDeviceMeasurement? measurementOf(OnDeviceImageModel model) =>
      _store.measurementOf(model);

  /// Si la app se cerró dibujando con [model] y quedó apagado.
  bool isClosed(OnDeviceImageModel model) => _store.closedOf(model) != null;

  /// El veredicto de [model] con lo último leído del teléfono (o con
  /// [device]). Sin nada leído todavía, «justo»: no se sabe.
  OnDeviceVerdict verdictOf(OnDeviceImageModel model, {DeviceProfile? device}) {
    final profile = device ?? _profile;
    if (profile == null) {
      return OnDeviceVerdict(OnDeviceVerdictLevel.tight, [
        RamFacts(
          ramGb: null,
          minGb: model.spec.minRamGb,
          recommendedGb: model.spec.recommendedRamGb,
        ),
      ]);
    }
    return onDeviceVerdict(
      model,
      profile,
      downloaded: isDownloaded(model),
      closedLastTime: isClosed(model),
    );
  }

  /// El modelo que eligió la persona, si eligió uno.
  OnDeviceImageModel? get chosenModel =>
      OnDeviceImageModel.byId(_chosenModel());

  /// Con qué modelo dibujaría ahora (ver la clase).
  OnDeviceImageModel get activeModel {
    final fitting = [
      for (final model in OnDeviceImageModel.values)
        if (!verdictOf(model).cannot) model,
    ];
    final downloaded = [
      for (final model in fitting)
        if (isDownloaded(model)) model,
    ];
    final chosen = chosenModel;
    if (chosen != null && downloaded.contains(chosen)) return chosen;
    if (downloaded.length > 1) {
      final turbo = verdictOf(OnDeviceImageModel.sdTurbo);
      return turbo.level == OnDeviceVerdictLevel.can
          ? OnDeviceImageModel.sdTurbo
          : OnDeviceImageModel.sdxs;
    }
    if (downloaded.isNotEmpty) return downloaded.single;
    return fitting.firstOrNull ?? OnDeviceImageModel.sdxs;
  }

  @override
  String get displayName => activeModel.spec.displayName;

  @override
  Future<OnDeviceImageReadiness> readiness() async {
    await profile(refresh: true);
    final model = activeModel;
    final verdict = verdictOf(model);
    if (verdict.cannot) {
      return OnDeviceImageReadiness.notReady(verdict.failure!);
    }
    if (!isDownloaded(model)) {
      return OnDeviceImageReadiness.notReady(
        ImageFailure.modelNotDownloaded,
        downloadBytes: model.spec.bytes,
      );
    }
    return const OnDeviceImageReadiness.ready();
  }

  @override
  Duration estimatedTimePerImage(IllustrationSize size) =>
      timePerImageOf(activeModel);

  /// Lo que tarda [model] por imagen: lo medido o lo estimado. Siempre a 512
  /// px: el tamaño pedido no cambia lo que dibuja en el teléfono.
  Duration timePerImageOf(OnDeviceImageModel model) =>
      measurementOf(model)?.perImage ??
      Duration(seconds: model.spec.estimatedSecondsPerImage);

  @override
  bool get timeMeasured => measurementOf(activeModel) != null;

  static ImageModelInfo _infoOf(OnDeviceImageModel model) =>
      ImageModelInfo(id: model.spec.id, displayName: model.spec.displayName);

  /// Los bajados que este teléfono puede usar.
  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    await profile(refresh: true);
    return [
      for (final model in OnDeviceImageModel.values)
        if (isDownloaded(model) && !verdictOf(model).cannot) _infoOf(model),
    ];
  }

  @override
  String? recommendedImageModel(List<ImageModelInfo> models) {
    if (models.isEmpty) return null;
    final active = activeModel.spec.id;
    return models.any((m) => m.id == active) ? active : models.first.id;
  }

  @override
  Future<GeneratedImage> generate(
    ImageWireRequest request,
    ImageWireAccess access, {
    CancelToken? cancel,
  }) async {
    final model = OnDeviceImageModel.byId(request.model);
    if (model == null) {
      throw ImageGenerationException(
        ImageFailure.modelNotFound,
        detail: 'Sin modelo del teléfono «${request.model}»',
      );
    }
    final pixels = pixelsOf(request.aspect, IllustrationSize.small);
    final image = await _draw(
      model,
      prompt: request.prompt,
      width: pixels.width,
      height: pixels.height,
      cancel: cancel,
    );
    return GeneratedImage(
      bytes: image.png,
      mimeType: 'image/png',
      model: model.spec.id,
    );
  }

  /// «Medir en mi teléfono»: dibuja una imagen de prueba de 512 × 512 con
  /// [model], cargándolo de cero, y guarda cuánto tardó en cargar y en
  /// dibujar. Si quedó apagado porque la app se cerró, lo vuelve a encender
  /// para probar. Falla con [ImageGenerationException].
  Future<OnDeviceMeasurement> measure(
    OnDeviceImageModel model, {
    CancelToken? cancel,
  }) async {
    if (isClosed(model)) await _store.clearClosed(model);
    // Que cargue de cero: lo medido incluye la carga, aparte.
    await _runtime.release();
    final image = await _draw(
      model,
      prompt: kOnDeviceMeasurePrompt,
      width: 512,
      height: 512,
      cancel: cancel,
    );
    final measurement = OnDeviceMeasurement(
      perImage: image.drawTime,
      load: image.loadTime,
      measuredAt: _clock().toUtc(),
    );
    await _store.setMeasurement(model, measurement);
    return measurement;
  }

  Future<StableDiffusionImage> _draw(
    OnDeviceImageModel model, {
    required String prompt,
    required int width,
    required int height,
    CancelToken? cancel,
  }) {
    final result = _turn.then((_) async {
      final device = await profile(refresh: true);
      final verdict = verdictOf(model, device: device);
      if (verdict.cannot) {
        throw ImageGenerationException(verdict.failure!);
      }
      final file = await _files.fileOf(model);
      if (!await _files.isDownloaded(model)) {
        throw const ImageGenerationException(ImageFailure.modelNotDownloaded);
      }
      if (cancel?.isCancelled ?? false) {
        throw const ImageGenerationException(ImageFailure.cancelled);
      }
      _releaseTimer?.cancel();
      await _store.markDrawing(model, _clock());
      final whenCancelled = cancel?.whenCancel.then((_) => _runtime.cancel());
      try {
        return await _runtime.generate(
          StableDiffusionJob(
            modelPath: file.path,
            prompt: prompt,
            width: width,
            height: height,
            steps: model.spec.steps,
            cfg: model.spec.cfg,
          ),
        );
      } on StableDiffusionException catch (error) {
        final failure = imageFailureOfRuntime(error.failure);
        if (failure == ImageFailure.notEnoughMemory) {
          // Lo mismo que si Android la hubiera cerrado: se apaga solo.
          await _store.markClosed(model, _clock());
          await _runtime.release();
        }
        throw ImageGenerationException(failure, detail: error.detail);
      } finally {
        unawaited(whenCancelled);
        await _store.clearDrawing();
        _scheduleRelease();
      }
    });
    _turn = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(releaseAfter, () => unawaited(_runtime.release()));
  }

  /// Saca el modelo de la memoria ya: Android avisa que falta, o la app se
  /// fue a segundo plano un rato. Si está dibujando, espera a que termine.
  Future<void> releaseNow() async {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    await _turn;
    if (_runtime.isLoaded) await _runtime.release();
  }

  Future<void> dispose() async {
    _releaseTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }
}

/// La falla de imagen que corresponde a una del motor.
ImageFailure imageFailureOfRuntime(StableDiffusionFailure failure) =>
    switch (failure) {
      StableDiffusionFailure.unavailable => ImageFailure.unsupportedDevice,
      StableDiffusionFailure.memory => ImageFailure.notEnoughMemory,
      StableDiffusionFailure.cancelled => ImageFailure.cancelled,
      StableDiffusionFailure.arguments => ImageFailure.badRequest,
      StableDiffusionFailure.generate => ImageFailure.noImage,
      // El archivo está con su tamaño pero el motor no lo entiende.
      StableDiffusionFailure.load => ImageFailure.unknown,
    };
