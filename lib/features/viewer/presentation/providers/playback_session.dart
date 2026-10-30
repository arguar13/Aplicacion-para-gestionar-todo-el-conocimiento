import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:video_player/video_player.dart';

/// Lo que suena de un archivo: **un** reproductor, compartido por todo lo
/// que lo muestra o lo sigue (F23) —el reproductor del detalle, el mini
/// reproductor flotante, el texto que resalta la palabra que suena y la
/// pantalla completa—. Pausar desde cualquiera pausa el mismo audio, y pasar
/// a pantalla completa no lo reinicia.
class PlaybackSession {
  PlaybackSession(this.controller);

  final VideoPlayerController controller;

  /// Cómo se llama lo que suena en la tarjeta de la notificación (F47, paso
  /// 2b): lo pone quien sabe de qué elemento es —el mini reproductor del
  /// detalle—; sin eso, el nombre del archivo.
  String? title;

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
///
/// Uno a la vez con el lector flotante (F25): al empezar a sonar toma el
/// foco de audio —ver [AudioFocus]—, y si otro lo toma, se pausa.
final playbackSessionProvider = Provider.autoDispose
    .family<PlaybackSession, String>((ref, path) {
      final session = PlaybackSession(
        VideoPlayerController.file(
          File(path),
          // Sigue sonando con la app minimizada o la pantalla apagada, con
          // su tarjeta en la notificación (F47, paso 2b). Al salir del
          // elemento se suelta igual, como siempre.
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        ),
      );
      ref.onDispose(session.controller.dispose);

      // La tarjeta de lo que suena, mientras tenga el foco de audio. Se
      // registra apenas termina de armarse: un provider no puede cambiar
      // otro mientras se arma.
      final card = PlaybackMediaSource(
        session,
        fallbackTitle: p.basename(path),
      );
      final sources = ref.read(mediaSessionSourcesProvider.notifier);
      var disposed = false;
      scheduleMicrotask(() {
        if (!disposed) sources.register(session, card);
      });
      ref.onDispose(() {
        disposed = true;
        sources.unregister(session, card);
        card.dispose();
      });

      final controller = session.controller;
      final focus = ref.read(audioFocusProvider.notifier);
      // El oyente del reproductor salta en cada avance de la posición: solo
      // importa el paso de quieto a sonando.
      var wasPlaying = false;
      controller.addListener(() {
        final playing = controller.value.isPlaying;
        if (playing && !wasPlaying) focus.claim(session);
        wasPlaying = playing;
      });
      ref.listen(audioFocusProvider, (_, owner) {
        if (!identical(owner, session) && controller.value.isPlaying) {
          unawaited(controller.pause());
        }
      });
      return session;
    });

/// Un audio o un video en la tarjeta de lo que suena (F47, paso 2b): su
/// título, por dónde va y cuánto dura, y lo que se toca en la tarjeta. El
/// foco de audio del teléfono lo pide su propio reproductor, no la tarjeta.
/// Terminado, la tarjeta se va.
class PlaybackMediaSource implements MediaSessionSource {
  PlaybackMediaSource(this._session, {required this.fallbackTitle}) {
    _session.controller.addListener(_update);
    _update();
  }

  final PlaybackSession _session;

  /// El título mientras nadie diga cuál es: el nombre del archivo.
  final String fallbackTitle;

  final _state = ValueNotifier<MediaSessionState?>(null);

  @override
  ValueListenable<MediaSessionState?> get state => _state;

  void _update() {
    final value = _session.controller.value;
    final ended =
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration;
    _state.value = !value.isInitialized || ended
        ? null
        : MediaSessionState(
            title: _session.title ?? fallbackTitle,
            position: value.position,
            duration: value.duration,
            playing: value.isPlaying,
            requestsAudioFocus: false,
          );
  }

  @override
  void handle(MediaCommand command) {
    final controller = _session.controller;
    final value = controller.value;
    switch (command) {
      case MediaPlay():
        unawaited(controller.play());
      case MediaPause() || MediaStop():
        unawaited(controller.pause());
      case MediaSkip(:final by):
        unawaited(
          controller.seekTo(_within(value.position + by, value.duration)),
        );
      case MediaSeek(:final to):
        unawaited(controller.seekTo(_within(to, value.duration)));
      case MediaNext() || MediaOpen():
        // Un audio no tiene cola, y tocar la tarjeta solo trae la app.
        break;
    }
  }

  static Duration _within(Duration at, Duration duration) {
    if (at < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && at > duration) return duration;
    return at;
  }

  void dispose() {
    _session.controller.removeListener(_update);
    _state.dispose();
  }
}

/// Qué archivo suena en el detalle de un elemento —su ruta absoluta—, o
/// `null` si no hay nada que escuchar: el audio o el video mismo, o el audio
/// ya bajado de un video de YouTube (F24). Es lo que comparten el
/// reproductor, el mini reproductor y el texto que sigue al audio.
final itemPlaybackPathProvider = FutureProvider.autoDispose
    .family<String?, KnowledgeItem>((ref, item) async {
      if (item.source.kind == SourceKind.youtube) {
        final downloaded = item.source.originalFilePath;
        if (downloaded == null || kIsWeb) return null;
        return ref.read(fileStoreProvider).resolve(downloaded);
      }
      final resolved = await ref.watch(resolvedFileViewerProvider(item).future);
      return resolved is MediaResolvedViewer ? resolved.path : null;
    });
