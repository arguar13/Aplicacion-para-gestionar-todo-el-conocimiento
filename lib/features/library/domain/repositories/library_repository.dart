import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// El acceso a todo lo guardado.
///
/// Trabaja con agregados completos —cada [KnowledgeItem] llega con su fuente
/// y sus formas ya cargadas— y no con filas sueltas. Es una decisión
/// deliberada: un elemento sin su procedencia no sirve para nada en esta app,
/// así que dejar que se pueda pedir "solo la fila" sería ofrecer una forma de
/// equivocarse.
abstract interface class LibraryRepository {
  /// Guarda un elemento con todo lo suyo, de una sola vez.
  ///
  /// Es atómico: o queda el elemento entero —fuente, formas y etiquetas— o no
  /// queda nada. Un guardado a medias dejaría contenido sin origen, que es
  /// justamente lo que esta app promete que no pasa.
  ///
  /// Sirve tanto para crear como para actualizar.
  Future<Either<Failure, KnowledgeItem>> save(KnowledgeItem item);

  /// Un elemento por su identificador, o `null` si no existe.
  ///
  /// Que no exista no es un fallo: es una respuesta. Por eso va como
  /// `Right(null)` y no como `Left`.
  Future<Either<Failure, KnowledgeItem?>> findById(String id);

  /// Los elementos que cumplen [query].
  Future<Either<Failure, List<KnowledgeItem>>> list(LibraryQuery query);

  /// Lo mismo que [list], pero emitiendo de nuevo cada vez que algo cambia.
  ///
  /// Es lo que permite que una pantalla abierta se actualice sola cuando una
  /// transcripción termina en segundo plano, sin tener que preguntar cada
  /// tanto ni acordarse de refrescar.
  Stream<List<KnowledgeItem>> watch(LibraryQuery query);

  /// Un elemento concreto, emitiendo de nuevo cada vez que cambia.
  ///
  /// Es lo que hace que la pantalla de detalle se complete sola: se abre un
  /// video recién guardado —con su enlace y nada más— y cuando la
  /// transcripción termina en segundo plano, el texto aparece sin que el
  /// usuario tenga que salir y volver a entrar.
  ///
  /// Emite `null` si el elemento deja de existir, para que la pantalla pueda
  /// cerrarse en vez de quedar mostrando algo que ya se borró.
  Stream<KnowledgeItem?> watchById(String id);

  /// Cuántos elementos cumplen [query], sin traerlos.
  ///
  /// Para los contadores de la interfaz: pedir la lista entera solo para
  /// contarla sería traer megabytes de transcripciones para mostrar un
  /// número.
  Future<Either<Failure, int>> count(LibraryQuery query);

  /// Borra un elemento y todo lo que cuelga de él.
  Future<Either<Failure, Unit>> delete(String id);

  /// Lo mismo que [delete], para varios elementos de una sola vez —el modo
  /// de selección múltiple de la biblioteca—. Las filas se van todas juntas
  /// o ninguna: una única transacción, no [ids] llamadas sueltas a [delete].
  Future<Either<Failure, Unit>> deleteMany(List<String> ids);

  /// Mueve un elemento a [spaceId], o lo deja sin clasificar si es `null`.
  ///
  /// Aparte de [save] a propósito: mover de carpeta no debería tocar ni
  /// releer las formas ni las etiquetas del elemento, que es lo que hace
  /// `save` al sincronizarlas — acá alcanza con una sola columna.
  Future<Either<Failure, Unit>> assignSpace({
    required String itemId,
    required String? spaceId,
  });

  /// Lo mismo que [assignSpace], para varios elementos de una sola vez.
  Future<Either<Failure, Unit>> assignSpaceMany({
    required List<String> itemIds,
    required String? spaceId,
  });
}
