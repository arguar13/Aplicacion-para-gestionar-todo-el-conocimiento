/// Elige en tiempo de compilación cómo se bajan los archivos que enlaza una
/// página, igual que `platform_file_store.dart`: fuera de la web, solo de
/// internet y acotado; en la web, nada (ver `_web`).
library;

export 'platform_linked_file_fetcher_io.dart'
    if (dart.library.js_interop) 'platform_linked_file_fetcher_web.dart';
