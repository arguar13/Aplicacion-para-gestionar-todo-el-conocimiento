import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

part 'timeline_filter.freezed.dart';

/// De qué se recorta la línea de tiempo (F40): un tema, un documento o una
/// rama del Atlas. Sin recorte (`null` en [TimelineFilter.scope]) se ve todo.
enum TimelineScopeKind {
  /// Lo que está en un tema (un espacio).
  topic,

  /// Lo que tiene un valor de una propiedad o uno de sus subtemas: una rama
  /// del Atlas.
  branch,

  /// Los hechos de un solo documento.
  document,
}

/// Un recorte de la línea de tiempo, con el nombre con el que se rotula.
///
/// Lleva su [label] porque quien lo fija —el Atlas con su rama, el detalle con
/// su documento, una hoja con lo elegido— ya lo tiene a mano, y buscarlo de
/// nuevo desde el identificador pediría tres lecturas distintas (un tema, un
/// valor, un elemento) para rotular un chip.
@immutable
class TimelineScope {
  /// Lo que está en el tema [spaceId].
  const TimelineScope.topic({required String spaceId, required this.label})
    : kind = TimelineScopeKind.topic,
      id = spaceId;

  /// Lo que tiene el valor [valueId] de una propiedad, o uno de sus subtemas.
  const TimelineScope.branch({required String valueId, required this.label})
    : kind = TimelineScopeKind.branch,
      id = valueId;

  /// Solo los hechos del elemento [itemId].
  const TimelineScope.document({required String itemId, required this.label})
    : kind = TimelineScopeKind.document,
      id = itemId;

  final TimelineScopeKind kind;

  /// El identificador del tema, del valor o del elemento, según [kind].
  final String id;

  final String label;

  @override
  bool operator ==(Object other) =>
      other is TimelineScope &&
      other.kind == kind &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, id, label);

  @override
  String toString() => 'TimelineScope($kind, $id, $label)';
}

/// Lo que filtra la línea de tiempo (F40), entero: el recorte de arriba, la
/// búsqueda y el panel de tipos y etiquetas.
///
/// Es un solo valor, con un solo dueño (`timelineFilterProvider`), y de él sale
/// la consulta que entiende la biblioteca ([query]): "qué hechos entran" tiene
/// una sola respuesta. El recorte es uno solo a la vez —o todo, o un tema, o un
/// documento, o una rama—, así que no puede quedar en un estado a medias, como
/// un tema y un documento que se pisan.
@freezed
sealed class TimelineFilter with _$TimelineFilter {
  const factory TimelineFilter({
    /// El recorte puesto, o `null` para ver todo.
    TimelineScope? scope,

    /// Lo buscado en el título y el contenido; `null` sin búsqueda.
    String? searchText,

    @Default(<SourceKind>{}) Set<SourceKind> sourceKinds,
    @Default(<String>{}) Set<String> tagIds,
  }) = _TimelineFilter;

  const TimelineFilter._();

  /// La consulta de biblioteca equivalente. La que leen los hechos, y la que
  /// distingue un filtro de otro para el encuadre.
  LibraryQuery get query => LibraryQuery(
    searchText: searchText,
    sourceKinds: sourceKinds,
    tagIds: tagIds,
    spaceId: scope?.kind == TimelineScopeKind.topic ? scope!.id : null,
    propertyValueIds: scope?.kind == TimelineScopeKind.branch
        ? {scope!.id}
        : const {},
    ids: scope?.kind == TimelineScopeKind.document ? {scope!.id} : null,
  );

  /// Cuántos filtros del panel (tipos y etiquetas) hay puestos.
  int get panelCount => sourceKinds.length + tagIds.length;

  /// Si hay algo de la búsqueda que mostrar.
  bool get hasSearchText => searchText?.trim().isNotEmpty ?? false;

  /// Cuántos filtros hay puestos en total, cualquiera sea su lugar.
  int get activeCount =>
      panelCount + (scope == null ? 0 : 1) + (hasSearchText ? 1 : 0);
}
