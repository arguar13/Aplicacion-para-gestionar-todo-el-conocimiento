/// Elige la implementación de `AudioTranscriber` en tiempo de compilación,
/// igual que `platform_file_store.dart`.
library;

export 'platform_audio_transcriber_io.dart'
    if (dart.library.js_interop) 'platform_audio_transcriber_web.dart';
