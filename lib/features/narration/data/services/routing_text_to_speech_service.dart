import 'dart:async';

import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// Un solo [TextToSpeechService] para el lector, con los dos motores detrás
/// (F47, paso 3): el del sistema y el sin conexión. Cada voz dice con cuál
/// lee ([NarrationVoice.engine]); el lector no sabe que son dos.
///
/// - Elegir una voz de otro motor corta el que sonaba: nunca suenan los dos.
/// - [events] y [progress] traen solo lo del motor de la voz elegida: un
///   «terminó» tardío del otro no hace pasar al lector de oración.
/// - Donde no hay motor sin conexión, una voz sin conexión
///   no se puede elegir —la biblioteca no la ofrece—, y si quedó elegida de
///   antes, lee la del sistema.
class RoutingTextToSpeechService implements TextToSpeechService {
  RoutingTextToSpeechService({
    required TextToSpeechService system,
    TextToSpeechService? offline,
  }) : _system = system,
       _offline = offline,
       _active = system {
    _subscriptions = [
      for (final engine in [system, ?offline]) ...[
        engine.events.listen((event) {
          if (identical(engine, _active)) _events.add(event);
        }),
        engine.progress.listen((offset) {
          if (identical(engine, _active)) _progress.add(offset);
        }),
      ],
    ];
  }

  final TextToSpeechService _system;
  final TextToSpeechService? _offline;
  TextToSpeechService _active;
  late final List<StreamSubscription<Object>> _subscriptions;

  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  /// Las voces del teléfono: las sin conexión salen del catálogo, no de un
  /// motor.
  @override
  Future<List<NarrationVoice>> getVoices() => _system.getVoices();

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    final offline = _offline;
    final next = voice?.engine == NarrationEngine.offline && offline != null
        ? offline
        : _system;
    if (!identical(next, _active)) {
      final previous = _active;
      _active = next;
      await previous.stop();
    }
    // Una voz sin conexión donde no hay motor sin conexión: la del sistema.
    await next.setVoice(
      identical(next, _system) && _isOffline(voice) ? null : voice,
    );
  }

  static bool _isOffline(NarrationVoice? voice) =>
      voice?.engine == NarrationEngine.offline;

  /// La velocidad vale para los dos: cambiar de voz no la cambia.
  @override
  Future<void> setSpeed(double speed) async {
    await _system.setSpeed(speed);
    await _offline?.setSpeed(speed);
  }

  @override
  Future<void> speak(String text) => _active.speak(text);

  @override
  Future<void> prepare(String text) => _active.prepare(text);

  @override
  Future<void> stop() => _active.stop();

  @override
  Stream<NarrationEvent> get events => _events.stream;

  @override
  Stream<int> get progress => _progress.stream;

  /// Suelta lo suyo; los dos motores son de quien los armó.
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
    await _progress.close();
  }
}
