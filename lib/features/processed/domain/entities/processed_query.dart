import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'processed_query.freezed.dart';

/// Por dónde ordenar «Procesado».
enum ProcessedSort {
  /// Cuándo se tocó por última vez: lo que se estuvo trabajando, arriba. El
  /// orden por defecto.
  updatedAt,

  /// Cuándo se procesó por primera vez.
  createdAt,

  /// Alfabético por título.
  title,
}

/// Qué pedirle a «Procesado» (F41), como `LibraryQuery` a la Biblioteca: dentro
/// de cada filtro vale cualquiera de sus valores, y entre filtros tienen que
/// cumplirse todos. Lo que está en la papelera no entra nunca.
@freezed
sealed class ProcessedQuery with _$ProcessedQuery {
  const factory ProcessedQuery({
    /// Texto libre: en el título y en el texto de cualquiera de sus partes. Con
    /// varias palabras, el documento tiene que tenerlas todas, aunque estén en
    /// partes distintas.
    String? searchText,

    /// Uno de sus temas (F37). `null` es «todos».
    String? spaceId,

    /// Sus etiquetas, cada una con todas sus ramas, como en la Biblioteca:
    /// basta con una.
    @Default(<String>{}) Set<String> tagIds,

    /// Sus valores de propiedad, con sus ramas: basta con uno. Junto con
    /// [tagIds], tienen que cumplirse los dos, como en `LibraryQuery`.
    @Default(<String>{}) Set<String> propertyValueIds,

    /// De qué tipo era la fuente: un libro, un video, una página.
    @Default(<SourceKind>{}) Set<SourceKind> sourceKinds,

    /// Qué partes tiene: basta con una de estas —o con la copia del original,
    /// si [withOriginal]—.
    @Default(<ProcessedSection>{}) Set<ProcessedSection> sections,

    /// Que tenga la copia del original (decisión H). Con [sections], vale
    /// cualquiera de las dos cosas, como dentro de un filtro.
    @Default(false) bool withOriginal,

    /// Limitar a estos documentos. `null` es «sin límite»; vacío no deja pasar
    /// nada.
    Set<String>? ids,

    @Default(ProcessedSort.updatedAt) ProcessedSort sortBy,

    /// Descendente por defecto: lo más reciente primero. Para el título, quien
    /// lo pida querrá ascendente y tendrá que decirlo.
    @Default(true) bool descending,
    int? limit,
    @Default(0) int offset,
  }) = _ProcessedQuery;

  const ProcessedQuery._();

  /// Si hay texto de búsqueda utilizable.
  bool get hasSearchText => searchText?.trim().isNotEmpty ?? false;
}
