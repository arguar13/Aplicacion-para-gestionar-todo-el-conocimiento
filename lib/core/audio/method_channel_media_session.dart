import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/core/audio/media_session.dart';

/// [MediaSessionPlatform] en Android, por el canal `app.sinapsis/media_session`
/// (ver `MediaSessionChannel` y `MediaPlaybackService`): una `MediaSession`
/// del sistema, con su tarjeta, el servicio en primer plano de tipo
/// «reproducción de medios», el foco de audio y los auriculares. Sin
/// dependencias nuevas: es la sesión de medios del propio Android.
///
/// Del lado nativo llegan dos mensajes: `command` —lo que se tocó en la
/// tarjeta, los auriculares o el reloj— e `interruption` —una llamada, otra
/// app, los auriculares desconectados—.
///
/// Si del otro lado no hay nada que conteste —una prueba, un motor sin los
/// canales de la app—, la tarjeta deja de intentarse: lo que suena sigue
/// sonando igual.
class MethodChannelMediaSession implements MediaSessionPlatform {
  MethodChannelMediaSession({
    MethodChannel channel = const MethodChannel('app.sinapsis/media_session'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _commands = StreamController<MediaCommand>.broadcast();
  final _interruptions = StreamController<MediaInterruption>.broadcast();
  var _available = true;

  @override
  bool get isSupported => true;

  @override
  Future<void> update(MediaSessionState state) => _invoke('update', {
    'title': state.title,
    'subtitle': state.subtitle,
    'positionMs': state.position.inMilliseconds,
    'durationMs': state.duration.inMilliseconds,
    'playing': state.playing,
    'hasNext': state.hasNext,
    'focus': state.requestsAudioFocus,
    'artwork': state.artwork,
  });

  @override
  Future<void> end() => _invoke('end');

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Stream<MediaInterruption> get interruptions => _interruptions.stream;

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _available = false;
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    final arguments = call.arguments;
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    switch (call.method) {
      case 'command':
        final command = commandFrom(map);
        if (command != null) _commands.add(command);
        return null;
      case 'interruption':
        final interruption = interruptionFrom(map);
        if (interruption != null) _interruptions.add(interruption);
        return null;
    }
    throw MissingPluginException('Método desconocido: ${call.method}');
  }

  /// Lo que se tocó, como lo manda el lado nativo: `{name, ms}`.
  static MediaCommand? commandFrom(Map<Object?, Object?> map) {
    final ms = map['ms'];
    final at = ms is int ? Duration(milliseconds: ms) : null;
    return switch (map['name']) {
      'play' => const MediaPlay(),
      'pause' => const MediaPause(),
      'skip' when at != null => MediaSkip(at),
      'next' => const MediaNext(),
      'seek' when at != null => MediaSeek(at),
      'stop' => const MediaStop(),
      'open' => const MediaOpen(),
      _ => null,
    };
  }

  /// Lo que pasó en el teléfono, como lo manda el lado nativo: `{kind}`.
  static MediaInterruption? interruptionFrom(Map<Object?, Object?> map) =>
      switch (map['kind']) {
        'began' => const MediaInterruptionBegan(resumable: true),
        'lost' => const MediaInterruptionBegan(resumable: false),
        'ended' => const MediaInterruptionEnded(),
        'noisy' => const MediaBecameNoisy(),
        _ => null,
      };

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _commands.close();
    await _interruptions.close();
  }
}
