import 'package:flutter/services.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// [LongWorkPlatform] sobre el servicio en primer plano de Android
/// (`LongWorkService`), por un canal de método. Le dice de quién es el
/// trabajo (`kind`), para que la notificación diga lo que se está haciendo:
/// procesar, organizar la biblioteca con el cargador (F27) o, en desarrollo,
/// cargar la biblioteca de ejemplo.
class MethodChannelLongWorkPlatform implements LongWorkPlatform {
  MethodChannelLongWorkPlatform({
    required AppLogger logger,
    MethodChannel channel = const MethodChannel('app.sinapsis/long_work'),
  }) : _logger = logger,
       _channel = channel;

  final AppLogger _logger;
  final MethodChannel _channel;

  /// Cómo se llama cada dueño del otro lado del canal.
  static String kindOf(LongWorkOwner owner) => switch (owner) {
    LongWorkOwner.processing => 'processing',
    LongWorkOwner.aiOrganize => 'organizing',
    LongWorkOwner.sampleLibrary => 'sample_library',
  };

  @override
  Future<void> show(LongWorkNotice notice) => _invoke('working', {
    'kind': kindOf(notice.owner),
    'done': notice.done,
    'total': notice.total,
  });

  @override
  Future<void> stop() => _invoke('idle');

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
