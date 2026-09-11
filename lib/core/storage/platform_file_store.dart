/// Elige la implementación de `FileStore` en tiempo de compilación: la
/// nativa sobre `dart:io`, o la de OPFS en la web —nunca las dos en el
/// mismo binario, cada una importa justo lo que su plataforma sabe
/// resolver—. Mismo mecanismo que usa `sherpa_onnx` puertas adentro para
/// elegir entre su implementación nativa y la de WebAssembly.
library;

export 'platform_file_store_io.dart'
    if (dart.library.js_interop) 'platform_file_store_web.dart';
