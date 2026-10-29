import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';

/// «Lo creado» de Estudiar (F43): las creaciones, su estado y su papelera.
///
/// Las listas son streams que se actualizan solos: la fila de una creación que
/// se genera aparece enseguida, cambia su avance y queda lista sin que nadie
/// avise. Quien escribe el estado es la cola (`CreationQueue`); la interfaz
/// solo crea, renombra, borra y restaura.
abstract interface class StudyCreationRepository {
  // --- Leer ---------------------------------------------------------------

  /// Las creaciones vivas de [scope], con la más nueva arriba —por cuándo se
  /// crearon—, y cada cambio:
  ///
  /// - [AllProcessed]: todas;
  /// - un documento: las creadas sobre él **y** las de cualquier recorte que lo
  ///   usaron como fuente;
  /// - un cuaderno, un tema o un espacio: las creadas sobre ese recorte.
  ///
  /// Nunca las de la papelera. Un tipo que esta versión no conoce no aparece.
  Stream<List<StudyCreation>> watchByScope(CreationScope scope);

  /// La creación [id] —viva o en la papelera—, o `null` si no existe, y cada
  /// cambio: lo que mira su visor.
  Stream<StudyCreation?> watch(String id);

  /// Lo mismo, de una vez.
  Future<Either<Failure, StudyCreation?>> find(String id);

  /// Lo que la cola tiene que hacer: lo vivo en la cola o generándose, primero
  /// lo de «Generar ahora» y, dentro de cada uno, lo más viejo primero.
  Future<Either<Failure, List<StudyCreation>>> pending();

  /// Las de la papelera, la más recién borrada arriba, y cada cambio.
  Stream<List<StudyCreation>> watchTrash();

  // --- Crear y generar (la cola) -------------------------------------------

  /// Guarda una creación nueva para [request]: lista enseguida si es de
  /// extraer (decisión E: una vista viva, sin contenido) y, si no, en la cola.
  Future<Either<Failure, StudyCreation>> create(CreationRequest request);

  /// La pasa a «generándose», con su primer paso, y suma un intento: si la
  /// app se cierra a mitad, al abrirla se sabe cuántas veces se empezó.
  Future<Either<Failure, Unit>> markGenerating(
    String id, {
    required String? modelName,
  });

  /// Anota cuánto va —[progress] de 0 a 1, o `null` si no se sabe— y en qué
  /// paso. No toca su fecha: avanzar no es editarla.
  Future<Either<Failure, Unit>> reportProgress(
    String id, {
    required double? progress,
    required CreationStep step,
  });

  /// La deja lista con lo que escribió la IA: el [title], el [content] en el
  /// JSON de su tipo, su [contentVersion] y las fuentes que de verdad se
  /// leyeron ([sourceIds]; `null` deja las que tenía). Sin avance ni motivo
  /// de falla, y con los intentos en cero.
  ///
  /// Ya guardado, se borran sus ilustraciones que el contenido nuevo no
  /// nombra: las de la vez anterior, al volver a generarla. Lo que un
  /// ilustrador todavía está guardando para ella no se toca.
  Future<Either<Failure, Unit>> complete(
    String id, {
    required String title,
    required String content,
    int contentVersion = 1,
    List<String>? sourceIds,
  });

  /// La deja fallida por [failure], con su [detail] técnico.
  Future<Either<Failure, Unit>> fail(
    String id,
    CreationFailure failure, {
    String? detail,
  });

  /// La vuelve a la cola: «Reintentar» una fallida, o «Volver a generar» una
  /// lista —con otras [options], [sourceIds] o [languageCode] si se dan—. Con
  /// [runNow], cambia con qué turno se genera. Conserva su lugar en la lista y
  /// su título hasta que llegue el nuevo. Una de extraer no se vuelve a
  /// generar: queda lista con lo nuevo que se le dé.
  Future<Either<Failure, StudyCreation>> requeue(
    String id, {
    bool? runNow,
    Map<String, Object?>? options,
    List<String>? sourceIds,
    String? languageCode,
  });

  /// Lo que quedó «generándose» de una sesión anterior —la app se cerró a
  /// mitad— vuelve a la cola; lo que ya se empezó [maxAttempts] veces queda
  /// fallido por interrumpido. [inFlight] es lo que esta sesión sí está
  /// generando, que no se toca. Devuelve cuántas volvieron a la cola.
  Future<Either<Failure, int>> recoverInterrupted({
    required int maxAttempts,
    Set<String> inFlight = const {},
  });

  // --- La persona -----------------------------------------------------------

  /// Le cambia el título. Uno en blanco no vale.
  Future<Either<Failure, Unit>> rename(String id, String title);

  /// Retoca una creación lista sin volver a generarla (decisión G): sus
  /// [options] —el diseño elegido en el visor, que va aparte del contenido—
  /// o su [content] —una ilustración rehecha—. Lo que es `null` queda como
  /// estaba. Solo si está lista y viva: una que se genera o falló no se
  /// retoca (la cola la va a pisar), ni una de la papelera; se dice con un
  /// `Failure.validation`.
  ///
  /// Con un [content] nuevo, como [complete]: lo que ya no nombra se borra
  /// —la ilustración que se rehízo—.
  Future<Either<Failure, Unit>> amend(
    String id, {
    Map<String, Object?>? options,
    String? content,
  });

  /// La manda a la papelera: deja de verse en «Lo creado» y se restaura desde
  /// la Papelera. Si estaba en la cola, ya no se genera.
  Future<Either<Failure, Unit>> trash(String id);

  /// La saca de la papelera. Si había quedado a medias, vuelve fallida por
  /// interrumpida, con «Reintentar».
  Future<Either<Failure, Unit>> restore(String id);

  /// Borra de verdad las de [ids] que están en la papelera, con sus archivos
  /// (`originales/<creación>/`: las ilustraciones, lo que haya guardado su
  /// tipo). Lo único irreversible.
  Future<Either<Failure, Unit>> purge(List<String> ids);

  /// Vacía la papelera de creaciones: [purge] de todas las que hay en ella.
  Future<Either<Failure, Unit>> emptyTrash();
}
