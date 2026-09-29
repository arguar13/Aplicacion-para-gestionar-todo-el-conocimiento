import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// [LongWorkKeeper] sobre el servicio en primer plano de Android
/// (`LongWorkService`), por un canal de método.
///
/// Solo le habla a Android cuando algo cambia —otro porcentaje, empezar,
/// terminar—: el avance llega página por página, y una notificación que se
/// redibuja cientos de veces por minuto gasta batería sin decir nada nuevo.
///
/// Soltar espera un momento ([releaseDelay]): entre un trabajo largo y el
/// siguiente de la cola hay un instante sin ninguno, y apagar el servicio
/// ahí obligaría a volver a prenderlo —algo que Android no deja hacer si la
/// app está en segundo plano—.
class PlatformLongWorkKeeper implements LongWorkKeeper {
  PlatformLongWorkKeeper({
    required AppLogger logger,
    MethodChannel channel = const MethodChannel('app.sinapsis/long_work'),
    this.releaseDelay = const Duration(seconds: 15),
  }) : _logger = logger,
       _channel = channel;

  final AppLogger _logger;
  final MethodChannel _channel;
  final Duration releaseDelay;

  var _working = false;
  int? _lastPercent;
  Timer? _release;

  @override
  void working({required int done, required int total}) {
    _release?.cancel();
    _release = null;

    final percent = total <= 0 ? -1 : (done * 100 ~/ total).clamp(0, 100);
    if (_working && percent == _lastPercent) return;
    _working = true;
    _lastPercent = percent;
    unawaited(_invoke('working', {'done': done, 'total': total}));
  }

  @override
  void idle() {
    if (!_working || _release != null) return;
    _release = Timer(releaseDelay, () {
      _release = null;
      _working = false;
      _lastPercent = null;
      unawaited(_invoke('idle'));
    });
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
