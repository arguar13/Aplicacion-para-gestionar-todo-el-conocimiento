import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Fusiona dos elementos que resultaron ser el mismo — F7, deduplicación.
///
/// `keepItemId` sobrevive y se queda con las dos renditions de texto
/// —ninguna se borra, se marca como principal la más completa (D5)—,
/// con las relaciones/etiquetas/propiedades/tarjetas de `discardItemId`
/// reasignadas, con un registro nuevo de la procedencia de
/// `discardItemId`, y con lo que el usuario escribió a mano en él —su
/// subtítulo, si el que queda no tiene, y sus notas, juntadas con las
/// suyas— (F11). `discardItemId` va a la papelera con el mismo
/// `LibraryRepository.delete()` que manda cualquier otro elemento: no se
/// borra nada, y se puede restaurar (D6: el TEXTO nunca se descarta).
// ignore: one_member_abstracts
abstract interface class MergeDuplicateItemsUseCase {
  Future<Either<Failure, Unit>> call({
    required String keepItemId,
    required String discardItemId,
  });
}
