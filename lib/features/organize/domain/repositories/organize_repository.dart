import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Lo que convierte una pila de recortes guardados en algo organizado:
/// etiquetas, vínculos entre elementos y resaltados con nota.
///
/// Las tres cosas viven en su propio repositorio y no en el de la biblioteca
/// porque no son parte del agregado `KnowledgeItem` — un elemento no carga
/// sus relaciones ni sus resaltados al leerse, de la misma forma que abrir un
/// libro no trae automáticamente la lista de con qué otros libros lo
/// comparaste. Cargarlos junto con cada elemento sería trabajo de más en el
/// caso común (mirar la biblioteca) para un dato que solo hace falta al
/// entrar al detalle.
abstract interface class OrganizeRepository {
  // ---------------------------------------------------------------------
  // Etiquetas
  // ---------------------------------------------------------------------

  /// Todas las etiquetas que existen, ordenadas alfabéticamente.
  ///
  /// Sirve tanto para ofrecerlas como sugerencia al etiquetar un elemento
  /// como para armar los filtros de la biblioteca. Agregar o quitar una
  /// etiqueta de un elemento no pasa por acá: eso ya lo hace
  /// `LibraryRepository.save` con la lista de etiquetas del elemento.
  Stream<List<Tag>> watchAllTags();

  /// La etiqueta que se llama [name], sin distinguir mayúsculas. Si no
  /// existe, la crea.
  ///
  /// Es el paso previo a agregar una etiqueta a un elemento: quien escribe
  /// "filosofía" en un elemento que ya tiene la etiqueta "Filosofía" tiene
  /// que terminar en la misma etiqueta, no en dos que compiten por agrupar lo
  /// mismo. Devuelve un fallo si el nombre queda vacío.
  Future<Either<Failure, Tag>> getOrCreateTag(String name);

  /// Le cambia el nombre a una etiqueta, en todos los elementos que la usan.
  ///
  /// Devuelve un fallo si el nombre queda vacío, o si ya existe otra etiqueta
  /// con ese nombre (sin distinguir mayúsculas) — la unicidad es parte de lo
  /// que hace que las etiquetas sirvan para agrupar.
  Future<Either<Failure, Tag>> renameTag({
    required String id,
    required String name,
  });

  /// Borra una etiqueta. Los elementos que la tenían simplemente dejan de
  /// tenerla; nada más se ve afectado.
  Future<Either<Failure, Unit>> deleteTag(String id);

  // ---------------------------------------------------------------------
  // Relaciones
  // ---------------------------------------------------------------------

  /// Vincula dos elementos.
  ///
  /// Devuelve un fallo si se intenta vincular un elemento consigo mismo, o si
  /// ya existe ese mismo vínculo —mismo origen, mismo destino, mismo tipo—
  /// entre los dos. Las dos reglas también están en el esquema como
  /// salvaguarda, pero comprobarlas acá permite devolver un mensaje que
  /// explica qué pasó, en vez de la excepción cruda de una restricción de la
  /// base.
  Future<Either<Failure, Unit>> createRelation({
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
    String? note,
  });

  /// Deshace un vínculo.
  Future<Either<Failure, Unit>> deleteRelation(String id);

  /// Con qué otros elementos está vinculado [itemId], en cualquiera de los
  /// dos sentidos, actualizándose solo.
  Stream<List<ItemRelation>> watchRelationsForItem(String itemId);

  /// Todos los vínculos de la bóveda, sin filtrar por ningún elemento.
  ///
  /// Para el grafo: mostrar la red completa necesita cada arista, no las
  /// de un elemento a la vez.
  Stream<List<RelationEdge>> watchAllRelations();

  // ---------------------------------------------------------------------
  // Resaltados
  // ---------------------------------------------------------------------

  /// Subraya un fragmento de una forma de contenido, con una nota opcional.
  Future<Either<Failure, Highlight>> createHighlight({
    required String renditionId,
    required int startOffset,
    required int endOffset,
    required String excerpt,
    String? note,
  });

  /// Cambia la nota de un resaltado ya hecho. `null` la borra sin borrar el
  /// resaltado en sí.
  Future<Either<Failure, Highlight>> updateHighlightNote({
    required String id,
    required String? note,
  });

  /// Quita un resaltado.
  Future<Either<Failure, Unit>> deleteHighlight(String id);

  /// Los resaltados de una forma de contenido, en el orden en que aparecen
  /// en el texto, actualizándose solo.
  Stream<List<Highlight>> watchHighlightsForRendition(String renditionId);

  // ---------------------------------------------------------------------
  // Espacios
  // ---------------------------------------------------------------------

  /// Todos los espacios que existen, ordenados alfabéticamente.
  Stream<List<Space>> watchAllSpaces();

