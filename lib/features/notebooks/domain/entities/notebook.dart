import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Un subconjunto con nombre de la bóveda (F16, D1): «Tesis», «Fuentes de la
/// clase 3». A diferencia de `Space`, un elemento puede estar en varios
/// cuadernos a la vez.
///
/// En modo [NotebookMode.manual] la pertenencia vive aparte, en
/// `notebook_item` —acá no hay lista de elementos—; en modo
/// [NotebookMode.query], [query] es la consulta guardada que decide, en el
/// momento, qué elementos tiene.
@immutable
class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    this.query,
    this.emptiedForProcessedAt,
  });

  final String id;
  final String name;
  final NotebookMode mode;

  /// Solo en modo [NotebookMode.query]; `null` en modo manual.
  final LibraryQuery? query;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cuándo se vació al llegar F41 (v46): de acá en más un cuaderno se arma
  /// solo con documentos procesados, y el que tenía algo de la Biblioteca
  /// quedó vacío. Mientras no sea `null`, el cuaderno muestra el aviso que lo
  /// explica; descartarlo lo deja en `null` para siempre.
  final DateTime? emptiedForProcessedAt;

  /// Si tiene que mostrar el aviso de por qué quedó vacío.
  bool get showsEmptiedNotice => emptiedForProcessedAt != null;

  Notebook copyWith({String? name, DateTime? updatedAt}) => Notebook(
    id: id,
    name: name ?? this.name,
    mode: mode,
    query: query,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    emptiedForProcessedAt: emptiedForProcessedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Notebook &&
      other.id == id &&
      other.name == name &&
      other.mode == mode &&
      other.query == query &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.emptiedForProcessedAt == emptiedForProcessedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    mode,
    query,
    createdAt,
    updatedAt,
    emptiedForProcessedAt,
  );
}
