import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';

/// Las voces del teléfono en la pieza común del audio (`SpeechAudioRenderer`,
/// F47): `device:<acento>:<nombre>`, y sin nombre la que el teléfono use para
/// ese acento.
///
/// En Android, con el motor del sistema por un canal propio
/// (`DeviceSpeechChannel.kt`), con su propia cola y no la del lector: generar
/// un podcast no corta lo que se está escuchando, ni lo que se escucha corta
/// lo que se genera. En las demás plataformas no se ofrece: `flutter_tts` no
/// guarda a un archivo en todas, y ahí tampoco hay voces sin conexión.
class DeviceSpeechVoiceRenderer implements SpeechVoiceRenderer {
  const DeviceSpeechVoiceRenderer({
    MethodChannel channel = const MethodChannel('app.sinapsis/device_speech'),
    this.timeout = const Duration(minutes: 2),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Lo más que se espera un tramo: un motor que no avisa nunca no deja el
  /// trabajo colgado para siempre.
  final Duration timeout;

  @override
  bool owns(String voiceId) => SpeechVoiceIds.deviceOf(voiceId) != null;

  /// Las del teléfono están siempre; si una se desinstaló, lo dice el motor
  /// al pedirle el tramo.
  @override
  Future<bool> isReady(String voiceId) async => owns(voiceId);

  @override
  SpeechAudioPrice? priceOf(String voiceId) => null;

  @override
  String versionOf(String voiceId) => 'device';

  @override
  Future<Duration> render({
    required String voiceId,
    required String text,
    required String outputPath,
  }) async {
    final device = SpeechVoiceIds.deviceOf(voiceId);
    if (device == null) {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
      );
    }
    try {
      await _channel
          .invokeMethod<void>('synthesize', {
            'text': text,
            'locale': device.locale,
            'voice': device.name,
            'output': outputPath,
          })
          .timeout(timeout);
    } on TimeoutException {
      throw SpeechAudioException(
        SpeechAudioFailure.engine,
        voiceId: voiceId,
        detail: 'el motor no terminó en ${timeout.inSeconds} s',
      );
    } on PlatformException catch (e) {
      throw SpeechAudioException(
        e.code == 'voice'
            ? SpeechAudioFailure.voiceMissing
            : SpeechAudioFailure.engine,
        voiceId: voiceId,
        detail: e.message ?? e.code,
      );
    } on MissingPluginException {
      throw SpeechAudioException(
        SpeechAudioFailure.voiceMissing,
        voiceId: voiceId,
        detail: 'sin el canal del motor del teléfono',
      );
    }
    return Duration.zero;
  }
}
