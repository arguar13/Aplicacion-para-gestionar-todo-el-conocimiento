import 'dart:io';

import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// Las voces propias —clonadas y creadas, F47, paso 4— en la pieza común del
/// audio (`SpeechAudioRenderer`): `mia:<id>`, el mismo nombre con que las
/// pide el lector.
///
/// - **Las creadas en el teléfono** leen con Kokoro, como en el lector: su
///   voz sin conexión ([MyVoicesService.offlineVoiceOf]) con el `voices.bin`
///   de las creadas ([MyVoicesService.engineConfigOf]), a velocidad 1 por su
///   ritmo propio —la velocidad se elige al escuchar, no al generar—. Son
///   gratis.
/// - **Las de ElevenLabs** piden cada tramo a la nube y dejan el MP3 tal
///   cual en `outputPath`: la pieza común lo pasa a WAV. Cobran
///   ([ElevenLabsFacts.creditsPerCharacter]), así que antes de generar se
///   dice el costo y se aprueba voz por voz (`cloudReadingGateProvider`).
class MySpeechVoiceRenderer implements SpeechVoiceRenderer {
  MySpeechVoiceRenderer({
    required MyVoicesService Function() service,
    required VoiceCloud Function() cloud,
    required OfflineSpeechSynthesizer? synthesizer,
    required List<MyVoice> Function() known,
    required Future<Set<String>> Function() ready,
  }) : _service = service,
       _cloud = cloud,
       _synthesizer = synthesizer,
       _known = known,
       _ready = ready;

  /// Se piden al usarlos, no al armar el renderer: la lista de quienes hacen
  /// voces se arma aunque nunca se genere con una propia.
  final MyVoicesService Function() _service;
  final VoiceCloud Function() _cloud;
  final OfflineSpeechSynthesizer? _synthesizer;

  /// Las voces que ya se conocen, sin esperar: lo que necesita [priceOf],
  /// que no puede esperar.
  final List<MyVoice> Function() _known;

  /// Las que pueden leer ya, por su nombre de lector (`mia:<id>`):
  /// `readyMyVoiceNamesProvider`, una vez sabidas las voces y los paquetes.
  final Future<Set<String>> Function() _ready;

  /// Lo que cobra una voz de ElevenLabs por cada mil caracteres: en créditos
  /// del plan, no en dinero —lo que vale un crédito depende del plan de cada
  /// persona—. Es lo que dice el aviso del costo.
  static const cloudPrice = SpeechAudioPrice(
    per1000Characters: 1000.0 * ElevenLabsFacts.creditsPerCharacter,
    currency: ElevenLabsFacts.creditsCurrency,
  );

  static String? _idOf(String voiceId) => voiceId.startsWith(myVoicePrefix)
      ? voiceId.substring(myVoicePrefix.length)
      : null;

  @override
  bool owns(String voiceId) => voiceId.startsWith(myVoicePrefix);

  @override
  Future<bool> isReady(String voiceId) async =>
      owns(voiceId) && (await _ready()).contains(voiceId);

  /// Las de ElevenLabs cobran; las del teléfono, no. **Una que todavía no se
  /// conoce cobra**: sin saber dónde vive, se pregunta antes, y no se gasta
  /// sin aprobar.
  @override
  SpeechAudioPrice? priceOf(String voiceId) {
    final id = _idOf(voiceId);
    if (id == null) return null;
    final voice = _known().where((v) => v.id == id).firstOrNull;
    return voice?.home == MyVoiceHome.phone ? null : cloudPrice;
  }

  /// Una voz propia no cambia —su mezcla y su id en la nube se fijan al
  /// crearla—: lo que puede cambiar es el motor, el paquete de Kokoro o el
  /// modelo con que lee ElevenLabs. Sin depender de [_known], para que un
  /// tramo ya pagado se reuse aunque las voces no se hayan cargado todavía.
  @override
  String versionOf(String voiceId) =>
      'mia|kokoro:${OfflineVoiceCatalog.kokoro.sha256}'
      '|elevenlabs:${ElevenLabsFacts.readingModel}';

  @override
  Future<Duration> render({
    required String voiceId,
    required String text,
    required String outputPath,
  }) async {
    final id = _idOf(voiceId);
    final voices = await _service().list();
    final voice = voices.where((v) => v.id == id).firstOrNull;
    if (voice == null) {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
        detail: 'la voz propia ya no está',
      );
    }
    return switch (voice.home) {
      MyVoiceHome.phone => _renderOnPhone(voice, voiceId, text, outputPath),
      MyVoiceHome.elevenLabs => _renderInCloud(
        voice,
        voiceId,
        text,
        outputPath,
      ),
    };
  }

  Future<Duration> _renderOnPhone(
    MyVoice voice,
    String voiceId,
    String text,
    String outputPath,
  ) async {
    final service = _service();
    final offline = await service.offlineVoiceOf(voice.narrationVoice);
    final engine = offline == null
        ? null
        : await service.engineConfigOf(offline);
    final synthesizer = _synthesizer;
    if (offline == null || engine == null || synthesizer == null) {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
        detail: 'sin Kokoro, o sin lugar en el voices.bin de las creadas',
      );
    }
    try {
      return await synthesizer.synthesize(
        engine: engine,
        speakerId: offline.speakerId,
        text: text,
        // A velocidad 1, con el ritmo propio de la voz creada.
        speed: offline.pace,
        outputPath: outputPath,
      );
    } on OfflineSpeechException catch (e) {
      throw SpeechAudioException(
        SpeechAudioFailure.engine,
        voiceId: voiceId,
        detail: e.detail,
      );
    }
  }

  Future<Duration> _renderInCloud(
    MyVoice voice,
    String voiceId,
    String text,
    String outputPath,
  ) async {
    final cloudVoiceId = voice.cloudVoiceId;
    if (cloudVoiceId == null) {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
        detail: 'la voz no tiene su id en ElevenLabs',
      );
    }
    try {
      final audio = await _cloud().speak(voiceId: cloudVoiceId, text: text);
      await File(outputPath).writeAsBytes(audio, flush: true);
      // Cuánto dura lo dice el WAV al que lo lleva la pieza común.
      return Duration.zero;
    } on VoiceCloudException catch (e) {
      throw SpeechAudioException(
        e.failure == VoiceCloudFailure.voiceNotFound
            ? SpeechAudioFailure.voiceMissing
            : SpeechAudioFailure.engine,
        voiceId: voiceId,
        detail: 'ElevenLabs: ${e.failure.name}',
      );
    }
  }
}
