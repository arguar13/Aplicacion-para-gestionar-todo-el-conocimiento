import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// Con qué archivos se arma el motor de una voz sin conexión (F47, paso 3):
/// los que dejó en el teléfono su paquete, ya abierto.
@immutable
class OfflineVoiceEngineConfig {
  const OfflineVoiceEngineConfig({
    required this.family,
    required this.model,
    required this.tokens,
    required this.dataDir,
    this.voices,
    this.lexicon,
    this.espeakVoice,
  });

  final OfflineVoiceFamily family;

  /// Rutas absolutas.
  final String model;
  final String tokens;
  final String dataDir;

  /// Kokoro: los estilos de sus hablantes.
  final String? voices;

  /// Kokoro en inglés: el léxico.
  final String? lexicon;

  /// Kokoro en los demás idiomas: la voz de espeak-ng.
  final String? espeakVoice;

  /// Lo que distingue un motor de otro: el mismo modelo con otra forma de
  /// pronunciar —Kokoro en español y en francés— es otro motor.
  String get key => '$model|${lexicon ?? ''}|${espeakVoice ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is OfflineVoiceEngineConfig && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// El motor que dice un texto con una voz sin conexión y lo deja en un WAV
/// (F47, paso 3): `sherpa_onnx` en un isolate aparte, con la voz cargada
/// entre pedido y pedido.
///
/// Existe como contrato por lo de siempre: el motor de verdad necesita la
/// biblioteca nativa y un modelo de cientos de megas, así que todo lo que lo
/// usa se prueba con un doble. Donde no hay motor —la web, el escritorio—, no
/// hay instancia: las voces sin conexión no se ofrecen.
abstract interface class OfflineSpeechSynthesizer {
  /// Dice [text] con el hablante [speakerId] de [engine], a [speed] (1 es la
  /// velocidad normal de la voz), y deja el audio en [outputPath]. Devuelve
  /// cuánto dura. Falla con [OfflineSpeechException] si el motor no pudo.
  Future<Duration> synthesize({
    required OfflineVoiceEngineConfig engine,
    required int speakerId,
    required String text,
    required double speed,
    required String outputPath,
  });

  /// Suelta la voz cargada —cientos de megas de memoria— sin cerrar el
  /// motor: el próximo pedido la vuelve a cargar. Al borrar una voz.
  Future<void> release();

  Future<void> dispose();
}

/// El motor sin conexión no pudo decir algo.
class OfflineSpeechException implements Exception {
  const OfflineSpeechException(this.detail);

  /// Solo para el registro, nunca para mostrar.
  final String detail;

  @override
  String toString() => 'La voz sin conexión no pudo leer: $detail.';
}
