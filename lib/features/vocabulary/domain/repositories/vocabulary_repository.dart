import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';

/// El mantenimiento del vocabulario controlado: fusionar valores repetidos,
/// renombrar, manejar alias, borrar lo que no se usa.
///
/// Cada operación que cambia algo devuelve un [VocabularyOperation] que se le
/// puede pasar a [undo]. Las de lote son transaccionales: o se aplican todas
/// o no se aplica ninguna.
abstract interface class VocabularyRepository {
  /// Cuántos valores y elementos toca fusionar [discardIds] en [keepId].
  /// No cambia nada.
  Future<Either<Failure, MergePreview>> previewMerge({
    required String keepId,
    required List<String> discardIds,
  });

  /// Fusiona todos los [discardIds] en [keepId], en una transacción. Los
  /// valores tienen que ser de la misma categoría. El label de cada
  /// descartado queda como alias del que se conserva.
  Future<Either<Failure, VocabularyOperation>> mergeValues({
    required String keepId,
    required List<String> discardIds,
  });

  /// Cambia el nombre de un valor. Sin distinguir mayúsculas ni acentos, no
  /// puede chocar con otro valor ni con un alias de la misma categoría;
  /// cambiarle solo el acento o las mayúsculas a su propio nombre sí se
  /// permite.
  Future<Either<Failure, VocabularyOperation>> renameValue({
    required String id,
    required String label,
  });

  /// Borra valores SIN ningún uso, en una transacción. Uno que algún elemento
  /// tiene puesto se rechaza —y no se borra ninguno—: quitar del vocabulario
  /// algo en uso es otra decisión, no un borrado de limpieza.
  Future<Either<Failure, VocabularyOperation>> deleteUnusedValues(
    List<String> ids,
  );

  /// Agrega [alias] al valor [valueId]: otro texto que se resuelve al mismo
  /// valor. No puede repetir el nombre de ningún valor ni de otro alias de la
  /// categoría.
  Future<Either<Failure, VocabularyOperation>> addAlias({
    required String valueId,
    required String alias,
  });

  Future<Either<Failure, VocabularyOperation>> removeAlias(String aliasId);

  /// Deshace [operation]. Se NIEGA con un fallo de validación si el
  /// vocabulario cambió desde entonces de una forma que obligaría a adivinar:
  /// no deshace a medias.
  Future<Either<Failure, Unit>> undo(VocabularyOperation operation);
}
