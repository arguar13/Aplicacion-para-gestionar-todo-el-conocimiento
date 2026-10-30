import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/audio/media_session.dart';

/// La sesión de medios del sistema, de mentira (F47, paso 2b): anota lo que
/// se le mostró y deja que la prueba toque la tarjeta o interrumpa, sin
/// Android detrás.
class FakeMediaSession implements MediaSessionPlatform {
  FakeMediaSession({this.isSupported = true});

  @override
  final bool isSupported;

  /// Cada tarjeta que se mostró, en orden.
  final shown = <MediaSessionState>[];
  int ended = 0;

  final _commands = StreamController<MediaCommand>.broadcast(sync: true);
  final _interruptions = StreamController<MediaInterruption>.broadcast(
    sync: true,
  );

  /// Lo último que muestra la tarjeta, o `null` si se fue.
  MediaSessionState? get card => _showing ? shown.last : null;
  var _showing = false;

  /// Se tocó [command] en la tarjeta.
  void tap(MediaCommand command) => _commands.add(command);

  /// Pasó [interruption] en el teléfono.
  void interrupt(MediaInterruption interruption) =>
      _interruptions.add(interruption);

  @override
  Future<void> update(MediaSessionState state) async {
    shown.add(state);
    _showing = true;
  }

  @override
  Future<void> end() async {
    ended++;
    _showing = false;
  }

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Stream<MediaInterruption> get interruptions => _interruptions.stream;
}

/// Algo que suena, de mentira: la prueba le dice qué mostrar y ve lo que se
/// le pidió.
class FakeMediaSource implements MediaSessionSource {
  FakeMediaSource([MediaSessionState? initial])
    : _state = ValueNotifier(initial);

  final ValueNotifier<MediaSessionState?> _state;
  final handled = <MediaCommand>[];

  @override
  ValueListenable<MediaSessionState?> get state => _state;

  MediaSessionState? get value => _state.value;
  set value(MediaSessionState? value) => _state.value = value;

  @override
  void handle(MediaCommand command) {
    handled.add(command);
    // Como un reproductor de verdad: pausar pausa y reproducir reproduce.
    final current = _state.value;
    if (current == null) return;
    if (command is MediaPause) {
      _state.value = _copy(current, playing: false);
    } else if (command is MediaPlay) {
      _state.value = _copy(current, playing: true);
    }
  }

  static MediaSessionState _copy(
    MediaSessionState state, {
    required bool playing,
  }) => MediaSessionState(
    title: state.title,
    subtitle: state.subtitle,
    position: state.position,
    duration: state.duration,
    playing: playing,
    hasNext: state.hasNext,
    requestsAudioFocus: state.requestsAudioFocus,
  );
}
