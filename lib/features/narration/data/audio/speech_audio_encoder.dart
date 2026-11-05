import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/transform/data/services/pcm_resampler.dart';

/// Lo que comprime el audio armado (F47, pasos 5 y 6): de WAV a M4A.
///
/// Un podcast de 15 minutos en WAV (24 kHz, mono, 16 bits) son 43 MB; en
/// M4A con AAC a [PlatformSpeechAudioEncoder.bitRate], unos 7. En un teléfono
/// eso es la diferencia entre guardar diez podcasts o setenta.
// ignore: one_member_abstracts
abstract interface class SpeechAudioEncoder {
  /// Comprime el WAV [wavPath] en el M4A [m4aPath]. Devuelve `false` si en
  /// esta plataforma no hay con qué —el WAV queda como está—, y lanza si se
  /// intentó y falló.
  Future<bool> toM4a(String wavPath, String m4aPath);
}

/// [SpeechAudioEncoder] con el codificador AAC del sistema, en Android
/// (`WavToM4a.kt`, por el canal de audio de la app): lee el WAV del disco de
/// a pedazos y escribe el M4A con `MediaMuxer`, así que una hora de audio no
/// pasa nunca entera por la memoria.
///
/// No es `audio_decoder.convertToM4a`, que la app ya trae: ese decodifica el
/// archivo entero a una lista en memoria antes de comprimirlo —un audio de
/// una hora son 170 MB de muestras— y un `OutOfMemoryError` no es una
/// `Exception`: tumbaría la app entera, con la cola de procesamiento adentro.
/// Tampoco se suma ningún paquete: el codificador es el del teléfono.
class PlatformSpeechAudioEncoder implements SpeechAudioEncoder {
  const PlatformSpeechAudioEncoder({
    MethodChannel channel = const MethodChannel('app.sinapsis/audio'),
    bool? android,
  }) : _channel = channel,
       _android = android;

  /// Lo que se le pide al AAC: la voz se oye limpia desde unos 48 kb/s en
  /// mono; 64 deja margen para la música de fondo que no hay.
  static const bitRate = 64000;

  final MethodChannel _channel;
  final bool? _android;

  @override
  Future<bool> toM4a(String wavPath, String m4aPath) async {
    if (!(_android ?? Platform.isAndroid)) return false;
    try {
      await _channel.invokeMethod<void>('wavToM4a', {
        'input': wavPath,
        'output': m4aPath,
        'bitRate': bitRate,
      });
    } on PlatformException catch (e) {
      throw FileSystemException(e.message ?? e.code, m4aPath);
    }
    return true;
  }
}

/// Lo que lleva a WAV un tramo que un motor dejó en otro formato (F47): el
/// MP3 que devuelve una voz de la nube (`VoiceCloud.speak`, paso 4). La
/// pieza común pasa por acá todo tramo que no empieza como un WAV, antes de
/// armar.
// ignore: one_member_abstracts
abstract interface class SpeechClipDecoder {
  /// Decodifica [inputPath] y lo deja en [wavPath], mono, de 16 bits y a 24
  /// kHz. Devuelve `false` si en esta plataforma no hay con qué, y lanza si
  /// se intentó y falló.
  Future<bool> toWav(String inputPath, String wavPath);
}

/// [SpeechClipDecoder] con el decodificador del sistema que la app ya usa
/// para transcribir (`AudioToPcm.kt`, F22): el PCM con el formato que de
/// verdad entrega, llevado a WAV en un isolate (`writeSpeechWavFromRaw`).
/// Sin paquetes nuevos.
class PlatformSpeechClipDecoder implements SpeechClipDecoder {
  const PlatformSpeechClipDecoder({
    MethodChannel channel = const MethodChannel('app.sinapsis/audio'),
    bool? android,
  }) : _channel = channel,
       _android = android;

  final MethodChannel _channel;
  final bool? _android;

  @override
  Future<bool> toWav(String inputPath, String wavPath) async {
    if (!(_android ?? Platform.isAndroid)) return false;
    final rawPath = '$wavPath.pcm';
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
        throw FileSystemException(e.message ?? e.code, inputPath);
      }
      final segments = [
        for (final s in raw)
          if (s is Map)
            PcmSegment(
              offset: s['offset']! as int,
              length: s['length']! as int,
              sampleRate: s['sampleRate']! as int,
              channels: s['channels']! as int,
              encoding: PcmEncoding.values.byName(s['encoding']! as String),
            ),
      ];
      if (segments.isEmpty) {
        throw FileSystemException('el tramo no trae audio', inputPath);
      }
      await Isolate.run(
        () => writeSpeechWavFromRaw(rawPath, segments, wavPath),
      );
      return true;
    } finally {
      final file = File(rawPath);
      if (file.existsSync()) file.deleteSync();
    }
  }
}
