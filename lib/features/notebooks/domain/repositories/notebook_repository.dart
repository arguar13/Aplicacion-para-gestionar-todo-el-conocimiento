import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

/// Los cuadernos (F16, D1): un subconjunto con nombre de la bóveda, manual o
/// por consulta guardada.
///
/// **Solo con documentos procesados** (F41, paso 5): lo que está en un
/// cuaderno es información pura que la persona sacó de sus fuentes, nunca una
/// fuente de la Biblioteca ni una nota suelta. Este repositorio es el único
/// lugar que decide qué puede ser miembro ([addItems]) y qué tiene un cuaderno
/// ([resolveQuery], [memberIds]); el chat, los repasos y «Llenar con IA» lo
/// preguntan acá.
abstract interface class NotebookRepository {
  /// Todos, emitiendo de nuevo cada vez que algo cambia.
  Stream<List<Notebook>> watchAll();

  /// Uno solo, o `null` si no existe o se borró —para que la pantalla de
  /// detalle sepa volver en vez de quedarse mostrando un cuaderno fantasma—.
  Stream<Notebook?> watchById(String id);

  /// Los ids de un cuaderno [NotebookMode.manual], emitiendo de nuevo cada
  /// vez que [addItem]/[removeItem] cambian algo. Vacío en modo `query`: la
  /// pertenencia ahí no vive en `notebook_item`.
  Stream<Set<String>> watchItemIds(String notebookId);

  /// Crea un cuaderno nuevo. [query] es obligatorio en
  /// [NotebookMode.query] e ignorado en [NotebookMode.manual] —empieza sin
  /// elementos, se agregan con [addItem]—.
  Future<Notebook> create({
    required String name,
    required NotebookMode mode,
    LibraryQuery? query,
  });

  Future<void> rename({required String id, required String name});

  /// Descarta el aviso de que el cuaderno [id] se vació al llegar F41: deja
  /// `emptied_for_processed_at` en `null`, y no vuelve. No toca nada más del
  /// cuaderno —ni su fecha—: es un aviso, no un cambio.
  Future<void> dismissEmptiedNotice(String id);

  Future<void> delete(String id);

  /// Agrega [itemId] a un cuaderno [NotebookMode.manual], si es un documento
  /// procesado —ver [addItems]—. Ya estar adentro no es un error: no hace
  /// nada.
  Future<void> addItem({required String notebookId, required String itemId});

  /// [addItem] para varios a la vez (F30): una sola transacción —todos o
  /// ninguno— y un solo aviso a quien mira el cuaderno, no uno por elemento.
  /// Los que ya estaban adentro no cambian nada.
  ///
  /// **Solo entran documentos procesados vivos** (F41, paso 5): una fuente
  /// de la Biblioteca, una nota, uno en la papelera o un id que no existe se
  /// quedan afuera, sin error —quien ofrece qué agregar ya ofrece solo
  /// procesados; esto es la regla, no la pantalla—.
  Future<void> addItems({
    required String notebookId,
    required Iterable<String> itemIds,
  });

  /// Saca [itemId] de un cuaderno [NotebookMode.manual]. El elemento sigue
  /// existiendo en la bóveda; solo deja de contar como parte de este
  /// cuaderno.
  Future<void> removeItem({required String notebookId, required String itemId});

  /// Qué documentos procesados tiene este cuaderno, como consulta de
  /// «Procesado»: la vista guardada traducida a procesados en modo
  /// [NotebookMode.query] (`processedQueryForView`), o [ProcessedQuery.ids]
  /// con lo que [addItem]/[removeItem] dejaron en modo [NotebookMode.manual].
  /// Lo que está en la papelera no entra nunca.
  ///
  /// Falla con un [StateError] si el cuaderno no existe.
  Future<ProcessedQuery> resolveQuery(String notebookId);

  /// Los ids de los documentos procesados de este cuaderno, en el orden de
  /// [resolveQuery], sin armar cada documento: lo que acota el chat, los
  /// repasos y «Llenar con IA». Falla si el cuaderno ya no existe.
  Future<Either<Failure, List<String>>> memberIds(String notebookId);
}
