/// Elige la implementación de `WhisperModelManager` en tiempo de
/// compilación, igual que `platform_file_store.dart`.
library;

export 'platform_whisper_model_manager_io.dart'
    if (dart.library.js_interop) 'platform_whisper_model_manager_web.dart';
