import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/data/voices/video_player_speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/passage_languages.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_filter.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_samples.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_audio_focus.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';

/// Todas las voces de la biblioteca (F47, paso 3): las del teléfono y, donde
/// se ofrecen, las sin conexión del catálogo, estén o no bajadas. Las
/// clonadas y las creadas se suman en el paso 4.
///
/// Si el teléfono no dice sus voces —un motor que falla al preguntarle—, la
/// biblioteca sigue con las demás.
final voiceLibraryProvider = FutureProvider.autoDispose<List<VoiceProfile>>((
  ref,
) async {
  final offline = ref.watch(offlineVoicesAvailableProvider)
      ? offlineVoiceProfiles(OfflineVoiceCatalog.voices)
      : const <VoiceProfile>[];
  List<NarrationVoice> device;
  try {
    device = await ref.watch(narrationVoicesProvider.future);
  } on Object {
    device = const [];
  }
  return [...offline, ...deviceVoiceProfiles(device)];
});

/// Las voces que ya pueden leer, por su id: las del teléfono, siempre, y las
/// sin conexión cuyo paquete está bajado.
final installedVoiceIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final packages = ref.watch(installedVoicePackagesProvider).valueOrNull;
  if (packages == null || packages.isEmpty) return const {};
  return {
    for (final voice in OfflineVoiceCatalog.voices)
      if (packages.contains(voice.package.id)) voice.id,
  };
});

/// Si [voice] puede leer ya, sin bajar nada.
bool isVoiceReady(VoiceProfile voice, Set<String> installed) =>
    voice.origin != VoiceOrigin.offline || installed.contains(voice.id);

/// El idioma de lo que se lee ahora (F47, paso 3): el del pedazo que suena,
/// o —sin nada sonando— el del texto que ofrece la pantalla. Es el que
/// «Te puede interesar» recomienda. `null` si no se sabe o no hay texto.
final readingLanguageProvider = Provider.autoDispose<String?>((ref) {
  final (segments, index) = ref.watch(
    readAloudControllerProvider.select((s) => (s.segments, s.segmentIndex)),
  );
  if (segments.isNotEmpty) return PassageLanguages.of(segments).at(index);
  final offered = ref.watch(currentReadableProvider);
  if (offered == null) return null;
  final all = offered.segmentsOf(ReadScope.all);
  return PassageLanguages.of(
    all.isNotEmpty ? all : offered.segmentsOf(offered.defaultScope),
  ).document;
});

/// Lo que se eligió en Filtrar de la biblioteca. Vive mientras la biblioteca
/// está abierta: al volver a abrirla, se ven todas.
final voiceFilterProvider = StateProvider.autoDispose<VoiceFilter>(
  (ref) => const VoiceFilter(),
);

/// Las voces favoritas, por su id, entre reinicios (F47, paso 3). En las
/// preferencias, como la voz elegida: es poco, y no es de la bóveda.
class VoiceFavoritesNotifier extends StateNotifier<Set<String>> {
  VoiceFavoritesNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super({...?prefs.getStringList(storageKey)});

  static const storageKey = 'narration_voice_favorites';

  final SharedPreferences _prefs;

  Future<void> toggle(String voiceId) async {
    state = state.contains(voiceId)
        ? ({...state}..remove(voiceId))
        : {...state, voiceId};
    await _prefs.setStringList(storageKey, state.toList()..sort());
  }
}

final voiceFavoritesProvider =
    StateNotifierProvider<VoiceFavoritesNotifier, Set<String>>(
      (ref) =>
          VoiceFavoritesNotifier(prefs: ref.watch(sharedPreferencesProvider)),
    );

