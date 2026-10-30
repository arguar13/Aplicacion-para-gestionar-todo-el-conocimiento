import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';

/// De un [CreationScope] a lo que tiene (F43): un solo lugar responde «qué
/// documentos procesados hay en este recorte», para el selector, las tarjetas
/// de crear, «Lo creado» y «Para hoy» (como [ProcessedStudyItems]).
///
/// Usa las mismas preguntas que el resto de la app: lo procesado con su
/// consulta (`ProcessedRepository.matchingIds`), un cuaderno con lo que tiene
/// hoy (`NotebookRepository.memberIds`) y un tema con todas sus ramas —la
/// misma regla que `LibraryScope.processed` y el Atlas—. Nunca la Biblioteca.
abstract interface class CreationScopeResolver implements ProcessedStudyItems {
  /// Los documentos procesados vivos de [scope], lo tocado más recientemente
  /// primero. Un documento que ya no está da una lista vacía; un cuaderno que
  /// ya no existe falla.
  Future<Either<Failure, List<String>>> documentIds(CreationScope scope);

  /// Cómo está cada uno de [documentIds], en ese orden —también los que ya no
  /// existen, como «fuente borrada»—: lo de la fila de «Fuentes» y del
  /// selector, de una sola vez para muchos.
  Future<Either<Failure, List<CreationSource>>> sourcesOf(
    List<String> documentIds,
  );

  /// El nombre y las cifras de [scope] para la píldora del selector, y cada
  /// cambio.
  Stream<CreationScopeSummary> watchSummary(CreationScope scope);

  /// Lo que ofrece el selector (M11), entero, con la línea de cada uno, y cada
  /// cambio: «Todo lo procesado», cada documento procesado vivo, cada cuaderno
  /// y, de [topics], los temas y los espacios que existen.
  ///
  /// **En lote**: unas pocas lecturas para todo, las mismas con diez
  /// documentos que con diez mil —nunca una por fila—, y las cifras de cada
  /// uno iguales a las de [watchSummary].
  Stream<CreationScopeCatalog> watchCatalog(Set<CreationScope> topics);
}
