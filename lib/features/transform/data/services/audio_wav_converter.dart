import 'dart:io';
import 'dart:isolate';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/transform/data/services/pcm_resampler.dart';

/// Convierte un audio —o la pista de audio de un video— al formato exacto
/// de Whisper: WAV de 16 kHz, mono, 16 bits, con cabecera de 44 bytes.
// ignore: one_member_abstracts
abstract interface class AudioWavConverter {
  Future<void> convert(String inputPath, String outputPath);
}

/// En Android, el conversor propio de la app (F22): el decodificador del
/// sistema vuelca el PCM crudo con el formato que entrega DE VERDAD
/// (`AudioToPcm.kt`), y Dart lo lleva a 16 kHz mono en un isolate
/// (`writeWhisperWav`). `audio_decoder` tomaba el formato que declara el
/// archivo, y un AAC eficiente (HE-AAC) —que declara la mitad de su
/// frecuencia— llegaba a Whisper con el doble de duración, y la
/// transcripción salía en disparates (medido en el teléfono del usuario:
/// 598,9 s de WAV para 299,4 s de audio); además hacía las cuentas muestra
/// por muestra en Kotlin interpretado, y tardaba 113 s por cada 5 minutos.
/// En las demás plataformas, `audio_decoder`, que ahí usa las APIs del
/// sistema sin ese defecto.
class PlatformAudioWavConverter implements AudioWavConverter {
  const PlatformAudioWavConverter({
    MethodChannel channel = const MethodChannel('app.sinapsis/audio'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> convert(String inputPath, String outputPath) async {
    if (!Platform.isAndroid) {
      await AudioDecoder.convertToWav(
        inputPath,
        outputPath,
        sampleRate: 16000,
        channels: 1,
      );
      return;
    }
    final rawPath = '$outputPath.pcm';
    try {
      final List<Object?> raw;
      try {
        raw =
            await _channel.invokeMethod<List<Object?>>('toRawPcm', {
              'input': inputPath,
              'output': rawPath,
            }) ??
            const [];
      } on PlatformException catch (e) {
        throw AudioConversionException(e.message ?? e.code);
      }
      final segments = [for (final s in raw) _segment(s! as Map)];
      if (segments.isEmpty) {
        throw const AudioConversionException('el archivo no trae audio');
      }
      await Isolate.run(() => writeWhisperWav(rawPath, segments, outputPath));
    } finally {
      final file = File(rawPath);
      if (file.existsSync()) file.deleteSync();
    }
  }

  static PcmSegment _segment(Map<Object?, Object?> map) => PcmSegment(
    offset: map['offset']! as int,
    length: map['length']! as int,
    sampleRate: map['sampleRate']! as int,
    channels: map['channels']! as int,
    encoding: PcmEncoding.values.byName(map['encoding']! as String),
  );
}

/// No se pudo leer el audio del archivo: formato que el teléfono no sabe
/// decodificar, archivo dañado, sin pista de audio.
class AudioConversionException implements Exception {
  const AudioConversionException(this.detail);

  final String detail;

  @override
  String toString() => 'No se pudo leer el audio: $detail';
}
