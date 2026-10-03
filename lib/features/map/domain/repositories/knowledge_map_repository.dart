import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';

/// De dónde sale el mapa de conocimiento (F14).
///
/// Solo lee. El mapa es un derivado de las asignaciones de valores y de las
/// relaciones entre elementos: ninguna escritura es de este repositorio, y lo
/// que calcula no se guarda.
abstract interface class KnowledgeMapRepository {
  /// Lo que hace falta para armar el grafo de temas de la categoría
  /// [definitionId] sobre los elementos que pasan [filter].
  ///
  /// Con `kSpacesDimensionId`, los temas son los espacios —lo que se elige al
  /// guardar— (F28): planos, y uno por elemento.
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

  /// Lo que se le puede desplegar a un nodo del esquema (F14, D6), sin lo que
  /// ya sabe el grafo de temas: las notas mapa de un tema, o los elementos
  /// vinculados a un elemento, con el tipo de vínculo. Lo que está en la
  /// papelera queda afuera. Trae a lo sumo [limit].
  ///
  /// [dimensionId] es lo que mira el mapa: con `kSpacesDimensionId`, un tema
  /// es un espacio y sus notas mapa son las que están en él (F28).
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    String? dimensionId,
    int limit = kSchemaFanOut,
  });

  /// Las notas mapa vivas de la bóveda, por título: los puntos de entrada del
  /// esquema (F14, D6). A lo sumo [limit], las tocadas más recientemente.
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes});

  /// Los elementos de un tema y de sus subtemas con los vínculos entre ellos:
  /// lo que se dibuja al acercarse a un tema (F14, D5). A lo sumo [limit], los
  /// tocados más recientemente; lo que está en la papelera queda afuera.
  ///
  /// Con [dimensionId] `kSpacesDimensionId`, [valueId] es un espacio: sus
  /// elementos, sin subtemas (F28).
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    String? dimensionId,
    int limit = kMaxGraphItems,
  });

  /// Los elementos vivos que pasan [filter] y tienen algún vínculo con otro
  /// que también lo pasa, con esos vínculos: lo que dibuja la vista
  /// «Vínculos» (F28). No mira temas ni etiquetas: un elemento sin ninguno
  /// se dibuja igual.
  ///
  /// A lo sumo [limit] elementos, elegidos como dice `selectLinkGraph`:
  /// primero [focusId] y su vecindario, después lo vinculado más
  /// recientemente y al final lo más vinculado.
  Future<LinkGraph> readLinkGraph({
    LibraryQuery filter = const LibraryQuery(),
    String? focusId,
    int limit = kMaxGraphItems,
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

/// Cuántos hijos se piden, como mucho, al desplegar un nodo del esquema.
const kSchemaFanOut = 24;

/// Cuántas notas mapa se ofrecen, como mucho, como punto de partida.
const kMaxMapNotes = 100;