/// Lo que hace sonar las muestras publicadas: un reproductor aparte del de la
/// lectura. Las pruebas lo cambian por uno de mentira.
final voiceSampleClipPlayerProvider = Provider<SpeechClipPlayer>((ref) {
  final player = VideoPlayerSpeechClipPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

/// Qué muestra se puede oír de [voice] (F47, paso 3): la que dice ella misma
/// —en su idioma— si ya puede leer, o la publicada si es una sin conexión
/// que todavía no se bajó. `null` si ninguna: una voz de un idioma sin
/// oración de muestra, o de Kokoro sin bajar (sus muestras publicadas no
/// están en su idioma).
VoiceSample? voiceSampleOf(VoiceProfile voice, Set<String> installed) {
  if (isVoiceReady(voice, installed)) {
    final text = voiceSampleText(voice.language);
    return text == null ? null : SpokenSample(text);
  }
  final url = voice.offline?.sampleUrl;
  return url == null ? null : PublishedSample(url);
}

sealed class VoiceSample {
  const VoiceSample();
}

/// La voz dice una oración de muestra, con el motor del lector.
class SpokenSample extends VoiceSample {
  const SpokenSample(this.text);

  final String text;
}

/// Suena la muestra que publicó sherpa-onnx: se oye antes de bajarla.
class PublishedSample extends VoiceSample {
  const PublishedSample(this.url);

  final String url;
}

/// La muestra que suena: el id de su voz, o `null` (F47, paso 3).
///
/// El motor de voz es uno solo, el del lector: una muestra dicha lo usa
/// prestado. Por eso, antes, el lector se pausa —y se entera de que su voz
/// ya no está puesta, ver [ReadAloudController.lendEngine]—, y si el lector
/// vuelve a sonar, la muestra se deja: lo que se lee manda.
class VoiceSampleController extends AutoDisposeNotifier<String?> {
  StreamSubscription<NarrationEvent>? _events;
  var _generation = 0;

  // Tomados al nacer: al soltarse, `ref` ya no se puede usar, y hay que
  // callar lo que suene.
  late SpeechClipPlayer _clips;
  late TextToSpeechService _tts;

  @override
  String? build() {
    _clips = ref.read(voiceSampleClipPlayerProvider);
    _tts = ref.read(textToSpeechServiceProvider);
    ref
      ..onDispose(() {
        unawaited(_events?.cancel());
        if (state != null) unawaited(_stopSound());
      })
      ..listen(readAloudControllerProvider.select((s) => s.playing), (
        _,
        playing,
      ) {
        if (playing && state != null) {
          _generation++;
          unawaited(_events?.cancel());
          unawaited(_clips.stop());
          state = null;
        }
      });
    return null;
  }

  /// Hace sonar la muestra de [voice]; si ya sonaba, la para.
  Future<void> toggle(VoiceProfile voice) async {
    if (state == voice.id) return stop();
    await stop();
    final sample = voiceSampleOf(voice, ref.read(installedVoiceIdsProvider));
    if (sample == null) return;
    final generation = ++_generation;
    state = voice.id;
    ref.read(audioFocusProvider.notifier).claim(readAloudFocusOwner);
    switch (sample) {
      case PublishedSample(:final url):
        await ref.read(readAloudControllerProvider.notifier).pause();
        try {
          await _clips.play(UrlSpeechClip(url));
        } on Object {
          // Sin conexión, o la muestra ya no está publicada: no suena, y
          // nada más.
        }
        if (generation == _generation) state = null;
      case SpokenSample(:final text):
        final reader = ref.read(readAloudControllerProvider.notifier);
        await reader.pause();
        reader.lendEngine();
        await _events?.cancel();
        _events = _tts.events.listen((_) {
          if (generation == _generation) state = null;
        });
        try {
          await _tts.setVoice(voice.voice);
          await _tts.speak(text);
        } on Exception {
          if (generation == _generation) state = null;
        }
    }
  }

  Future<void> stop() async {
    if (state == null) return;
    _generation++;
    state = null;
    await _stopSound();
  }

  Future<void> _stopSound() async {
    await _events?.cancel();
    _events = null;
    await _clips.stop();
    await _tts.stop();
  }
}

final voiceSampleProvider =
    AutoDisposeNotifierProvider<VoiceSampleController, String?>(
      VoiceSampleController.new,
    );

/// La voz que lee ahora, como voz de la biblioteca: la cara y el nombre que
/// muestra el reproductor (F47, paso 2) y el «Lee ahora» de la biblioteca.
/// `null` con la voz del sistema —la que tenga elegida el teléfono— o una
/// sin conexión que el catálogo ya no tiene.
final currentVoiceProfileProvider = Provider.autoDispose<VoiceProfile?>((ref) {
  final voice = ref.watch(readAloudControllerProvider.select((s) => s.voice));
  return voice == null ? null : voiceProfileOf(voice);
});
