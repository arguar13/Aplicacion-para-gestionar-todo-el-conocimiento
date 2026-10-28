import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

/// Qué documentos procesados pide la vista guardada [view] de un cuaderno por
/// consulta (F41, paso 5).
///
/// Un cuaderno se arma **solo con documentos procesados**, y la vista que elige
/// uno por consulta se guardó en la Biblioteca. Acá se dice qué significa cada
/// filtro sobre un procesado, que es otra cosa que una fuente:
///
/// - **El texto buscado** se busca en su título y en sus partes —lo que la
///   persona eligió—, no en la fuente.
/// - **El tipo de fuente** es el de la fuente de la que salió: «libros» trae lo
///   procesado de libros.
/// - **Los temas, las etiquetas y las propiedades** son los del procesado
///   (decisión F): los que la IA o la persona le dieron a él.
/// - **Unos elementos puntuales** quedan como están.
/// - **«Sin tema»** no llega: una vista guardada no lo guarda
///   (`libraryQueryToJson`), porque es la lista para ordenar, no un filtro
///   que se nombre.
/// - **El procesamiento técnico** de un procesado siempre está listo —su texto
///   ya está—: una vista de lo pendiente o de lo que falló no trae ninguno.
/// - **Lo decidido en la Bandeja** es de las fuentes: un procesado no pasa por
///   la Bandeja, como una nota, así que una vista de «Por revisar» o «Triado»
///   no trae ninguno. Es la misma regla de la Biblioteca.
///
/// El orden se traduce al más parecido y la página se ignora: un cuaderno es
/// lo que la vista trae, entero.
ProcessedQuery processedQueryForView(LibraryQuery view) {
  final noneReady =
      view.processingStates.isNotEmpty &&
      !view.processingStates.contains(ProcessingState.ready);
  final byInbox = view.inboxStatuses.isNotEmpty;
  return ProcessedQuery(
    searchText: view.searchText,
    spaceId: view.spaceId,
    tagIds: view.tagIds,
    propertyValueIds: view.propertyValueIds,
    sourceKinds: view.sourceKinds,
    ids: noneReady || byInbox ? const <String>{} : view.ids,
    sortBy: switch (view.sortBy) {
      LibrarySort.capturedAt ||
      LibrarySort.publishedAt => ProcessedSort.createdAt,
      LibrarySort.updatedAt || LibrarySort.relevance => ProcessedSort.updatedAt,
      LibrarySort.title => ProcessedSort.title,
    },
    descending: view.descending,
  );
}

/// Qué documentos procesados tiene un cuaderno a mano con [itemIds]: esos, en
/// el orden de «Procesado» —lo último que se trabajó, arriba—.
ProcessedQuery processedQueryForMembers(Set<String> itemIds) =>
    ProcessedQuery(ids: itemIds);
