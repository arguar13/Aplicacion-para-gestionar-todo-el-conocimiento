/// Elige la implementación de `FileOpener` en tiempo de compilación, igual
/// que `platform_file_store.dart`.
library;

export 'platform_file_opener_io.dart'
    if (dart.library.js_interop) 'platform_file_opener_web.dart';
