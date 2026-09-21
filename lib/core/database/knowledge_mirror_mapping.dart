import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

/// Funciones puras que clasifican una fila del esquema viejo —o un
/// [KnowledgeItem] recién guardado— según el modelo `item`/`source`/`note`
/// de F1. Un solo criterio de clasificación en todo el proyecto: lo usan el
/// espejo en vivo de F3 (`LibraryRepositoryImpl._mirrorItem`) y su catch-up
/// (`mirror_unmirrored_items_v10.dart`). El backfill de una sola vez de F1, que
/// también lo usaba, se retiró con los pasos anteriores a v15.

/// Una nota manual o armada con el editor de bloques —las dos únicas formas
/// hoy de que el usuario cree contenido sin que venga de afuera— es una
/// nota; todo lo demás es una fuente.
ItemKind itemKindFor(SourceKind sourceKind) =>
    sourceKind == SourceKind.manualNote ? ItemKind.note : ItemKind.source;

/// El estado inicial de un elemento que todavía no tiene fila en el
/// espejo: `processed` si el pipeline técnico ya terminó, `captured` en
/// cualquier otro caso.
ItemState initialItemStateFor(ProcessingState processingState) =>
    switch (processingState) {
      ProcessingState.ready => ItemState.processed,
      ProcessingState.pending ||
      ProcessingState.processing ||
      ProcessingState.failed => ItemState.captured,
    };

SourceProcessingStatus sourceProcessingStatusFor(
  ProcessingState processingState,
) => switch (processingState) {
  ProcessingState.pending => SourceProcessingStatus.pending,
  ProcessingState.processing => SourceProcessingStatus.running,
  ProcessingState.ready => SourceProcessingStatus.done,
  ProcessingState.failed => SourceProcessingStatus.failed,
};

/// El inverso de [sourceProcessingStatusFor]: el estado del pipeline técnico
/// que la app usa para dibujar una fila, a partir del que guarda `source`.
///
/// Una NOTA no tiene fila en `source` ni pipeline que esperar: está lista
/// desde que se guarda.
ProcessingState processingStateFor(SourceProcessingStatus? status) =>
    switch (status) {
      null || SourceProcessingStatus.done => ProcessingState.ready,
      SourceProcessingStatus.pending => ProcessingState.pending,
      SourceProcessingStatus.running => ProcessingState.processing,
      SourceProcessingStatus.failed => ProcessingState.failed,
    };

/// El próximo `ItemState` del espejo, dado el estado actual (si ya
/// existía fila) y el estado técnico del pipeline.
///
/// El único avance automático es `captured → processed`. Nunca retrocede
/// ni pisa una decisión de triaje ya tomada: sin esto, editar un elemento
/// después de triarlo (cambiarle el título, por ejemplo) lo devolvería en
/// silencio a `processed` en cada `save()` posterior —`ProcessItemUseCase`
/// llama `save()` más de una vez por elemento, y nada distingue "esto es
/// una edición" de "esto es el pipeline terminando" salvo esta regla—.
///
/// Una referencia ([SourceKind.reference]) nace **triada**: se carga a
/// propósito —a mano o desde un `.bib`— y no pasa por la Bandeja. Importar una
/// bibliografía de 300 entradas no la inunda (F15).
ItemState nextMirrorState({
  required ItemState? current,
  required ProcessingState processingState,
  SourceKind? sourceKind,
}) {
  if (current == null) {
    if (sourceKind == SourceKind.reference) return ItemState.triaged;
    return initialItemStateFor(processingState);
  }
  if (current == ItemState.captured &&
      processingState == ProcessingState.ready) {
    return ItemState.processed;
  }
  return current;
}

/// `KnowledgeEntries.deviceId` no tiene ningún lector hoy —ver el
/// comentario en `knowledge_entries.dart`, "preparado para cuando exista
/// sync de verdad"—, así que todo lo que escribe el espejo antes de que
/// eso exista usa el mismo placeholder explícito.
const kMirrorDeviceIdPlaceholder = 'f3-espejo-sin-sync';
