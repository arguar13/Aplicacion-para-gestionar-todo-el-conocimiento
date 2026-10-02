import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';

/// El testigo del lector flotante en [audioFocusProvider].
const Object readAloudFocusOwner = #readAloud;

/// El lado del lector en "uno a la vez con el audio" (F25): cuando empieza
/// a leer toma el foco —y el audio o el video que sonaba se pausa—, y
/// cuando un audio empieza a sonar, el lector se pausa. Retoma solo si se le
/// pide: nadie quiere que un audio pausado le hable encima.
///
/// No hace nada por sí mismo hasta que alguien lo escucha: lo mantiene vivo
/// `ReadAloudOverlay`, que está siempre montado.
final readAloudAudioFocusProvider = Provider<void>((ref) {
  ref
    ..listen(readAloudControllerProvider.select((s) => s.playing), (
      _,
      playing,
    ) {
      if (playing) {
        ref.read(audioFocusProvider.notifier).claim(readAloudFocusOwner);
      }
    })
    ..listen(audioFocusProvider, (_, owner) {
      if (identical(owner, readAloudFocusOwner)) return;
      if (ref.read(readAloudControllerProvider).playing) {
        unawaited(ref.read(readAloudControllerProvider.notifier).pause());
      }
    });
});
