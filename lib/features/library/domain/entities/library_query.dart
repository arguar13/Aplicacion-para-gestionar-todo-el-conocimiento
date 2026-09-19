import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'library_query.freezed.dart';

/// Por dónde ordenar la biblioteca.
enum LibrarySort {
  /// Cuándo lo guardó el usuario. El orden por defecto: lo último que entró,
  /// arriba.
  capturedAt,

  /// Cuándo se publicó el original. Distinto del anterior y responde otra
  /// pregunta: un artículo de 2019 guardado hoy aparece arriba por captura y
  /// abajo por publicación.
  publishedAt,

  /// Última modificación — útil para volver a lo que se estuvo trabajando.
  updatedAt,

  /// Alfabético por título.
  title,

  /// Por qué tan bien coincide con el texto buscado.
  ///
  /// Solo significa algo cuando hay búsqueda: sin texto que comparar no hay
  /// relevancia que medir, y en ese caso el repositorio cae en
  /// [LibrarySort.capturedAt]. Es el orden que corresponde elegir apenas el
  /// usuario escribe algo — quien busca "paradigma" quiere lo que más habla
  /// de paradigma, no lo que guardó más recientemente.
  relevance,
}

/// Qué pedirle a la biblioteca.
///
/// Es un objeto y no una lista de parámetros sueltos porque los filtros se
/// combinan: "videos de YouTube etiquetados como filosofía que mencionen
/// paradigma, ordenados por fecha de publicación" es una sola consulta, no
/// cuatro llamadas encadenadas. Con parámetros sueltos, cada combinación
/// nueva obligaría a cambiar la firma del repositorio.
///
/// Los filtros son conjuntos y se combinan así: dentro de cada uno vale
/// *cualquiera* de los valores (un elemento de YouTube **o** de la web), y
/// entre filtros distintos tienen que cumplirse *todos*. Es lo que espera
/// cualquiera que haya usado filtros alguna vez.
@freezed
sealed class LibraryQuery with _$LibraryQuery {
  const factory LibraryQuery({
    /// Texto libre. Busca en título, subtítulo y contenido a la vez.
    String? searchText,

    @Default(<SourceKind>{}) Set<SourceKind> sourceKinds,
    @Default(<String>{}) Set<String> tagIds,

    /// Igual que [tagIds]: cualquiera de estos valores de propiedad basta,
    /// sin importar de qué categoría sea cada uno. Filtrar por categoría
    /// completa no hace falta —elegir sus valores ya lo implica.
    @Default(<String>{}) Set<String> propertyValueIds,

    /// A qué espacio limitar la vista. `null` es "todos" — a diferencia de
    /// las etiquetas, que se combinan, acá tiene sentido mirar un espacio a
    /// la vez, como una carpeta.
    String? spaceId,

    /// Para poder mirar solo lo que falló, o solo lo que está en la cola.
    @Default(<ProcessingState>{}) Set<ProcessingState> processingStates,

    @Default(LibrarySort.capturedAt) LibrarySort sortBy,

    /// Descendente por defecto: en fechas, lo más reciente primero es lo que
    /// se espera. Para el orden por título, quien lo pida querrá ascendente y
    /// tendrá que decirlo.
    @Default(true) bool descending,

    /// Para paginar. Sin límite, una biblioteca de veinte mil elementos se
    /// carga entera en memoria para mostrar los diez primeros.
    int? limit,
    @Default(0) int offset,
  }) = _LibraryQuery;

  const LibraryQuery._();

  /// Si hay texto de búsqueda utilizable.
  ///
  /// Una cadena de espacios no es una búsqueda: tratarla como tal devolvería
  /// cero resultados y daría a entender que la biblioteca está vacía.
  bool get hasSearchText => searchText?.trim().isNotEmpty ?? false;

  /// Si la consulta restringe algo. Con `false` alcanza toda la biblioteca,
  /// sea cual sea el orden o la página.
  bool get isFiltered =>
      hasSearchText ||
      sourceKinds.isNotEmpty ||
      tagIds.isNotEmpty ||
      propertyValueIds.isNotEmpty ||
      spaceId != null ||
      processingStates.isNotEmpty;
}
