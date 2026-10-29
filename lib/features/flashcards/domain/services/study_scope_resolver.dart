import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';

/// Los elementos de un recorte de Procesado (F43): quien lo sabe resolver —el
/// recorte de «Lo creado», `CreationScopeResolver`— lo da sin que Repasar
/// tenga que conocerlo.
// ignore: one_member_abstracts
abstract interface class ProcessedStudyItems {
  /// Los elementos que estudia el recorte de clave [scopeKey]
  /// (`CreationScope.storageKey`): sus documentos procesados vivos y las
  /// fuentes de las que salieron. `null` si el recorte no restringe nada; un
  /// recorte que ya no existe falla, como un cuaderno borrado.
  Future<Either<Failure, Set<String>?>> studyItemIds(String scopeKey);
}

/// De un [StudyScope] a los elementos que lo componen (F31, decisión 69).
///
/// Usa los MISMOS filtros que la Biblioteca (`LibraryRepository.matchingIds`) y
/// lo que un cuaderno tiene hoy (`NotebookRepository.memberIds`: sus documentos
/// procesados, F41): "qué entra en «Roma»" tiene una sola respuesta, y no un
/// segundo motor que pueda discrepar. Un valor del vocabulario trae también sus
/// ramas. Un recorte de Procesado (F43) lo resuelve `processed`, el mismo que
/// arma el material de «Lo creado».
class StudyScopeResolver {
  const StudyScopeResolver({
    required LibraryRepository library,
    required NotebookRepository notebooks,
    ProcessedStudyItems? processed,
  }) : _library = library,
       _notebooks = notebooks,
       _processed = processed;

  final LibraryRepository _library;
  final NotebookRepository _notebooks;
  final ProcessedStudyItems? _processed;

  /// Los elementos de [scope], o `null` si no restringe nada
  /// ([StudyScopeKind.all]). Un recorte vacío da un conjunto vacío, no `null`.
  Future<Either<Failure, Set<String>?>> itemIds(StudyScope scope) async {
    switch (scope.kind) {
      case StudyScopeKind.all:
        return right(null);
      case StudyScopeKind.item:
        return right({scope.id!});
      case StudyScopeKind.space:
        return _matching(LibraryQuery(spaceId: scope.id));
      case StudyScopeKind.value:
        return _matching(LibraryQuery(propertyValueIds: {scope.id!}));
      case StudyScopeKind.notebook:
        // Falla si el cuaderno ya no existe: un recorte que apunta a algo
        // borrado no tiene nada que estudiar, y se dice.
        final ids = await _notebooks.memberIds(scope.id!);
        return ids.map((ids) => ids.toSet());
      case StudyScopeKind.processed:
        final processed = _processed;
        if (processed == null) {
          return left(
            const Failure.unexpected(
              message: 'No hay quién resuelva un recorte de Procesado.',
            ),
          );
        }
        return processed.studyItemIds(scope.id!);
    }
  }

  Future<Either<Failure, Set<String>?>> _matching(LibraryQuery query) async {
    final result = await _library.matchingIds(query);
    return result.map((ids) => ids.toSet());
  }
}
