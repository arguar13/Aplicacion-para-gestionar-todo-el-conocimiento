import 'package:flutter/foundation.dart';

/// Lo que muestra **la tarjeta de lo que suena** (F47, paso 2b): la de los
/// reproductores de música, en la barra de notificaciones, en la pantalla de
/// bloqueo, en los auriculares y en el reloj.
///
/// Es la misma para todo lo que suena en la app —el lector en voz alta, un
/// audio o un video, la voz del chat y, cuando llegue, el podcast—: cada uno
/// la describe con esto, y nadie más sabe de Android.
@immutable
class MediaSessionState {
  const MediaSessionState({
    required this.title,
    this.subtitle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.hasNext = false,
    this.requestsAudioFocus = true,
    this.artwork,
  });

  /// Lo que suena: el título del documento, del audio, del podcast.
  final String title;

  /// Debajo del título: «Leyendo con Marisa · 1,0×».
  final String? subtitle;

  /// Por dónde va y cuánto dura, para la barra de avance. Con una voz del
  /// teléfono son estimados (`ReadingTimeline`); con audio, los reales.
  final Duration position;
  final Duration duration;

  final bool playing;

  /// Si hay algo después en la cola: la tarjeta suma «siguiente».
  final bool hasNext;

  /// Si la tarjeta tiene que pedir el foco de audio del teléfono —y pausar
  /// con una llamada—. El lector en voz alta lo pide; un audio no, porque su
  /// reproductor ya lo pide por su cuenta, y dos pedidos de la misma app se
  /// pisarían.
  final bool requestsAudioFocus;

  /// La portada, en PNG o JPEG: la miniatura del documento o la cara de la
  /// voz. Sin ella, la de la app.
  final Uint8List? artwork;

  /// Si [other] se ve igual en la tarjeta, salvo por dónde va: lo único que
  /// cambia con cada palabra, y que el teléfono ya adelanta solo mientras
  /// suena.
  bool looksLike(MediaSessionState other) =>
      other.title == title &&
      other.subtitle == subtitle &&
      other.duration == duration &&
      other.playing == playing &&
      other.hasNext == hasNext &&
      other.requestsAudioFocus == requestsAudioFocus &&
      identical(other.artwork, artwork);

  @override
  bool operator ==(Object other) =>
      other is MediaSessionState &&
      looksLike(other) &&
      other.position == position;

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    position,
    duration,
    playing,
    hasNext,
    requestsAudioFocus,
    artwork,
  );
}

/// Lo que se toca en la tarjeta, en los auriculares o en el reloj (F47, paso
/// 2b).
sealed class MediaCommand {
  const MediaCommand();
}

final class MediaPlay extends MediaCommand {
  const MediaPlay();
}

final class MediaPause extends MediaCommand {
  const MediaPause();
}

/// −10 s o +10 s.
final class MediaSkip extends MediaCommand {
  const MediaSkip(this.by);

  final Duration by;
}

/// «Siguiente» en la cola.
final class MediaNext extends MediaCommand {
  const MediaNext();
}

/// Soltar la barra de avance de la tarjeta.
final class MediaSeek extends MediaCommand {
  const MediaSeek(this.to);

  final Duration to;
}

/// La tarjeta se descartó: deslizada, en pausa.
final class MediaStop extends MediaCommand {
  const MediaStop();
}

/// Se tocó la tarjeta: la app vuelve al frente.
final class MediaOpen extends MediaCommand {
  const MediaOpen();
}

/// Lo que pasa en el teléfono que tiene que callar a la app un rato (F47,
/// paso 2b).
sealed class MediaInterruption {
  const MediaInterruption();
}

/// Otra cosa empezó a sonar: una llamada o el GPS hablando, o la música de
/// otra app. Con [resumable], es por un rato —la llamada termina—, y lo que
/// sonaba vuelve solo; sin él, otra app se quedó con el sonido y no vuelve.
final class MediaInterruptionBegan extends MediaInterruption {
  const MediaInterruptionBegan({required this.resumable});

  final bool resumable;
}

/// Terminó lo que interrumpía por un rato.
final class MediaInterruptionEnded extends MediaInterruption {
  const MediaInterruptionEnded();
}

/// Se desconectaron los auriculares: lo que sonaba por ellos no tiene que
/// salir por el parlante.
final class MediaBecameNoisy extends MediaInterruption {
  const MediaBecameNoisy();
}

/// La sesión de medios del sistema (F47, paso 2b, decisión J): la tarjeta,
/// el servicio en primer plano «de reproducción de medios», el foco de audio
/// y los auriculares.
///
/// Un contrato y no Android a secas, como `StudyReminder`: hablarle al
/// sistema necesita una plataforma de verdad, así que lo que lo use se prueba
/// con un doble. En Android es `MethodChannelMediaSession`; en el resto
/// —la web, Windows— `NullMediaSession`, que no hace nada.
abstract interface class MediaSessionPlatform {
  /// Si hay una tarjeta que mostrar en esta plataforma.
  bool get isSupported;

  /// Muestra o actualiza la tarjeta con [state]. La primera vez arranca el
  /// servicio en primer plano y, si [MediaSessionState.requestsAudioFocus],
  /// pide el foco de audio.
  Future<void> update(MediaSessionState state);

  /// Ya no suena nada: la tarjeta se va, el servicio también y el foco se
  /// devuelve.
  Future<void> end();

  /// Lo que se toca en la tarjeta, los auriculares o el reloj.
  Stream<MediaCommand> get commands;

  /// Lo que pasa en el teléfono: llamadas, otras apps, auriculares.
  Stream<MediaInterruption> get interruptions;
}

/// Algo de la app que suena y se muestra en la tarjeta (F47, paso 2b): el
/// lector en voz alta, un audio, el podcast.
///
/// Se registra con el mismo testigo con que toma el foco de audio de la app
/// (`audioFocusProvider`): la tarjeta muestra al que lo tiene. Ver
/// `mediaSessionSourcesProvider`.
abstract interface class MediaSessionSource {
  /// Lo que muestra la tarjeta; `null` si no hay nada que mostrar —cerrado,
  /// o terminado—.
  ValueListenable<MediaSessionState?> get state;

  /// Lo que se tocó en la tarjeta.
  void handle(MediaCommand command);
}
