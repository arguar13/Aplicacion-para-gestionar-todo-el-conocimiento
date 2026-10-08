import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';

/// De un [StudyScope] a los elementos que lo componen (F31, decisión 69).
///
/// Usa los MISMOS filtros que la Biblioteca (`LibraryRepository.matchingIds`) y
/// lo que un cuaderno es hoy (`NotebookRepository.resolveQuery`): "qué entra en
/// «Roma»" tiene una sola respuesta, y no un segundo motor que pueda
/// discrepar. Un valor del vocabulario trae también sus ramas.
class StudyScopeResolver {
  const StudyScopeResolver({
    required LibraryRepository library,
    required NotebookRepository notebooks,
  }) : _library = library,
       _notebooks = notebooks;

  final LibraryRepository _library;
  final NotebookRepository _notebooks;

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
        final LibraryQuery query;
        try {
          query = await _notebooks.resolveQuery(scope.id!);
          // `resolveQuery` falla si el cuaderno ya no existe: un recorte que
          // apunta a algo borrado no tiene nada que estudiar, y se dice.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          return left(
            const Failure.unexpected(
              message: 'El cuaderno ya no existe; puede que se haya borrado.',
            ),
          );
        }
        return _matching(query);
    }
  }

  Future<Either<Failure, Set<String>?>> _matching(LibraryQuery query) async {
    final result = await _library.matchingIds(query);
    return result.map((ids) => ids.toSet());
  }
}
