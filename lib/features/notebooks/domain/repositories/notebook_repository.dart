import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';

/// Los cuadernos (F16, D1): un subconjunto con nombre de la bóveda, manual o
/// por consulta guardada.
abstract interface class NotebookRepository {
  /// Todos, emitiendo de nuevo cada vez que algo cambia.
  Stream<List<Notebook>> watchAll();

  /// Uno solo, o `null` si no existe o se borró —para que la pantalla de
  /// detalle sepa volver en vez de quedarse mostrando un cuaderno fantasma—.
  Stream<Notebook?> watchById(String id);

  /// Los ids de un cuaderno [NotebookMode.manual], emitiendo de nuevo cada
  /// vez que [addItem]/[removeItem] cambian algo. Vacío en modo `query`: la
  /// pertenencia ahí no vive en `notebook_item`.
  Stream<Set<String>> watchItemIds(String notebookId);

  /// Crea un cuaderno nuevo. [query] es obligatorio en
  /// [NotebookMode.query] e ignorado en [NotebookMode.manual] —empieza sin
  /// elementos, se agregan con [addItem]—.
  Future<Notebook> create({
    required String name,
    required NotebookMode mode,
    LibraryQuery? query,
  });

  Future<void> rename({required String id, required String name});

  Future<void> delete(String id);

  /// Agrega [itemId] a un cuaderno [NotebookMode.manual]. Ya estar adentro
  /// no es un error: no hace nada.
  Future<void> addItem({required String notebookId, required String itemId});

  /// Saca [itemId] de un cuaderno [NotebookMode.manual]. El elemento sigue
  /// existiendo en la bóveda; solo deja de contar como parte de este
  /// cuaderno.
  Future<void> removeItem({required String notebookId, required String itemId});

  /// Qué buscar para traer los elementos de este cuaderno: la consulta
  /// guardada en modo [NotebookMode.query], o [LibraryQuery.ids] con lo que
  /// [addItem]/[removeItem] dejaron en modo [NotebookMode.manual].
  Future<LibraryQuery> resolveQuery(String notebookId);
}
