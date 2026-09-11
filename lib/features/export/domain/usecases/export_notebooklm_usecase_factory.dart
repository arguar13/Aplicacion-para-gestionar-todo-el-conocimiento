/// Elige la implementación del caso de uso de exportación a NotebookLM en
/// tiempo de compilación, igual que `platform_file_store.dart`.
library;

export 'export_notebooklm_usecase_factory_io.dart'
    if (dart.library.js_interop) 'export_notebooklm_usecase_factory_web.dart';
