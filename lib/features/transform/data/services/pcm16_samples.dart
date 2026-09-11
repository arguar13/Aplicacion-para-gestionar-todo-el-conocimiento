import 'dart:typed_data';

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
