import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/domain/entities/item_relation.dart';

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
}
