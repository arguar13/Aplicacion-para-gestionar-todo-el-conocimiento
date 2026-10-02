import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Lo que suena de un archivo: **un** reproductor, compartido por todo lo
/// que lo muestra o lo sigue (F23) —el reproductor del detalle, el mini
/// reproductor flotante, el texto que resalta la palabra que suena y la
/// pantalla completa—. Pausar desde cualquiera pausa el mismo audio, y pasar
/// a pantalla completa no lo reinicia.
class PlaybackSession {
  PlaybackSession(this.controller);

  final VideoPlayerController controller;

  /// `true` si el archivo se pudo abrir. `Either`-a-mano con un booleano en
  /// vez de dejar que `initialize()` rechace: un archivo movido o dañado
  /// después de guardarse muestra un aviso, no una excepción sin atrapar.
  late final Future<bool> initialized = controller
      .initialize()
      .then((_) => true)
      .catchError((_) => false);

  /// Si ya se empezó a escuchar: lo que hace aparecer el mini reproductor y
  /// el resaltado. Un audio recién abierto, quieto en 0:00, no los muestra.
  bool get started {
    final value = controller.value;
    return value.isInitialized &&
        (value.isPlaying || value.position > Duration.zero);
  }
}

/// La sesión de reproducción del archivo en `path` —ruta absoluta—. Vive
/// mientras algo en pantalla la use: al salir del elemento, se suelta y el
/// audio se detiene.
final playbackSessionProvider = Provider.autoDispose
    .family<PlaybackSession, String>((ref, path) {
      final session = PlaybackSession(VideoPlayerController.file(File(path)));
      ref.onDispose(session.controller.dispose);
      return session;
    });
