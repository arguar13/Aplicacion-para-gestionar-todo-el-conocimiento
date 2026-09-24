/// En qué forma se ve la biblioteca: la lista de siempre, una tabla al
/// estilo de una base de datos de Notion, o un tablero que agrupa por
/// tema.
///
/// Vive en el dominio (F16) porque una vista guardada la persiste junto con
/// su filtro y su orden: dejó de ser solo una preferencia de la sesión —ver
/// `SavedView`—. La pantalla sigue siendo la única que sabe de íconos y
/// etiquetas para cada valor.
enum LibraryViewMode { list, table, kanban, calendar }
