import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';

/// Los conflictos que dejó una fusión y todavía nadie revisó (F11).
abstract interface class MergeConflictRepository {
  /// Los conflictos sin resolver, del más nuevo al más viejo. Se actualiza
  /// solo: al resolver uno desaparece, y al fusionar aparecen los nuevos.
  Stream<List<MergeConflict>> watchPending();

  /// Resuelve [conflictId] dejando la versión [choice].
  ///
  /// Escribe como cualquier edición del usuario —con su versión de campo
  /// nueva—: una fusión posterior no vuelve a marcarlo. Elegir la versión que
  /// ya está en uso no cambia ningún dato: solo da el conflicto por revisado.
  ///
  /// Uno que ya se resolvió, o que no existe, no es un error: no hace nada.
  /// Sí lo es pedir [MergeConflictChoice.keepBoth] donde no tiene sentido.
  Future<Either<Failure, Unit>> resolve(
    String conflictId,
    MergeConflictChoice choice,
  );
}
