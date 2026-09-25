import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/search_hit.dart';
import 'package:sinapsis/features/library/domain/entities/trashed_item.dart';

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

  /// Los identificadores de los elementos que cumplen [query], en el orden
  /// que ella pide, sin traer los agregados.
  ///
  /// Para quien tiene que aplicar a lo suyo los mismos filtros que la
  /// biblioteca —la línea de tiempo filtra sus eventos con el texto, las
  /// propiedades y el resto—: así "qué elementos entran" tiene una sola
  /// respuesta y no un segundo motor de búsqueda que pueda discrepar.
  Future<Either<Failure, List<String>>> matchingIds(LibraryQuery query);

  /// Cuántos elementos cumplen [query], sin traerlos.
  ///
  /// Para los contadores de la interfaz: pedir la lista entera solo para
  /// contarla sería traer megabytes de transcripciones para mostrar un
  /// número.
  Future<Either<Failure, int>> count(LibraryQuery query);

  /// Los resultados de [query] con DÓNDE está lo que se encontró en cada uno:
  /// el chunk que mejor coincide, con su fragmento y su posición —el minuto, la
  /// página, los caracteres—.
  ///
  /// Aparte de [list] a propósito: la cita sale de la misma pasada por el
  /// índice que elige y ordena los resultados, en vez de una segunda consulta
  /// que recorra de nuevo todas las coincidencias. Sin texto buscado, es
  /// [list] con una cita vacía en cada uno. Un elemento que coincide solo por
  /// su título o su subtítulo, o cuya coincidencia no está en un chunk —una
  /// nota—, no trae cita: no hay dónde señalar.
  Future<Either<Failure, List<SearchHit>>> search(LibraryQuery query);

  /// Lo mismo que [search], emitiendo de nuevo cada vez que algo cambia.
  Stream<List<SearchHit>> watchSearch(LibraryQuery query);

  /// Manda un elemento a la papelera. No se borra nada: el elemento deja de
  /// verse en la biblioteca, en la búsqueda, en el grafo y en las sugerencias,
  /// pero conserva todo lo que tenía —texto, vínculos, tarjetas, el archivo
  /// original— y se puede [restore]. Solo [purge] y [emptyTrash] borran de
  /// verdad.
  ///
  /// Borrar algo que no existe, o que ya está en la papelera, no es un error.
  Future<Either<Failure, Unit>> delete(String id);

  /// Lo mismo que [delete], para varios elementos de una sola vez —el modo
  /// de selección múltiple de la biblioteca—. Todos juntos o ninguno: una
  /// única transacción, no [ids] llamadas sueltas a [delete].
  Future<Either<Failure, Unit>> deleteMany(List<String> ids);

  /// Saca un elemento de la papelera: vuelve a la biblioteca tal cual estaba.
  Future<Either<Failure, Unit>> restore(String id);

  /// Lo mismo que [restore], para varios de una sola vez.
  Future<Either<Failure, Unit>> restoreMany(List<String> ids);

  /// Borra PARA SIEMPRE los elementos de [ids] que están en la papelera, junto
  /// con lo que cuelga de ellos, y los archivos originales que ningún otro
  /// elemento usa. Lo que no está en la papelera no se toca: no hay forma de
  /// borrar de verdad algo que sigue vivo.
  Future<Either<Failure, Unit>> purge(List<String> ids);

  /// Vacía la papelera: [purge] de cada elemento que hay en ella.
  Future<Either<Failure, Unit>> emptyTrash();

  /// Lo que hay en la papelera, del más reciente al más viejo, emitiendo de
  /// nuevo cada vez que algo entra o sale.
  Stream<List<TrashedItem>> watchTrash();

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

  /// Corre [body] entero dentro de UNA sola transacción.
  ///
  /// Para quien guarda muchos elementos con lógica propia entre cada uno
  /// —a diferencia de [deleteMany]/[restoreMany]/[assignSpaceMany], que ya
  /// saben qué hacer con cada uno—, como importar miles de referencias de un
  /// `.bib` (F15): sin esto, cada [save] de adentro abre y cierra su propia
  /// transacción, y miles de confirmaciones sueltas pesan mucho más que la
  /// escritura en sí. Todo o nada, igual que [save]: si algo de adentro
  /// falla, no queda nada a medias.
  Future<T> runInTransaction<T>(Future<T> Function() body);

  /// Lo mismo que [runInTransaction], y además en modo lote (F19, 19.4): el
  /// índice de texto queda suspendido —se repuebla entero al cerrar, no fila
  /// por fila— y cada campo versionado se escribe una sola vez por elemento,
  /// con su último valor, en vez de una vez por [save].
  ///
  /// Para una operación que guarda MUCHOS elementos de golpe —de nuevo,
  /// importar un `.bib` entero—, no para guardar uno: suspender y repoblar
  /// el índice entero cuesta más de lo que ahorra cuando [body] solo toca un
  /// elemento, así que [runInTransaction] sigue siendo lo que corresponde
  /// para eso.
  Future<T> runBulk<T>(Future<T> Function() body);
}
