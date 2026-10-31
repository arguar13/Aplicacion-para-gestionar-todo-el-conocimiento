import 'dart:async';

import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';

/// Un solo [TextToSpeechService] para el lector, con los motores detrás (F47,
/// pasos 3 y 4): el del sistema, el sin conexión y el de las voces propias en
/// la nube. Cada voz dice con cuál lee ([NarrationVoice.engine]); el lector no
/// sabe que son varios.
///
/// - Elegir una voz de otro motor corta el que sonaba: nunca suenan dos.
/// - [events] y [progress] traen solo lo del motor de la voz elegida: un
///   «terminó» tardío de otro no hace pasar al lector de oración.
/// - Donde no hay un motor —el sin conexión, el de la nube—, una voz suya no
///   se puede elegir —la biblioteca no la ofrece—, y si quedó elegida de
///   antes, lee la del sistema.
class RoutingTextToSpeechService implements TextToSpeechService {
  RoutingTextToSpeechService({
    required TextToSpeechService system,
    TextToSpeechService? offline,
    TextToSpeechService? cloud,
  }) : _system = system,
       _offline = offline,
       _cloud = cloud,
       _active = system {
    _subscriptions = [
      for (final engine in [system, ?offline, ?cloud]) ...[
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
  final TextToSpeechService? _cloud;
  TextToSpeechService _active;
  late final List<StreamSubscription<Object>> _subscriptions;

  final _events = StreamController<NarrationEvent>.broadcast();
  final _progress = StreamController<int>.broadcast();

  /// Las voces del teléfono: las sin conexión salen del catálogo y las
  /// propias de Mías, no de un motor.
  @override
  Future<List<NarrationVoice>> getVoices() => _system.getVoices();

  /// El motor de [voice], o `null` si no está en este dispositivo.
  TextToSpeechService? _engineOf(NarrationVoice? voice) =>
      switch (voice?.engine) {
        NarrationEngine.offline => _offline,
        NarrationEngine.cloud => _cloud,
        NarrationEngine.system || null => _system,
      };

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    final own = _engineOf(voice);
    final next = own ?? _system;
    if (!identical(next, _active)) {
      final previous = _active;
      _active = next;
      await previous.stop();
    }
    // Una voz de un motor que no está: la del sistema.
    await next.setVoice(own == null ? null : voice);
  }

  /// La velocidad vale para todos: cambiar de voz no la cambia.
  @override
  Future<void> setSpeed(double speed) async {
    await _system.setSpeed(speed);
    await _offline?.setSpeed(speed);
    await _cloud?.setSpeed(speed);
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

  /// Suelta lo suyo; los motores son de quien los armó.
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
    await _progress.close();
  }
}
