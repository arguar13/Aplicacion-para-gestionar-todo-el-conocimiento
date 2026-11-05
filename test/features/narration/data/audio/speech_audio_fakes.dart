import 'dart:io';

import 'package:sinapsis/features/narration/data/audio/speech_audio_encoder.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';

/// Unas voces de mentira para la pieza común del audio (F47): las de prefijo
/// `fake:`. Cada tramo es un tono de 400 ms con 100 ms de silencio de cada
/// lado, como deja un motor de verdad.
class FakeVoiceRenderer implements SpeechVoiceRenderer {
  FakeVoiceRenderer({this.prefix = 'fake:', this.sampleRate = 24000});

  final String prefix;
  final int sampleRate;

  /// Lo que se dijo, en orden: la voz y el texto.
  final said = <(String, String)>[];

  /// Las voces que no están en el teléfono.
  final missing = <String>{};

  final prices = <String, SpeechAudioPrice>{};
  String version = 'v1';

  /// La voz cuyo motor falla, la que no deja nada y si falla con un error
  /// suelto.
  String? failOn;
  String? silentOn;
  bool throwRaw = false;

  /// Lo que pasa al decir cada tramo, antes de escribirlo.
  void Function(String voiceId, String text)? onSay;

  /// Las voces que dejan su tramo en otro formato, como el MP3 de una voz de
  /// la nube: unos bytes que no son un WAV.
  final mp3 = <String>{};

  @override
  bool owns(String voiceId) => voiceId.startsWith(prefix);

  @override
  Future<bool> isReady(String voiceId) async => !missing.contains(voiceId);

  @override
  SpeechAudioPrice? priceOf(String voiceId) => prices[voiceId];

  @override
  String versionOf(String voiceId) => version;

  @override
  Future<Duration> render({
    required String voiceId,
    required String text,
    required String outputPath,
  }) async {
    if (throwRaw) throw StateError('se rompió');
    if (voiceId == failOn) {
      throw SpeechAudioException(SpeechAudioFailure.engine, voiceId: voiceId);
    }
    said.add((voiceId, text));
    onSay?.call(voiceId, text);
    if (voiceId == silentOn) return Duration.zero;
    if (mp3.contains(voiceId)) {
      File(outputPath).writeAsBytesSync(fakeMp3);
      return Duration.zero;
    }
    final edge = sampleRate ~/ 10;
    File(outputPath).writeAsBytesSync(
      encodeMonoWav([
        for (var i = 0; i < edge; i++) 0,
        for (var i = 0; i < sampleRate * 2 ~/ 5; i++) 0.5,
        for (var i = 0; i < edge; i++) 0,
      ], sampleRate),
    );
    return const Duration(milliseconds: 600);
  }
}

/// Un codificador de mentira: copia el WAV con otra extensión.
class FakeEncoder implements SpeechAudioEncoder {
  bool supported = true;
  bool fail = false;
  final calls = <(String, String)>[];

  @override
  Future<bool> toM4a(String wavPath, String m4aPath) async {
    if (!supported) return false;
    if (fail) throw const FileSystemException('sin lugar');
    calls.add((wavPath, m4aPath));
    File(wavPath).copySync(m4aPath);
    return true;
  }
}

/// Lo que deja una voz de mentira de la nube: empieza como un MP3.
final fakeMp3 = [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6];

/// Un decodificador de mentira: lo que no es WAV lo vuelve un tono de 400
/// ms, como si el sistema lo hubiera decodificado.
class FakeDecoder implements SpeechClipDecoder {
  bool supported = true;
  bool fail = false;
  final calls = <String>[];

  @override
  Future<bool> toWav(String inputPath, String wavPath) async {
    calls.add(inputPath);
    if (!supported) return false;
    if (fail) throw const FileSystemException('no se pudo decodificar');
    File(wavPath).writeAsBytesSync(
      encodeMonoWav([for (var i = 0; i < 9600; i++) 0.5], 24000),
    );
    return true;
  }
}
