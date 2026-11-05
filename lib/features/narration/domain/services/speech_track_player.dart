import 'package:flutter/foundation.dart';

/// Por dónde va un audio ya generado que suena: lo que avisa
/// [SpeechTrackPlayer.positions] cada vez que cambia.
@immutable
class SpeechTrackPosition {
  const SpeechTrackPosition({
    required this.position,
    required this.playing,
    this.completed = false,
    this.failed = false,
  });

  final Duration position;

  /// Si está sonando: el reproductor puede pausarse solo —una llamada le
  /// quita el foco, se desconectan los auriculares—.
  final bool playing;

  /// Llegó al final.
  final bool completed;

  /// No se pudo seguir: el archivo no está o no se puede leer.
  final bool failed;

  @override
  bool operator ==(Object other) =>
      other is SpeechTrackPosition &&
      other.position == position &&
      other.playing == playing &&
      other.completed == completed &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(position, playing, completed, failed);

  @override
  String toString() =>
      'SpeechTrackPosition(${position.inMilliseconds} ms'
      '${playing ? ', sonando' : ''}${completed ? ', al final' : ''}'
      '${failed ? ', falló' : ''})';
}

/// Lo que hace sonar un audio ya generado de punta a punta —un podcast (F47,
/// paso 6b), el audio descargado de un documento (paso 5)— en el lector:
/// con su tiempo real, para saltar ±10 s, ir a un tramo o cambiar la
/// velocidad sin cortar.
///
/// Un contrato y no `VideoPlayerController` a secas, por lo de siempre: el
/// reproductor de verdad necesita la plataforma, y las pruebas lo cambian por
/// un doble que avanza cuando se le dice.
abstract interface class SpeechTrackPlayer {
  /// Abre [path], quieto al principio; cierra lo que hubiera abierto. Lanza
  /// si el archivo no se puede abrir.
  Future<void> open(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// De 0,5 a 3: el tono no cambia.
  Future<void> setSpeed(double speed);

  /// Cierra lo abierto, si hay algo.
  Future<void> close();

  /// Por dónde va lo abierto, cada vez que cambia.
  Stream<SpeechTrackPosition> get positions;

  Future<void> dispose();
}
