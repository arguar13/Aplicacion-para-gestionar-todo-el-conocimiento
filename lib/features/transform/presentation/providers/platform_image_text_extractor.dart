/// Elige la implementación de `ImageTextExtractor` en tiempo de
/// compilación, igual que `platform_file_store.dart`.
library;

export 'platform_image_text_extractor_io.dart'
    if (dart.library.js_interop) 'platform_image_text_extractor_web.dart';
