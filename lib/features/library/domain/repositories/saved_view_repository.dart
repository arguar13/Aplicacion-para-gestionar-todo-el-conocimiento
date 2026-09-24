import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/saved_view.dart';

/// Las vistas guardadas de la Biblioteca (F16): filtro, orden y modo, con
/// nombre.
abstract interface class SavedViewRepository {
  /// Todas, en su orden, emitiendo de nuevo cada vez que algo cambia.
  Stream<List<SavedView>> watchAll();

  /// Guarda [query] y [viewMode] con [name]: una vista nueva, al final del
  /// orden.
  Future<SavedView> create({
    required String name,
    required LibraryQuery query,
    required LibraryViewMode viewMode,
  });

  Future<void> rename(String id, String name);

  /// Si aparece entre los accesos rápidos.
  Future<void> setPinned(String id, {required bool pinned});

  /// El nuevo orden entre las vistas guardadas: los ids de [ids], en el
  /// orden en que deben quedar. Falta alguno existente lo deja donde estaba,
  /// al final.
  Future<void> reorder(List<String> ids);

  Future<void> delete(String id);
}
