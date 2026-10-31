import 'package:flutter/foundation.dart';

/// Lo que hace sonar un tramo de voz ya generado (F47, paso 3): el WAV que
/// dejó el motor sin conexión, o la muestra publicada de una voz.
///
/// Un contrato y no `VideoPlayerController` a secas por lo de siempre: el
/// reproductor de verdad necesita la plataforma, y las pruebas lo cambian por
/// un doble que «termina» cuando se le dice.
abstract interface class SpeechClipPlayer {
  /// Hace sonar [clip] de punta a punta y avisa por [onProgress] cuánto lleva,
  /// de 0 a 1. Devuelve `true` si sonó hasta el final y `false` si se cortó
  /// con [stop] o con otro [play]. Falla si el clip no se pudo abrir.
  ///
  /// [speed] lo hace sonar más rápido o más lento (1 es como se generó): lo
  /// usan las voces de la nube (F47, paso 4), cuyo audio no se vuelve a pedir
  /// —ni a pagar— para cambiar la velocidad.
  Future<bool> play(
    SpeechClip clip, {
    void Function(double)? onProgress,
    double speed = 1,
  });

  /// Corta lo que suena, si algo suena.
  Future<void> stop();

  Future<void> dispose();
}

/// Qué suena: un archivo del teléfono o una dirección.
@immutable
sealed class SpeechClip {
  const SpeechClip();
}

class FileSpeechClip extends SpeechClip {
  const FileSpeechClip(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is FileSpeechClip && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileSpeechClip($path)';
}

class UrlSpeechClip extends SpeechClip {
  const UrlSpeechClip(this.url);

  final String url;

  @override
  bool operator ==(Object other) => other is UrlSpeechClip && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'UrlSpeechClip($url)';
}
