import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quién tiene la palabra (F25): **una sola cosa suena a la vez** en la
/// app. Un audio o un video que empieza a sonar le saca el foco al lector
/// flotante, y el lector que empieza a leer se lo saca al audio.
///
/// Es un testigo y nada más: quien empieza a sonar lo toma con [claim], y
/// cada uno escucha este provider y se pausa cuando el testigo deja de ser
/// suyo. No sabe pausar a nadie —no conoce ni `video_player` ni el motor de
/// voz—, así que lo de cada lado queda donde ya estaba: ver
/// `playbackSessionProvider` y `readAloudAudioFocusProvider`.
///
/// No hace falta soltarlo al terminar: un testigo de alguien que ya no
/// suena no pausa a nadie, y el próximo que empiece lo pisa.
class AudioFocus extends Notifier<Object?> {
  @override
  Object? build() => null;

  /// [owner] empieza a sonar: los demás se pausan. Volver a tomarlo siendo
  /// ya de [owner] no avisa nada.
  void claim(Object owner) {
    if (!identical(state, owner)) state = owner;
  }
}

final audioFocusProvider = NotifierProvider<AudioFocus, Object?>(
  AudioFocus.new,
);
