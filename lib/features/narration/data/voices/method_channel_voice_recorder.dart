import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/features/narration/domain/services/voice_recorder.dart';

/// [VoiceRecorder] en Android, con `AudioRecord` por los canales
/// `app.sinapsis/voice_recorder` y `app.sinapsis/voice_recorder/events` (ver
/// `VoiceRecorderChannel` del lado de Kotlin).
///
/// **Sin paquete de grabación** —lo que se justifica en el informe del paso 4
/// y en la decisión 3—: la app ya tiene el permiso del micrófono y un canal
/// propio para dictar (F42); grabar un solo formato, un WAV PCM de 16 bits,
/// son cien líneas de Kotlin, y un paquete sumaría formatos, plataformas y
/// dependencias nativas que la muestra de una voz no usa.
class MethodChannelVoiceRecorder implements VoiceRecorder {
  const MethodChannelVoiceRecorder({
    MethodChannel methods = const MethodChannel('app.sinapsis/voice_recorder'),
    EventChannel events = const EventChannel(
      'app.sinapsis/voice_recorder/events',
    ),
  }) : _methods = methods,
       _events = events;

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
      // Sin el canal —la web, Windows, una prueba— no se graba.
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _methods.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Stream<RecordingProgress> record({
    required String outputPath,
    required Duration limit,
  }) => _events
      .receiveBroadcastStream({
        'path': outputPath,
        'limitMs': limit.inMilliseconds,
      })
      .transform(
        StreamTransformer<Object?, RecordingProgress>.fromHandlers(
          handleData: (event, sink) {
            final progress = recordingProgressFrom(event);
            if (progress != null) sink.add(progress);
          },
          handleError: (error, stackTrace, sink) => sink.addError(
            error is PlatformException
                ? VoiceRecorderException(error.code)
                : error,
            stackTrace,
          ),
        ),
      );

  @override
  Future<void> stop() async {
    try {
      await _methods.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Sin canal no había nada grabando.
    }
  }
}

/// Lo que manda `VoiceRecorderChannel` por cada evento, en Dart; `null` si no
/// se entiende.
RecordingProgress? recordingProgressFrom(Object? event) {
  if (event is! Map) return null;
  final level = event['level'];
  final elapsed = event['elapsedMs'];
  if (level is! num || elapsed is! num) return null;
  return RecordingProgress(
    level: level.toDouble().clamp(0, 1),
    elapsed: Duration(milliseconds: elapsed.toInt()),
  );
}
