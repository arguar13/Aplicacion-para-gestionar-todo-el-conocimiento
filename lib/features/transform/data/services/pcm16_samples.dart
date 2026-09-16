import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Convierte PCM de 16 bits con signo, en little-endian, a las muestras
/// normalizadas entre -1.0 y 1.0 que pide `OfflineStream.acceptWaveform()`.
///
/// Lo único que cambia entre plataformas es de dónde salen esos bytes —un
/// WAV en disco fuera de la web, los bytes en memoria que devuelve
/// `AudioDecoder.convertToWavBytes()` ahí—, nunca cómo se interpretan: por
/// eso esta conversión es una sola función, no una por plataforma.
///
/// [headerBytes] son los que hay que saltear antes de que empiecen los
/// datos: 44 para un WAV con su cabecera RIFF completa, 0 para el PCM en
/// crudo que devuelve `convertToWavBytes(includeHeader: false)`.
Float32List pcm16ToFloat32Samples(Uint8List bytes, {int headerBytes = 0}) {
  final data = ByteData.sublistView(bytes, headerBytes);
  final sampleCount = data.lengthInBytes ~/ 2;

  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Cuántas muestras entran en la ventana de audio que espera Whisper, a la
/// frecuencia con la que está entrenado el modelo.
const whisperChunkSamples = 16000 * 30;

/// Transcribe [samples] entero, partido en ventanas de [chunkSamples], y
/// concatena el texto de cada una.
///
/// Whisper —a diferencia de un modelo de streaming— está entrenado sobre
/// un espectrograma de ancho **fijo**, 30 segundos: `OfflineStream` no
/// rechaza un audio más largo, pero el modelo igual lo recorta a esa
/// ventana antes de mirar una sola muestra, así que sin este corte un
/// audio de una hora transcribe nada más que sus primeros 30 segundos, sin
/// ningún error que lo avise. Partirlo acá, del lado de Dart, en tantos
/// `OfflineStream` como haga falta —uno por ventana, con su propio
/// `acceptWaveform`/`decode`— es lo que deja transcribir el audio entero.
///
/// El corte es en un punto fijo del reloj, no en un silencio: encontrar
/// silencios reales pediría un detector de actividad de voz aparte, y una
/// palabra partida justo en el borde de una ventana pierde como mucho esa
/// palabra, no el resto de la transcripción — el mismo compromiso que hace
/// la propia herramienta de línea de comandos de Whisper para un audio
/// largo sin ese detector.
///
/// Mismo motivo por el que esta función es una sola, no una por
/// plataforma, que [pcm16ToFloat32Samples]: `OfflineRecognizer` y
/// `OfflineStream` son la misma API de sherpa-onnx en las dos, solo cambia
/// cómo se consiguen los bytes de origen.
String transcribeInChunks(
  sherpa_onnx.OfflineRecognizer recognizer,
  Float32List samples, {
  int sampleRate = 16000,
  int chunkSamples = whisperChunkSamples,
}) {
  final buffer = StringBuffer();

  for (var offset = 0; offset < samples.length; offset += chunkSamples) {
    final end = (offset + chunkSamples).clamp(0, samples.length);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(
        samples: samples.sublist(offset, end),
        sampleRate: sampleRate,
      );
      recognizer.decode(stream);

      final text = recognizer.getResult(stream).text.trim();
      if (text.isEmpty) continue;

      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    } finally {
      stream.free();
    }
  }

  return buffer.toString();
}