  /// Crea un espacio nuevo. Devuelve un fallo si el nombre queda vacío o si
  /// ya existe otro espacio con ese nombre (sin distinguir mayúsculas).
  ///
  /// A diferencia de `getOrCreateTag`, esto sí puede fallar por nombre
  /// repetido en vez de devolver el existente: un espacio se crea desde una
  /// pantalla propia donde el usuario elige el nombre a propósito, no al
  /// escribirlo de paso sobre un elemento — que dos veces haya escrito lo
  /// mismo amerita avisarle, no unificarlo en silencio.
  Future<Either<Failure, Space>> createSpace(String name);

  /// Le cambia el nombre a un espacio.
  Future<Either<Failure, Space>> renameSpace({
    required String id,
    required String name,
  });

  /// Borra un espacio. Los elementos que pertenecían a él quedan sin
  /// clasificar — la cascada de la columna es `SET NULL`, no `CASCADE`:
  /// borrar una carpeta no debería borrar lo que había adentro.
  Future<Either<Failure, Unit>> deleteSpace(String id);

  // ---------------------------------------------------------------------
  // Propiedades
  // ---------------------------------------------------------------------

  /// Todas las categorías de propiedad que existen —"Época", "Región",
  /// "Tema"—, ordenadas alfabéticamente.
  Stream<List<PropertyDefinition>> watchAllPropertyDefinitions();

  /// La categoría que se llama [name], sin distinguir mayúsculas. Si no
  /// existe, la crea con el [type] indicado —`text` si no se especifica—.
  /// Si ya existe, se devuelve tal cual: [type] no le pisa el tipo a una
  /// categoría existente. Devuelve un fallo si el nombre queda vacío.
  Future<Either<Failure, PropertyDefinition>> getOrCreatePropertyDefinition(
    String name, {
    PropertyValueType type = PropertyValueType.text,
  });

  /// Borra una categoría entera, con todos sus valores y las asignaciones
  /// que tenía puestas. A diferencia de un espacio, acá sí se borra en
  /// cascada: la categoría y sus valores son la propiedad en sí, no una
  /// carpeta que contiene elementos ajenos a ella.
  ///
  /// Una categoría de sistema (`isSystem`, como "Tema" o "Fecha del
  /// hecho") no se puede borrar: [Failure.validation], sin tocar nada.
  Future<Either<Failure, Unit>> deletePropertyDefinition(String id);

  /// Los valores que ya existen bajo [definitionId], ordenados
  /// alfabéticamente — para sugerir mientras se escribe uno nuevo, y para
  /// armar los filtros de la vista de propiedades.
  Stream<List<PropertyValue>> watchPropertyValues(String definitionId);

  /// Pone el valor [value] bajo la categoría [definitionId] en el
  /// elemento [itemId]. Crea el valor si todavía no existía bajo esa
  /// categoría —mismo criterio que [getOrCreateTag]: escribir "Roma"
  /// donde ya existe "Roma" tiene que terminar en el mismo valor, no en
  /// dos que compiten por lo mismo—. No falla si el elemento ya lo tenía
  /// puesto.
  Future<Either<Failure, Unit>> assignProperty({
    required String itemId,
    required String definitionId,
    required String value,
  });

  /// Saca un valor de propiedad de un elemento. El valor en sí sigue
  /// existiendo para los demás elementos que lo tengan puesto.
  Future<Either<Failure, Unit>> removeItemProperty({
    required String itemId,
    required String propertyValueId,
  });

  /// Cambia el label de un valor de propiedad. Se propaga sola a todo lo
  /// que lo referencia, porque todo lo hace por [id] —a diferencia de
  /// [mergePropertyValues], acá no hay dos valores de por medio, solo
  /// uno que cambia de nombre—.
  ///
  /// Devuelve un fallo si [label] queda vacío, si ya existe otro valor
  /// con ese label en la MISMA categoría (sin distinguir mayúsculas), o
  /// si ese label ya es un alias de otro valor de esa categoría — mismo
  /// criterio de unicidad "dentro de la categoría" que [PropertyAlias].
  Future<Either<Failure, PropertyValue>> renamePropertyValue({
    required String id,
    required String label,
  });

  /// Resuelve [text] a un valor existente bajo [definitionId], buscando
  /// primero por label y después por alias —ambos sin distinguir
  /// mayúsculas—. `right(null)` si no hay ningún match: "no encontrado"
  /// es una respuesta válida de un resolver, no un fallo.
  Future<Either<Failure, PropertyValue?>> resolvePropertyValue({
    required String definitionId,
    required String text,
  });

  /// Fusiona [discardId] dentro de [keepId]: todo lo que tenía asignado
  /// [discardId] pasa a tener [keepId], y su label queda como un alias
  /// nuevo de [keepId] —así, quien lo buscaba por el nombre viejo lo
  /// sigue encontrando—. "Reversible" es eso: no se pierde la capacidad
  /// de *resolver* el nombre viejo, no que se pueda reconstruir qué
  /// elemento tenía cuál de los dos antes de la fusión.
  ///
  /// Devuelve un fallo si son el mismo valor, si son de categorías
  /// distintas, o si alguno de los dos ya no existe.
  Future<Either<Failure, Unit>> mergePropertyValues({
    required String keepId,
    required String discardId,
  });
}
