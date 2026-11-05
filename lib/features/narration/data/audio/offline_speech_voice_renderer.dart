import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// Las voces sin conexión (Piper y Kokoro, F47, paso 3) en la pieza común
/// del audio (`SpeechAudioRenderer`): `offline:<id del catálogo>`.
///
/// Con el mismo motor que el lector —`sherpa_onnx` en su isolate, hasta dos
/// voces armadas—, así que generar un podcast de dos voces no carga más de lo
/// que carga leer un texto en dos idiomas. Siempre a velocidad 1: la velocidad
/// se elige al escuchar, no al generar.
class OfflineSpeechVoiceRenderer implements SpeechVoiceRenderer {
  OfflineSpeechVoiceRenderer({
    required OfflineSpeechSynthesizer synthesizer,
    required Future<OfflineVoiceEngineConfig?> Function(OfflineVoice voice)
    engineOf,
  }) : _synthesizer = synthesizer,
       _engineOf = engineOf;

  final OfflineSpeechSynthesizer _synthesizer;
  final Future<OfflineVoiceEngineConfig?> Function(OfflineVoice voice)
  _engineOf;

  OfflineVoice? _voiceOf(String voiceId) {
    final id = SpeechVoiceIds.offlineIdOf(voiceId);
    return id == null ? null : OfflineVoiceCatalog.byId(id);
  }

  @override
  bool owns(String voiceId) => voiceId.startsWith(SpeechVoiceIds.offlinePrefix);

  @override
  Future<bool> isReady(String voiceId) async {
    final voice = _voiceOf(voiceId);
    return voice != null && await _engineOf(voice) != null;
  }

  @override
  SpeechAudioPrice? priceOf(String voiceId) => null;

  /// El paquete y su huella: una voz que se vuelve a publicar con otro modelo
  /// suena distinta, y lo generado con la anterior no se mezcla.
  @override
  String versionOf(String voiceId) {
    final voice = _voiceOf(voiceId);
    return voice == null
        ? 'sherpa'
        : 'sherpa|${voice.package.id}|${voice.package.sha256}';
  }

  @override
  Future<Duration> render({
    required String voiceId,
    required String text,
    required String outputPath,
  }) async {
    final voice = _voiceOf(voiceId);
    final engine = voice == null ? null : await _engineOf(voice);
    if (voice == null || engine == null) {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
        detail: 'la voz sin conexión no está en el teléfono',
      );
    }
    try {
      return await _synthesizer.synthesize(
        engine: engine,
        speakerId: voice.speakerId,
        text: text,
        speed: 1,
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
}
