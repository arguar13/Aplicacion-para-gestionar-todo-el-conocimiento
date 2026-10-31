import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/method_channel_media_session.dart';
import 'package:sinapsis/core/audio/null_media_session.dart';

/// La sesión de medios de esta plataforma: en Android, la de verdad; en el
/// resto, una que no hace nada.
final mediaSessionPlatformProvider = Provider<MediaSessionPlatform>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const NullMediaSession();
  }
  final session = MethodChannelMediaSession();
  ref.onDispose(session.dispose);
  return session;
});

/// Un reloj que solo avanza, para saber cuánto adelantó el teléfono la barra
/// de la tarjeta por su cuenta. Un provider para que las pruebas lo manejen.
final mediaSessionClockProvider = Provider<Duration Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
});

/// Lo que puede mostrarse en la tarjeta, por el testigo con que cada uno
/// toma el foco de audio de la app (F47, paso 2b): el del lector en voz alta,
/// el de cada audio abierto.
///
/// Lo que se suma después —el podcast— se registra igual y entra a la
/// tarjeta sin cambiar nada más.
class MediaSessionSources extends Notifier<Map<Object, MediaSessionSource>> {
  @override
  Map<Object, MediaSessionSource> build() => const {};

  /// [source] es lo que muestra la tarjeta mientras [owner] tenga el foco.
  void register(Object owner, MediaSessionSource source) {
    if (identical(state[owner], source)) return;
    state = Map.unmodifiable({...state, owner: source});
  }

  /// [owner] ya no muestra nada. Si en el medio otro se registró con el
  /// mismo testigo, ese queda.
  void unregister(Object owner, MediaSessionSource source) {
    if (!identical(state[owner], source)) return;
    state = Map.unmodifiable({...state}..remove(owner));
  }
}

final mediaSessionSourcesProvider =
    NotifierProvider<MediaSessionSources, Map<Object, MediaSessionSource>>(
      MediaSessionSources.new,
    );

/// Lo que suena ahora en la app: la fuente registrada por quien tiene el foco
/// de audio, o `null`. Es lo mismo que sigue la tarjeta —ver
/// [mediaSessionHubProvider]—, para quien lo mire de afuera: el widget
/// «Seguir escuchando» cuenta lo que empieza a sonar acá (F47, paso 7).
///
/// La tarjeta no lo escucha a él sino al foco y a las fuentes, de a uno: así
/// la sigue en el mismo instante en que cambian, sin esperar a que se vuelva
/// a calcular un provider derivado.
final focusedMediaSourceProvider = Provider<MediaSessionSource?>((ref) {
  final owner = ref.watch(audioFocusProvider);
  return owner == null ? null : ref.watch(mediaSessionSourcesProvider)[owner];
});

/// La tarjeta de lo que suena, de punta a punta (F47, paso 2b): muestra lo
/// que tiene el foco de audio de la app, le pasa lo que se toca y se porta
/// bien con el resto del teléfono.
///
/// No hace nada por sí mismo hasta que alguien lo escucha: lo mantiene vivo
/// `ReadAloudOverlay`, que está siempre montado.
final mediaSessionHubProvider = Provider<void>((ref) {
  final platform = ref.watch(mediaSessionPlatformProvider);
  if (!platform.isSupported) return;
  final hub = MediaSessionHub(
    platform,
    now: ref.watch(mediaSessionClockProvider),
  );
  ref.onDispose(hub.dispose);

  void follow() {
    final owner = ref.read(audioFocusProvider);
    hub.follow(
      owner == null ? null : ref.read(mediaSessionSourcesProvider)[owner],
    );
  }

  ref
    ..listen(audioFocusProvider, (_, _) => follow())
    ..listen(mediaSessionSourcesProvider, (_, _) => follow());
  follow();
});

