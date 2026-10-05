import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';

/// La papelera del contenido (F30, decisión 68): soltar el archivo original o
/// el texto de un elemento, recuperarlo durante 30 días y, pasado ese tiempo,
/// borrarlo de verdad.
///
/// Es el único camino para soltar una de las dos mitades de un elemento: el
/// triaje de un libro en la Bandeja («Solo el texto», «Solo el libro») y la
/// hoja «Más» del panel de la fuente («Borrar archivo, quedarme con el
/// texto») pasan por acá, con la misma papelera y el mismo plazo. Nada se
/// borra del disco ni de la base antes de [kContentTrashRetention].
abstract interface class ContentTrashRepository {
  /// «Solo el texto»: el archivo original de [itemId] va a la papelera y
  /// queda el texto. Falla —sin tocar nada— si el elemento no tiene archivo o
  /// no tiene texto: soltar el archivo lo dejaría vacío.
  Future<Either<Failure, List<TrashedContent>>> keepOnlyText(String itemId);

  /// «Solo el libro»: el texto de [itemId] va a la papelera —con sus
  /// subrayados— y queda el archivo, marcado para que la cola no le vuelva a
  /// extraer el texto sola (`Source.onlyFile`). Falla —sin tocar nada— si no
  /// tiene archivo o no tiene texto.
  Future<Either<Failure, List<TrashedContent>>> keepOnlyFile(String itemId);

  /// Devuelve a su elemento lo que espera en la papelera con [trashedId]: el
  /// archivo, o el texto con sus subrayados. Ver [ContentRestoreOutcome].
  Future<Either<Failure, ContentRestoreOutcome>> restore(String trashedId);

  /// Lo que [itemId] tiene en la papelera, de lo más nuevo a lo más viejo.
  Stream<List<TrashedContent>> watchOf(String itemId);

  /// El barrido: borra de verdad lo que lleva más de [kContentTrashRetention]
  /// en la papelera —la fila y, si nada más lo usa, el archivo del disco— y
  /// devuelve cuántas cosas borró.
  Future<Either<Failure, int>> purgeExpired();
}
