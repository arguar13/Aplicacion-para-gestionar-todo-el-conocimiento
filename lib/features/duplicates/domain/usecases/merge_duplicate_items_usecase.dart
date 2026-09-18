import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Fusiona dos elementos que resultaron ser el mismo — F7, deduplicación.
///
/// `keepItemId` sobrevive y se queda con las dos renditions de texto
/// —ninguna se borra, se marca como principal la más completa (D5)—,
/// con las relaciones/etiquetas/propiedades/tarjetas de `discardItemId`
/// reasignadas, y con un registro nuevo de la procedencia de
/// `discardItemId` antes de que desaparezca. `discardItemId` se borra
/// de verdad, con el mismo `LibraryRepository.delete()` que borra
/// cualquier otro elemento —cascadas viejas, espejo nuevo, y su archivo
/// original si tenía uno propio (D6: solo el TEXTO nunca se descarta,
/// no necesariamente el archivo).
// ignore: one_member_abstracts
abstract interface class MergeDuplicateItemsUseCase {
  Future<Either<Failure, Unit>> call({
    required String keepItemId,
    required String discardItemId,
  });
}
