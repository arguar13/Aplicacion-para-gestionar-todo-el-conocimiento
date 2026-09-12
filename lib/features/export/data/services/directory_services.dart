/// Elige, en tiempo de compilación, cómo se elige y se escribe la carpeta
/// del paquete de NotebookLM fuera de la web —igual que
/// `export_notebooklm_usecase_factory.dart`—.
library;

export 'directory_services_io.dart'
    if (dart.library.js_interop) 'directory_services_web.dart';
