import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// De dónde sale el mapa de conocimiento (F14).
///
/// Solo lee. El mapa es un derivado de las asignaciones de valores y de las
/// relaciones entre elementos: ninguna escritura es de este repositorio, y lo
/// que calcula no se guarda.
abstract interface class KnowledgeMapRepository {
  /// Lo que hace falta para armar el grafo de temas de la categoría
  /// [definitionId] sobre los elementos que pasan [filter].
  ///
  /// Los elementos que cuentan son los VIVOS —lo que está en la papelera queda
  /// afuera, y con ello sus relaciones— y, si [filter] restringe algo, los que
  /// además cumple la consulta de la biblioteca: el mapa no tiene un motor de
  /// filtros propio. Una categoría que no existe da una entrada vacía.
  ///
  /// Falla con una excepción si la biblioteca no pudo resolver el filtro: quien
  /// llama —el motor del mapa— decide qué mostrar en su lugar.
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  });

  /// Lo que el tablero cuenta además del grafo de temas —las contradicciones
  /// abiertas, cuánto creció la bóveda, la madurez de las notas— sobre los
  /// mismos elementos que [readTopicInput]: los vivos que pasan [filter].
  Future<MapDashboard> readDashboard({
    LibraryQuery filter = const LibraryQuery(),
  });

  /// Avisa cada vez que se escribe algo que puede cambiar lo que devuelve
  /// [readTopicInput] con ese [filter]: las asignaciones, el vocabulario, las
  /// relaciones y los elementos —y, si el filtro restringe algo, lo que el
  /// filtro mira—. Nada más: una tarjeta repasada o un mensaje del chat no
  /// mueven el mapa.
  ///
  /// El aviso no dice QUÉ cambió —la base avisa por tabla, no por fila—: quien
  /// lo recibe vuelve a leer.
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()});
}
