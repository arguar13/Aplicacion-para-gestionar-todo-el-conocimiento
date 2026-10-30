import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';

/// En la web no hay motor sin conexión (F47, paso 3): el TTS de sherpa-onnx
/// para la web necesita su propio `.wasm` y el modelo en la memoria de la
/// pestaña, y las voces se bajan al teléfono. Lee la voz del sistema.
OfflineSpeechSynthesizer? createOfflineSpeechSynthesizer() => null;
