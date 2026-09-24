import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Una combinación de filtro, orden y modo de la Biblioteca, guardada con
/// nombre (F16): «Sin leer, más nuevo primero», «Videos de este mes».
@immutable
class SavedView {
  const SavedView({
    required this.id,
    required this.name,
    required this.query,
    required this.viewMode,
    required this.position,
    required this.createdAt,
    this.pinned = false,
  });

  final String id;
  final String name;
  final LibraryQuery query;
  final LibraryViewMode viewMode;

  /// El orden entre las vistas guardadas, no un dato del filtro.
  final int position;

  /// Si aparece entre los accesos rápidos, además de en la lista entera.
  final bool pinned;

  final DateTime createdAt;

  SavedView copyWith({
    String? name,
    LibraryQuery? query,
    LibraryViewMode? viewMode,
    int? position,
    bool? pinned,
  }) => SavedView(
    id: id,
    name: name ?? this.name,
    query: query ?? this.query,
    viewMode: viewMode ?? this.viewMode,
    position: position ?? this.position,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedView &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.viewMode == viewMode &&
      other.position == position &&
      other.pinned == pinned &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, name, query, viewMode, position, pinned, createdAt);
}
