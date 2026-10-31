import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El lector en voz alta en la tarjeta de lo que suena (F47, paso 2b): lo
/// que se lee —también la voz del chat, que es el mismo lector—, con qué voz
/// y a qué velocidad, por dónde va, y lo que se toca en la tarjeta.
///
/// Se registra con el testigo del lector ([readAloudFocusOwner]): la tarjeta
/// lo muestra mientras el lector tenga el foco de audio de la app.
class ReadAloudMediaSource implements MediaSessionSource {
  ReadAloudMediaSource(this._controller);

  final ReadAloudController Function() _controller;
  final _state = ValueNotifier<MediaSessionState?>(null);

  @override
  ValueListenable<MediaSessionState?> get state => _state;

  /// Lo que muestra la tarjeta del lector en [reading], con los textos de
  /// [l10n] en [locale] y la cara de la voz como portada ([artwork]): nada si
  /// no se lee nada o si terminó —al terminar, la tarjeta se va—.
  void describe(
    ReadAloudState reading,
    AppLocalizations l10n,
    String locale, {
    Uint8List? artwork,
  }) {
    final document = reading.document;
    if (document == null || reading.finished) {
      _state.value = null;
      return;
    }
    final voice = readAloudVoiceName(reading.voice, l10n);
    final speed = formatReadAloudSpeed(reading.speed, locale);
    _state.value = MediaSessionState(
      title: document.title,
      subtitle: reading.playing
          ? l10n.f47P2ReadingWith(voice, speed)
          : l10n.f47P2PausedWith(voice, speed),
      position: reading.elapsed,
      duration: reading.total,
      playing: reading.playing,
      hasNext: !reading.queue.isEmpty,
      artwork: artwork,
    );
  }

  @override
  void handle(MediaCommand command) {
    final controller = _controller();
    switch (command) {
      case MediaPlay():
        unawaited(controller.play());
      case MediaPause():
        unawaited(controller.pause());
      case MediaSkip(:final by):
        unawaited(controller.skip(by));
      case MediaNext():
        unawaited(controller.playNext());
      case MediaSeek(:final to):
        unawaited(controller.seekTo(to));
      case MediaStop():
        // La tarjeta se descartó: se deja de leer, como con «Dejar de leer».
        unawaited(controller.close());
      case MediaOpen():
        // La app vuelve al frente con el reproductor abierto en lo que
        // suena; la pantalla que lo ofrece sigue la línea sola.
        controller.expand();
    }
  }

  void dispose() => _state.dispose();
}

/// Cómo se dibuja la portada de la tarjeta: la cara de la voz, en PNG (ver
/// `voiceFacePng`). Un provider para que las pruebas no dependan del motor de
/// dibujo.
final voiceArtworkProvider = Provider<Future<Uint8List?> Function(VoiceFace)>(
  (ref) => voiceFacePng,
);

/// Pone al lector en la tarjeta de lo que suena mientras esté montado (F47,
/// paso 2b). Lo monta `ReadAloudOverlay`, por encima de toda pantalla: los
/// textos de la tarjeta salen de su idioma.
class ReadAloudMediaSession extends ConsumerStatefulWidget {
  const ReadAloudMediaSession({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReadAloudMediaSession> createState() =>
      _ReadAloudMediaSessionState();
}

class _ReadAloudMediaSessionState extends ConsumerState<ReadAloudMediaSession> {
  late final _source = ReadAloudMediaSource(
    () => ref.read(readAloudControllerProvider.notifier),
  );
  late final MediaSessionSources _sources = ref.read(
    mediaSessionSourcesProvider.notifier,
  );
  late final ProviderSubscription<ReadAloudState> _reading;
  AppLocalizations? _l10n;
  var _locale = '';

  /// La portada de cada voz, por la cara que la dibuja, ya armada: la misma
  /// imagen —el mismo objeto— mientras lea la misma voz, así la tarjeta no
  /// la vuelve a mandar.
  final _artworks = <VoiceFace, Uint8List>{};

  /// Las caras que se están dibujando, para no pedir dos veces la misma.
  final _drawing = <VoiceFace>{};

  @override
  void initState() {
    super.initState();
    _reading = ref.listenManual(
      readAloudControllerProvider,
      (_, next) => _describe(next),
    );
    // Fuera de la construcción: cambiar un provider mientras se construye
    // otro widget no está permitido.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sources.register(readAloudFocusOwner, _source);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
    _locale = Localizations.localeOf(context).toString();
    _describe(ref.read(readAloudControllerProvider));
  }

  void _describe(ReadAloudState reading) {
    final l10n = _l10n;
    if (l10n == null) return;
    _source.describe(
      reading,
      l10n,
      _locale,
      artwork: _artworkOf(reading.voice, l10n),
    );
  }

  /// La portada de la tarjeta: la cara de [voice] —la de la biblioteca, o la
  /// de la voz del sistema—, si ya está dibujada. Si no, se dibuja aparte y,
  /// al estar, la tarjeta se vuelve a describir. Donde no hay tarjeta, no se
  /// dibuja nada.
  Uint8List? _artworkOf(NarrationVoice? voice, AppLocalizations l10n) {
    if (!ref.read(mediaSessionPlatformProvider).isSupported) return null;
    final profile = voice == null ? null : voiceProfileOf(voice);
    final face = profile == null
        ? VoiceFace.of(
            ReadAloudVoiceFace.systemFaceId,
            l10n.readAloudSystemVoice,
          )
        : VoiceFace.of(profile.id, profile.label);
    final ready = _artworks[face];
    if (ready != null || !_drawing.add(face)) return ready;
    unawaited(
      ref
          .read(voiceArtworkProvider)(face)
          .then(
            (bytes) {
              _drawing.remove(face);
              if (bytes == null || !mounted) return;
              _artworks[face] = bytes;
              _describe(ref.read(readAloudControllerProvider));
            },
            onError: (Object _) {
              // Sin portada, la tarjeta lleva la de la app.
              _drawing.remove(face);
            },
          ),
    );
    return null;
  }

  @override
  void dispose() {
    _reading.close();
    final sources = _sources;
    final source = _source;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sources.unregister(readAloudFocusOwner, source);
      source.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
