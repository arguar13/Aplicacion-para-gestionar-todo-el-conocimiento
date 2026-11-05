import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/narration/data/voices/cloud_text_to_speech_service.dart';
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/data/voices/method_channel_voice_recorder.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/data/voices/video_player_speech_clip_player.dart';
import 'package:sinapsis/features/narration/data/voices/voice_sample_tools.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/services/voice_recorder.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/transform/data/services/audio_wav_converter.dart';

/// Si este dispositivo tiene la pestaña Mías con voces (F47, paso 4): donde
/// leen las voces sin conexión —Android—, que es donde se graba, se mezcla
/// Kokoro y suenan los tramos de la nube. En la web y en Windows, Mías
/// explica que es del teléfono.
final myVoicesAvailableProvider = Provider<bool>(
  (ref) => ref.watch(offlineVoicesAvailableProvider),
);

/// Dónde se guardan: la carpeta de documentos, la de la bóveda.
final myVoicesStoreProvider = Provider<MyVoicesStore>((ref) {
  final store = MyVoicesStore(rootDirectory: getApplicationDocumentsDirectory);
  ref.onDispose(() => unawaited(store.dispose()));
  return store;
});

/// La clave de ElevenLabs, en el almacén seguro.
final elevenLabsKeyStoreProvider = Provider<ElevenLabsKeyStore>(
  (ref) => ElevenLabsKeyStore(),
);

/// Si la nube para voces está prendida y si hay una clave cargada (F47, paso
/// 4): apagada de entrada (decisión F). En las preferencias si está prendida;
/// la clave, en el almacén seguro.
class VoiceCloudSettings {
  const VoiceCloudSettings({this.enabled = false, this.hasKey = false});

  final bool enabled;
  final bool hasKey;

  /// Si se puede usar: prendida y con clave.
  bool get ready => enabled && hasKey;
}

class VoiceCloudSettingsNotifier extends StateNotifier<VoiceCloudSettings> {
  VoiceCloudSettingsNotifier({
    required SharedPreferences prefs,
    required ElevenLabsKeyStore keys,
  }) : _prefs = prefs,
       _keys = keys,
       super(VoiceCloudSettings(enabled: prefs.getBool(enabledKey) ?? false)) {
    unawaited(_loadKey());
  }

  static const enabledKey = 'voice_cloud_enabled';

  final SharedPreferences _prefs;
  final ElevenLabsKeyStore _keys;

  Future<void> _loadKey() async {
    bool has;
    try {
      has = await _keys.read() != null;
      // Un almacén seguro que no se puede leer —un teléfono con el almacén
      // de claves roto, una plataforma sin él— es como no tener clave: la
      // nube no se usa, y la pantalla pide cargarla de nuevo.
    } on Exception {
      has = false;
    }
    if (mounted) {
      state = VoiceCloudSettings(enabled: state.enabled, hasKey: has);
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = VoiceCloudSettings(enabled: enabled, hasKey: state.hasKey);
    await _prefs.setBool(enabledKey, enabled);
  }

  Future<void> saveKey(String key) async {
    await _keys.write(key);
    state = VoiceCloudSettings(enabled: state.enabled, hasKey: true);
  }

  Future<void> deleteKey() async {
    await _keys.delete();
    state = VoiceCloudSettings(enabled: state.enabled);
  }
}

final voiceCloudSettingsProvider =
    StateNotifierProvider<VoiceCloudSettingsNotifier, VoiceCloudSettings>(
      (ref) => VoiceCloudSettingsNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
        keys: ref.watch(elevenLabsKeyStoreProvider),
      ),
    );

/// El cliente HTTP de ElevenLabs: sin registrar lo que viaja —el texto que se
/// lee, el audio de la muestra—, como el de la IA en la nube (F32).
final voiceCloudDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(minutes: 2),
      headers: const {'User-Agent': 'Sinapsis/0.1'},
    ),
  ),
);

/// ElevenLabs, con la clave cargada **solo si la nube está prendida**: si se
/// apaga, nada sale, aunque la clave siga guardada. Las pruebas lo cambian
/// por un doble: nunca se llama a ElevenLabs de verdad.
final voiceCloudProvider = Provider<VoiceCloud>((ref) {
  final keys = ref.watch(elevenLabsKeyStoreProvider);
  return ElevenLabsVoiceCloud(
    dio: ref.watch(voiceCloudDioProvider),
    key: () async =>
        ref.read(voiceCloudSettingsProvider).enabled ? keys.read() : null,
  );
});

