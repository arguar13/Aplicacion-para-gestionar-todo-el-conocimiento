import 'dart:async';

import 'package:sinapsis/features/narration/domain/services/speech_track_player.dart';

/// Un reproductor de audio ya generado de mentira (F47, paso 6b): anota lo
/// que se le pide y avanza solo cuando la prueba lo dice ([advance],
/// [finish], [interrupt], [breakDown]).
class FakeSpeechTrackPlayer implements SpeechTrackPlayer {
  final calls = <String>[];
  final _positions = StreamController<SpeechTrackPosition>.broadcast();

  String? opened;
  Duration position = Duration.zero;
  double speed = 1;
  bool playing = false;

  /// Los archivos que no se pueden abrir.
  final broken = <String>{};

  @override
  Stream<SpeechTrackPosition> get positions => _positions.stream;

  void _emit({bool completed = false, bool failed = false}) => _positions.add(
    SpeechTrackPosition(
      position: position,
      playing: playing,
      completed: completed,
      failed: failed,
    ),
  );

  @override
  Future<void> open(String path) async {
    calls.add('open $path');
    if (broken.contains(path)) throw StateError('no se puede abrir $path');
    opened = path;
    position = Duration.zero;
    playing = false;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
    _emit();
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek ${to.inMilliseconds}');
    position = to;
    _emit();
  }

  @override
  Future<void> setSpeed(double speed) async {
    calls.add('speed $speed');
    this.speed = speed;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    opened = null;
    playing = false;
  }

  /// Avanza [by] mientras suena.
  void advance(Duration by) {
    position += by;
    _emit();
  }

  /// Llega al final.
  void finish(Duration total) {
    position = total;
    playing = false;
    _emit(completed: true);
  }

  /// Se pausa solo: una llamada.
  void interrupt() {
    playing = false;
    _emit();
  }

  /// No se puede seguir.
  void breakDown() => _emit(failed: true);

  @override
  Future<void> dispose() => _positions.close();
}
