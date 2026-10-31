import 'package:flutter/foundation.dart';

/// El micrófono, para grabar la muestra de una voz que se clona (F47, paso
/// 4).
///
/// Existe como contrato por lo de siempre: grabar necesita el micrófono de un
/// teléfono, y todo lo que lo usa se prueba con un doble.
abstract interface class VoiceRecorder {
  /// Si se puede grabar en este dispositivo.
  Future<bool> isAvailable();

  /// Pide el permiso del micrófono si hace falta; contesta si quedó concedido.
  Future<bool> requestPermission();

  /// Graba en [outputPath] —un WAV PCM de 16 bits, mono, a
  /// [kVoiceRecordingSampleRate]— hasta [stop] o hasta [limit]. Avisa el
  /// nivel y el tiempo mientras graba, y termina cuando el archivo quedó
  /// escrito. Falla con [VoiceRecorderException].
  Stream<RecordingProgress> record({
    required String outputPath,
    required Duration limit,
  });

  /// Termina la grabación: lo grabado hasta acá queda en el archivo.
  Future<void> stop();
}

/// La frecuencia a la que se graba: 44,1 kHz, la única que Android garantiza
/// en todos los teléfonos (`AudioRecord`).
const kVoiceRecordingSampleRate = 44100;

/// Cómo va una grabación.
@immutable
class RecordingProgress {
  const RecordingProgress({required this.level, required this.elapsed});

  /// El nivel de lo que entra, de 0 (silencio) a 1 (el tope).
  final double level;
  final Duration elapsed;
}

/// No se pudo grabar.
class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.code);

  /// `permission`, `busy`, `audio` o `unavailable`.
  final String code;

  @override
  String toString() => 'No se pudo grabar: $code';
}
