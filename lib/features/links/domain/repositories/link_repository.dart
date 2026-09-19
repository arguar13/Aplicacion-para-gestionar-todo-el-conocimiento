import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';

/// Los `[[Título]]` que apuntan a algo que no existe, y cómo completarlos.
///
/// Enlazar primero y crear la nota después es el flujo natural de destilar:
/// este repositorio es lo que hace que ese enlace deje de ser un texto sin
/// destino. La sincronización de los enlaces de una nota con `inline_link`
/// no vive acá sino en `LibraryRepository.save`, dentro de la misma
/// transacción que la guarda.
abstract interface class LinkRepository {
  /// De [normalizedTitles] —títulos ya normalizados con `normalizeLinkTitle`—,
  /// los que no tienen ningún elemento con ese título.
  ///
  /// [excludingItemId] es la nota que se está escribiendo: un enlace cuyo
  /// único homónimo es ella misma no es un enlace roto, así que no vuelve en
  /// el resultado. `null` para una nota que todavía no se guardó.
  Future<Either<Failure, Set<String>>> findMissingTitles(
    Set<String> normalizedTitles, {
    String? excludingItemId,
  });

  /// Crea una nota vacía llamada [title], del subtipo [kind], y devuelve la
  /// nota resultante.
  ///
  /// Guardarla por `LibraryRepository.save` es lo que resuelve los enlaces
  /// rotos de la bóveda que esperaban ese título y crea su relación
  /// `relatedTo`: el enlace deja de estar roto en el momento.
  ///
  /// Si ya existe un elemento con ese título —otra ventana lo creó entre que
  /// se detectó el enlace roto y se pidió crear la nota— devuelve ese
  /// elemento en vez de crear un homónimo.
  Future<Either<Failure, KnowledgeItem>> createNoteForLink({
    required String title,
    NoteKind kind = NoteKind.living,
  });

  /// Los `[[Título]]` sin nota de toda la bóveda, agrupados por título y
  /// actualizándose solos: los que más notas escriben primero, y a igual
  /// cantidad, por orden alfabético.
  ///
  /// Sale de `inline_link` y no de releer el texto de cada nota.
  Stream<List<BrokenLink>> watchBrokenLinks();

  /// Crea una nota por cada título de [titles], todas del subtipo [kind], y
  /// devuelve cuántas creó de verdad.
  ///
  /// Es atómico: si una falla, ninguna queda creada. Un título que ya tiene
  /// nota —o que se repite en [titles]— no crea un homónimo y no cuenta.
  Future<Either<Failure, int>> createNotesForLinks(
    List<String> titles, {
    NoteKind kind = NoteKind.living,
  });
}
