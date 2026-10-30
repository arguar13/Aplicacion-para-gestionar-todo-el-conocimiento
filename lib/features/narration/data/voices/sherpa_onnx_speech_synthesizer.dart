/// El motor de las voces sin conexión de cada plataforma (F47, paso 3): el de
/// sherpa-onnx nativo fuera de la web, y ninguno en la web, donde las voces
/// sin conexión no se ofrecen.
library;

export 'sherpa_onnx_speech_synthesizer_io.dart'
    if (dart.library.js_interop) 'sherpa_onnx_speech_synthesizer_web.dart';