/// Lo que hace la tarjeta (F47, paso 2b), sin Riverpod: ver
/// [mediaSessionHubProvider].
///
/// - **Una sola tarjeta**: la de lo que tiene el foco de audio de la app.
///   Cuando el foco pasa a otro —empieza un audio mientras se leía—, la
///   tarjeta pasa a mostrarlo; si lo que suena ya no tiene nada que mostrar
///   —terminó o se cerró—, la tarjeta se va.
/// - **Sin ruido en el canal**: la tarjeta se actualiza cuando cambia algo
///   que se ve, no con cada palabra. Mientras suena, el teléfono adelanta la
///   barra solo; se le corrige la posición si se apartó más de
///   [maxDrift] —un salto, o una voz que va más rápido que lo estimado—.
/// - **Se porta bien**: una llamada o el GPS hablando pausan, y al terminar
///   sigue; otra app que se queda con el sonido pausa y no vuelve;
///   desconectar los auriculares pausa.
class MediaSessionHub {
  MediaSessionHub(this._platform, {required Duration Function() now})
    : _now = now {
    _commands = _platform.commands.listen(_onCommand);
    _interruptions = _platform.interruptions.listen(_onInterruption);
  }

  /// Cuánto puede apartarse lo que adelanta el teléfono de lo que de verdad
  /// va, antes de corregirlo.
  static const maxDrift = Duration(seconds: 2);

  final MediaSessionPlatform _platform;
  final Duration Function() _now;
  late final StreamSubscription<MediaCommand> _commands;
  late final StreamSubscription<MediaInterruption> _interruptions;

  MediaSessionSource? _source;

  /// Lo último que se mandó a la tarjeta, y cuándo; `null` sin tarjeta.
  MediaSessionState? _shown;
  Duration _shownAt = Duration.zero;

  /// Si se pausó por una interrupción pasajera, para seguir al terminar.
  var _pausedByInterruption = false;

  /// Muestra [source] en la tarjeta —el que tiene el foco—, o nada.
  void follow(MediaSessionSource? source) {
    if (identical(source, _source)) return;
    _source?.state.removeListener(_onState);
    _source = source;
    _pausedByInterruption = false;
    source?.state.addListener(_onState);
    _onState();
  }

  void _onState() {
    final state = _source?.state.value;
    if (state == null) {
      if (_shown == null) return;
      _shown = null;
      _pausedByInterruption = false;
      unawaited(_platform.end());
      return;
    }
    final shown = _shown;
    final now = _now();
    if (shown != null && shown.looksLike(state)) {
      // Lo mismo a la vista: solo cuenta si la barra se apartó.
      final advanced = shown.playing ? now - _shownAt : Duration.zero;
      final drift = (shown.position + advanced - state.position).abs();
      if (drift <= maxDrift) return;
    }
    _shown = state;
    _shownAt = now;
    unawaited(_platform.update(state));
  }

  void _onCommand(MediaCommand command) {
    final source = _source;
    if (source == null) return;
    // Lo que pide la persona manda sobre lo que hizo una interrupción.
    if (command is MediaPlay || command is MediaPause) {
      _pausedByInterruption = false;
    }
    source.handle(command);
  }

  void _onInterruption(MediaInterruption interruption) {
    final source = _source;
    if (source == null) return;
    final playing = source.state.value?.playing ?? false;
    switch (interruption) {
      case MediaInterruptionBegan(:final resumable):
        if (!playing) return;
        _pausedByInterruption = resumable;
        source.handle(const MediaPause());
      case MediaInterruptionEnded():
        if (!_pausedByInterruption) return;
        _pausedByInterruption = false;
        source.handle(const MediaPlay());
      case MediaBecameNoisy():
        _pausedByInterruption = false;
        if (playing) source.handle(const MediaPause());
    }
  }

  void dispose() {
    _source?.state.removeListener(_onState);
    _source = null;
    unawaited(_commands.cancel());
    unawaited(_interruptions.cancel());
    if (_shown != null) unawaited(_platform.end());
  }
}
