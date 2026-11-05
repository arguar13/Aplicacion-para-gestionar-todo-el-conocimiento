import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/features/narration/data/audio/device_speech_voice_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/offline_speech_voice_renderer.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_encoder.dart';
import 'package:sinapsis/features/narration/data/audio/speech_audio_renderer.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';

/// Si las voces del teléfono pueden quedar en un archivo: en Android, con el
/// motor del sistema (`DeviceSpeechChannel.kt`). Como con las voces sin
/// conexión, `Platform.isAndroid` y no la plataforma de mentira de las
/// pruebas.
final deviceSpeechToFileAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);

/// **Quienes hacen las voces del audio que genera la app** (F47, pasos 5 y
/// 6), cada una con su prefijo de id (`SpeechVoiceIds`): las sin conexión
/// bajadas y las del teléfono, donde se puede.
///
/// **El enganche del paso 4** (las voces de la nube, clonadas o creadas): se
/// suman acá con su propio [SpeechVoiceRenderer] —su prefijo, `isReady` con
/// su cuenta y `priceOf` con lo que cobra—. Con eso, el podcast las acepta,
/// dice el costo antes de generar y pide confirmación, sin cambiar nada más.
final speechVoiceRenderersProvider = Provider<List<SpeechVoiceRenderer>>((ref) {
  final files = ref.watch(offlineVoiceFilesProvider);
  final synthesizer = ref.watch(offlineSpeechSynthesizerProvider);
  return [
    if (files != null && synthesizer != null)
      OfflineSpeechVoiceRenderer(
        synthesizer: synthesizer,
        engineOf: files.engineConfigOf,
      ),
    if (ref.watch(deviceSpeechToFileAvailableProvider))
      const DeviceSpeechVoiceRenderer(),
  ];
});

/// Dónde se trabaja mientras se genera un audio: fuera de la bóveda —no
/// viaja en la copia— pero no en la caché, que el sistema vacía cuando
/// quiere: lo hecho tiene que estar al retomar. Las pruebas lo cambian.
final speechAudioWorkRootProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join((await getApplicationSupportDirectory()).path, 'audio-en-curso'),
      ),
);

/// Lo que comprime el audio armado. Las pruebas lo cambian.
final speechAudioEncoderProvider = Provider<SpeechAudioEncoder>(
  (ref) => const PlatformSpeechAudioEncoder(),
);

/// Lo que lleva a WAV un tramo en otro formato (el MP3 de una voz de la
/// nube). Las pruebas lo cambian.
final speechClipDecoderProvider = Provider<SpeechClipDecoder>(
  (ref) => const PlatformSpeechClipDecoder(),
);

/// La pieza común para generar audio en el teléfono: ver
/// [SpeechAudioRenderer]. Lee a sus voces al usarlas, así que una voz que se
/// baja mientras tanto ya cuenta.
final speechAudioRendererProvider = Provider<SpeechAudioRenderer>(
  (ref) => SpeechAudioRenderer(
    voices: () => ref.read(speechVoiceRenderersProvider),
    workRoot: ref.watch(speechAudioWorkRootProvider),
    encoder: ref.watch(speechAudioEncoderProvider),
    decoder: ref.watch(speechClipDecoderProvider),
  ),
);
