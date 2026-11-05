import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/narration/data/audio/document_audio_store.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';

/// **Si en este dispositivo se descarga el audio de un documento** (F47,
/// paso 5): en Android, donde la pieza común lo genera con las voces del
/// teléfono y las sin conexión, lo comprime a M4A y el reproductor lo hace
/// sonar desde el disco. En la web el almacén no tiene una ruta en el disco ni
/// hay motor que deje un archivo, y en Windows tampoco: ahí «Descargar audio»
/// no se ofrece, y ⋮ dice por qué.
///
/// Como las voces sin conexión, `Platform.isAndroid` y no la plataforma de
/// mentira de las pruebas: las pruebas lo cambian.
final documentAudioSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);

/// Dónde se guardan los audios de los documentos: la bóveda.
final documentAudioStoreProvider = Provider<DocumentAudioStore>(
  (ref) => DocumentAudioStore(ref.watch(fileStoreProvider)),
);

/// El idioma de la voz del teléfono para un pedazo sin voz elegida y sin
/// idioma reconocido: el del teléfono, que es el que usa su motor. Las
/// pruebas lo cambian.
final speechFallbackLocaleProvider = Provider<String>(
  (ref) => WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
);

/// El audio descargado del documento `documentId` —su ficha—, o `null` si no
/// tiene. Quien guarda o borra uno lo invalida.
final documentAudioProvider = FutureProvider.autoDispose
    .family<DocumentAudio?, String>((ref, documentId) {
      if (!ref.watch(documentAudioSupportedProvider)) return null;
      return ref.watch(documentAudioStoreProvider).read(documentId);
    });

/// Si del audio de `documentId` quedó generado algo de un intento anterior
/// —se canceló, se cerró la app, faltó una voz—: «Seguir descargando», que
/// no rehace lo hecho. Quien descarga lo invalida al terminar.
final documentAudioResumableProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, documentId) {
      if (!ref.watch(documentAudioSupportedProvider)) return false;
      return ref
          .watch(speechAudioRendererProvider)
          .hasWork(documentAudioWorkKey(documentId));
    });

/// Quién busca el audio descargado de lo que el lector va a leer (F47, paso
/// 5): con [voicesFor] —la voz con que el lector diría ahora cada pedazo—
/// arma lo que se generaría y, si el audio guardado es de esto mismo, lo
/// devuelve para que suene desde él. Si quedó viejo, o no está, `null`: se
/// lee con la voz, como siempre.
typedef DownloadedSpeechLookup =
    Future<RecordedSpeech?> Function(
      ReadableDocument document,
      List<NarrationVoice?> Function(List<ReadableSegment> segments) voicesFor,
    );

/// El que busca el audio descargado al empezar a leer, o `null` donde no se
/// descargan audios ([documentAudioSupportedProvider]): ahí el lector ni
/// pregunta, y empieza a leer como siempre.
final downloadedSpeechLookupProvider = Provider<DownloadedSpeechLookup?>((ref) {
  if (!ref.watch(documentAudioSupportedProvider)) return null;
  final store = ref.watch(documentAudioStoreProvider);
  final locale = ref.watch(speechFallbackLocaleProvider);
  return (document, voicesFor) async {
    // Lo que ya suena en su propio audio —un podcast, un audio— no tiene
    // otro.
    if (document.ownAudio || document.recording != null) return null;
    try {
      final audio = await store.read(document.id);
      if (audio == null) return null;
      final segments = document.segments;
      final plan = DocumentAudioPlan.of(
        segments,
        voicesFor(segments),
        fallbackLocale: locale,
      );
      if (documentAudioStatusOf(audio, plan, segments) !=
          DocumentAudioStatus.ready) {
        return null;
      }
      final path = await store.localPathOf(audio);
      return path == null ? null : audio.recordingAt(path);
    } on FileSystemException {
      // El audio no se pudo leer: se lee con la voz, que es lo de siempre.
      return null;
    }
  };
});
