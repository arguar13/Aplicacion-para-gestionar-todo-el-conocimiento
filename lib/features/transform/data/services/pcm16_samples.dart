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
///
/// 29 segundos y no los 30 de la ventana de Whisper: sherpa-onnx se reserva
/// 50 cuadros —medio segundo— de relleno al final, y todo lo que pase de
/// 29,5 s lo descarta con un aviso ("Only waves less than 30 seconds are
/// supported"). Con tramos de 30 s se perdía el último medio segundo de
/// cada uno: palabras sueltas en cada borde, cada medio minuto —medido en
/// el emulador (F21): 28 avisos en 30 tramos llenos—.
const whisperChunkSamples = 16000 * 29;

/// Transcribe UNA ventana de Whisper —hasta 29 segundos, ver
/// [whisperChunkSamples]—: el tramo que se transcribe, se guarda y se retoma
/// de a uno en un audio largo (F21). Whisper está entrenado sobre un
/// espectrograma de ancho **fijo**, 30 segundos, y recorta a esa ventana
/// cualquier audio que reciba: un audio largo hay que partirlo antes —ver
/// `planWindows` en `speech_windows.dart` (F22)—.
String transcribeWindow(
  sherpa_onnx.OfflineRecognizer recognizer,
  Float32List samples, {
  int sampleRate = 16000,
}) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
  }
}