/// Clonar, crear y borrar las voces de Mías.
final myVoicesServiceProvider = Provider<MyVoicesService>(
  (ref) => MyVoicesService(
    store: ref.watch(myVoicesStoreProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
    files: ref.watch(offlineVoiceFilesProvider),
    synthesizer: ref.watch(offlineSpeechSynthesizerProvider),
    cloud: ref.watch(voiceCloudProvider),
  ),
);

/// Las voces de Mías, al día con cada una que se guarda o se borra. Vacía
/// donde no se ofrecen.
final myVoicesProvider = StreamProvider<List<MyVoice>>((ref) async* {
  if (!ref.watch(myVoicesAvailableProvider)) {
    yield const [];
    return;
  }
  final service = ref.watch(myVoicesServiceProvider);
  yield await service.list();
  await for (final _ in service.changes()) {
    yield await service.list();
  }
});

/// Las voces de Mías que pueden leer ya, por su nombre de lector
/// (`mia:<id>`): las creadas en el teléfono con el paquete de Kokoro bajado y
/// lugar en el `voices.bin` de las creadas,
/// y las de ElevenLabs con la nube prendida y su clave.
final readyMyVoiceNamesProvider = Provider<Set<String>>((ref) {
  final voices = ref.watch(myVoicesProvider).valueOrNull ?? const [];
  if (voices.isEmpty) return const {};
  final kokoro =
      ref
          .watch(installedVoicePackagesProvider)
          .valueOrNull
          ?.contains(OfflineVoiceCatalog.kokoro.id) ??
      false;
  final cloud = ref.watch(voiceCloudSettingsProvider).ready;
  // Las creadas en el teléfono que caben en el `voices.bin` de las creadas.
  final slots = blendSlots(voices);
  return {
    for (final voice in voices)
      if (switch (voice.home) {
        MyVoiceHome.phone => kokoro && slots.containsKey(voice.id),
        MyVoiceHome.elevenLabs => cloud,
      })
        voice.narrationVoice.name,
  };
});

/// El micrófono, para grabar la muestra de una clonada. Las pruebas lo
/// cambian por un doble.
final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => const MethodChannelVoiceRecorder(),
);

/// Medir la muestra y traer un audio que se sube, en la carpeta temporal.
/// Las pruebas lo cambian por uno que no usa isolates ni el conversor.
final voiceSampleToolsProvider = Provider<VoiceSampleTools>(
  (ref) => VoiceSampleTools(
    converter: const PlatformAudioWavConverter(),
    workDirectory: () async =>
        Directory(p.join((await getTemporaryDirectory()).path, 'voz-muestra')),
  ),
);

/// Dónde se dejan los audios que se escuchan al crear una voz: la muestra de
/// una mezcla, las propuestas de ElevenLabs.
final voicePreviewDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join((await getTemporaryDirectory()).path, 'voz-propuestas'),
      )..createSync(recursive: true),
);

/// El lector con las voces de la nube, para el motor del lector; `null` donde
/// no se ofrecen. No depende de si la nube está prendida —eso lo decide qué
/// voces pueden leer, y la clave que se manda—: así prenderla o apagarla no
/// rearma el motor del lector.
final cloudTextToSpeechServiceProvider = Provider<TextToSpeechService?>((ref) {
  if (!ref.watch(myVoicesAvailableProvider)) return null;
  final cloud = ref.watch(voiceCloudProvider);
  final store = ref.watch(myVoicesStoreProvider);
  final player = VideoPlayerSpeechClipPlayer();
  final service = CloudTextToSpeechService(
    cloud: cloud,
    player: player,
    cloudVoiceIdOf: (voice) async {
      final id = myVoiceIdOf(voice);
      if (id == null) return null;
      final voices = await store.list();
      return voices.where((v) => v.id == id).firstOrNull?.cloudVoiceId;
    },
    clipsDirectory: () async => Directory(
      p.join((await getTemporaryDirectory()).path, 'voz-en-la-nube'),
    ),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
    unawaited(player.dispose());
  });
  return service;
});

/// El plan y lo gastado en ElevenLabs, cuando se pide: al abrir la nube para
/// voces y antes de clonar o crear. Cada pedido lo vuelve a preguntar.
final voiceCloudAccountProvider = FutureProvider.autoDispose<VoiceCloudAccount>(
  (ref) => ref.watch(voiceCloudProvider).account(),
);
