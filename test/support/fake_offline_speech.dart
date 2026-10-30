import 'dart:async';
import 'dart:io';

import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';

/// Un motor sin conexión de mentira (F47, paso 3): no genera audio de verdad;
/// escribe un archivo chico donde se le pide y anota qué dijo, con qué voz y
/// a qué velocidad. Con [hold], cada pedido espera a que la prueba lo suelte
/// ([finishNext]), para ver qué pasa mientras «genera».
class FakeOfflineSpeechSynthesizer implements OfflineSpeechSynthesizer {
  FakeOfflineSpeechSynthesizer({this.hold = false});

  final bool hold;

  final requests = <FakeSynthesis>[];
  int releases = 0;
  bool disposed = false;

  /// Si se pone, cada pedido falla con esto.
  Object? failWith;

  final _waiting = <Completer<void>>[];

  @override
  Future<Duration> synthesize({
    required OfflineVoiceEngineConfig engine,
    required int speakerId,
    required String text,
    required double speed,
    required String outputPath,
  }) async {
    requests.add(
      FakeSynthesis(
        engine: engine,
        speakerId: speakerId,
        text: text,
        speed: speed,
        outputPath: outputPath,
      ),
    );
    if (hold) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    }
    if (failWith case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    File(outputPath).writeAsStringSync('audio de: $text');
    return Duration(milliseconds: 80 * text.length);
  }

  /// Suelta el pedido más viejo que espera.
  void finishNext() => _waiting.removeAt(0).complete();

  @override
  Future<void> release() async => releases++;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeSynthesis {
  const FakeSynthesis({
    required this.engine,
    required this.speakerId,
    required this.text,
    required this.speed,
    required this.outputPath,
  });

  final OfflineVoiceEngineConfig engine;
  final int speakerId;
  final String text;
  final double speed;
  final String outputPath;
}

/// Un reproductor de tramos de mentira (F47, paso 3): no suena; anota qué se
/// le pidió y «termina», «avanza» o «falla» cuando la prueba lo dice.
class FakeSpeechClipPlayer implements SpeechClipPlayer {
  final played = <SpeechClip>[];
  int stops = 0;

  Completer<bool>? _current;
  void Function(double)? _onProgress;

  /// Si suena algo ahora.
  bool get playing => _current != null;

  @override
  Future<bool> play(SpeechClip clip, {void Function(double)? onProgress}) {
    _cut();
    played.add(clip);
    final current = _current = Completer<bool>();
    _onProgress = onProgress;
    return current.future;
  }

  /// Lo que suena lleva [fraction] (de 0 a 1).
  void advance(double fraction) => _onProgress?.call(fraction);

  /// Lo que suena llegó al final.
  void finish() {
    final current = _current;
    _current = null;
    current?.complete(true);
  }

  /// Lo que suena no se pudo abrir.
  void fail() {
    final current = _current;
    _current = null;
    current?.completeError(StateError('no se pudo abrir'));
  }

  void _cut() {
    final current = _current;
    _current = null;
    current?.complete(false);
  }

  @override
  Future<void> stop() async {
    stops++;
    _cut();
  }

  @override
  Future<void> dispose() => stop();
}
