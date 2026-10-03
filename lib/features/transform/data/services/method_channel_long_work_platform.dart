import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// [LongWorkPlatform] sobre el servicio en primer plano de Android
/// (`LongWorkService`), por un canal de método. Le dice de quién es el
/// trabajo (`kind`) y qué se hace (`detail`), para que la notificación lo
/// diga —procesar, bajar el modelo de lenguaje, ordenar la biblioteca con el
/// cargador—, y con qué tipos tiene que correr el servicio (`types`).
///
/// Por el mismo canal, Android avisa si cortó el servicio por su cuenta
/// (`timedOut`): ver [stoppedBySystem].
class MethodChannelLongWorkPlatform implements LongWorkPlatform {
  MethodChannelLongWorkPlatform({
    required AppLogger logger,
    MethodChannel channel = const MethodChannel('app.sinapsis/long_work'),
  }) : _logger = logger,
       _channel = channel {
    _channel.setMethodCallHandler(_fromAndroid);
  }

  final AppLogger _logger;
  final MethodChannel _channel;
  final _stops = StreamController<void>.broadcast();

  /// Cómo se llama cada dueño del otro lado del canal.
  static String kindOf(LongWorkOwner owner) => switch (owner) {
    LongWorkOwner.processing => 'processing',
    LongWorkOwner.modelDownload => 'model_download',
    LongWorkOwner.audioDownload => 'audio_download',
    LongWorkOwner.aiOrganize => 'organizing',
    LongWorkOwner.sampleLibrary => 'sample_library',
  };

  /// Cómo se llama cada tipo del otro lado: el nombre del tipo de servicio
  /// de Android.
  static String typeOf(LongWorkKind kind) => switch (kind) {
    LongWorkKind.dataSync => 'data_sync',
    LongWorkKind.mediaProcessing => 'media_processing',
  };

  @override
  Future<void> show(LongWorkNotice notice) => _invoke('working', {
    'kind': kindOf(notice.owner),
    'done': notice.done,
    'total': notice.total,
    'detail': ?notice.detail,
    'types': [for (final kind in notice.kinds) typeOf(kind)],
  });

  @override
  Future<void> stop() => _invoke('idle');

  @override
  Stream<void> get stoppedBySystem => _stops.stream;

  Future<void> _fromAndroid(MethodCall call) async {
    if (call.method != 'timedOut') {
      throw MissingPluginException('Sin ${call.method} en el trabajo largo.');
    }
    final type = (call.arguments as Map<Object?, Object?>?)?['type'];
    _logger.warning(
      'Android cortó el servicio en primer plano: se acabaron las horas del '
      'tipo $type. El trabajo sigue sin protección hasta volver a la app.',
    );
    _stops.add(null);
  }

  Future<void> _invoke(String method, [Map<String, Object>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      // Sin el servicio el trabajo sigue igual, solo sin la garantía de que
      // el sistema no congele la app: no es motivo para cortarlo.
      _logger.warning('No se pudo avisar el trabajo largo ($method): $e');
    } on MissingPluginException {
      // Una plataforma sin el canal: no hay nada que mantener vivo.
    }
  }
}
