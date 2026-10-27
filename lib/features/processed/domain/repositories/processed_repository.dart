import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';

/// Un texto de una fuente, para copiar de él (F41).
@immutable
class ProcessedSourceText {
  const ProcessedSourceText({required this.renditionId, required this.text});

  final String renditionId;
  final String text;
}

/// Lo que [ProcessedRepository.commit] guarda de una vez.
@immutable
class ProcessedCommit {
  const ProcessedCommit({
    required this.sourceItemId,
    required this.plans,
    required this.expectedStatus,
  });

  /// La fuente: de ella salen el id, el título y el tipo del documento si
  /// todavía no existe. Nunca se escribe.
  final String sourceItemId;

  /// Cómo queda cada sección que se tocó, armado sobre lo que había.
  final List<SectionPlan> plans;

  /// En qué estaba el documento cuando se armaron los planes: si cambió
  /// mientras tanto, no se guarda nada.
  final ProcessedDocumentStatus expectedStatus;
}

/// Los documentos procesados (F41): la información pura que la persona sacó de
/// cada fuente. Ver `ProcessedDocuments` y `ProcessedParts`.
///
/// Nada de acá escribe la fuente: la lee para copiar de ella, y su único
/// enlace con ella es `processed_documents.source_item_id`.
abstract interface class ProcessedRepository {
  // --- «Procesado», la lista ---------------------------------------------

  /// Los documentos que cumplen [query], en su orden, y cada cambio. Nunca los
  /// de la papelera.
  Stream<List<ProcessedDocumentSummary>> watchDocuments(ProcessedQuery query);

  /// Cuántos documentos cumplen [query], sin paginar, y cada cambio.
  Stream<int> watchCount(ProcessedQuery query);

  /// Los ids de todo lo que cumple [query], en su orden: para acotar a
  /// procesados un cuaderno o el chat (paso 5) sin armar cada documento.
  Future<Either<Failure, List<String>>> matchingIds(ProcessedQuery query);

  /// Las fuentes que ya tienen su documento procesado vivo, y cada cambio: el
  /// chip «Procesado» del selector de «Volver a triar».
  Stream<Set<String>> watchProcessedSourceIds();

  // --- Un documento ---------------------------------------------------------

  /// El documento [documentId] —vivo o en la papelera—, o `null` si no existe,
  /// y cada cambio.
  Stream<ProcessedDocument?> watchDocument(String documentId);

  /// El documento procesado de la fuente [sourceItemId], o `null` si no tiene,
  /// y cada cambio: el acceso desde el detalle de la fuente.
  Stream<ProcessedDocument?> watchForSource(String sourceItemId);

  /// En qué está el documento [documentId].
  Future<Either<Failure, ProcessedDocumentStatus>> statusOf(String documentId);

  /// Las partes de [section] de [documentId], en orden, y cada cambio. Con
  /// [limit], solo ese tramo desde [offset]: así se piden las páginas del texto
  /// de un libro, de a una o de a pocas, sin traer el libro entero.
  Stream<List<ProcessedPart>> watchParts(
    String documentId,
    ProcessedSection section, {
    int offset = 0,
    int? limit,
  });

  /// Las partes de [documentId] —de [sections], o de todas—, por sección y en
  /// orden: lo que lee la IA al organizar un procesado (paso 6).
  Future<Either<Failure, List<ProcessedPart>>> partsOf(
    String documentId, {
    Set<ProcessedSection>? sections,
  });

  // --- La fuente, solo para leer -------------------------------------------

  /// Lo que la fuente [sourceItemId] ofrece para procesar. Falla si no es una
  /// fuente viva. Con [countWords] cuenta además las palabras de su texto, en
  /// otro hilo si es largo.
  Future<Either<Failure, ProcessedSourceMaterial>> materialOf(
    String sourceItemId, {
    bool countWords = true,
  });

  /// El texto de [renditionId] de la fuente [sourceItemId] —o, sin
  /// [renditionId], el de la forma de la que sale todo—; `null` si no tiene, o
  /// si la forma no es de esa fuente.
  Future<Either<Failure, ProcessedSourceText?>> sourceText(
    String sourceItemId, {
    String? renditionId,
  });

  // --- Escribir ------------------------------------------------------------

  /// Guarda [commit] en una sola transacción: crea el documento si no existe
  /// —con el título y el tipo de su fuente— o lo saca de la papelera, y deja
  /// cada sección como dice su plan. Devuelve cómo deshacerlo.
  ///
  /// No escribe nada si el documento ya no está como cuando se armaron los
  /// planes —en otro estado, o con otras partes en una sección tocada—.
  Future<Either<Failure, ProcessUndo>> commit(ProcessedCommit commit);

  /// Deja el documento como estaba antes del [commit] que dio [undo]: borra lo
  /// que nació en él, devuelve cada sección tocada a como estaba y lo vuelve a
  /// la papelera si estaba ahí.
  Future<Either<Failure, Unit>> undo(ProcessUndo undo);

  /// Cambia el texto de la parte [partId] por [content]: una parte copiada
  /// queda editada, y «Actualizar» ya no la pisa. Devuelve la parte como
  /// estaba, para deshacer con [restorePart].
  Future<Either<Failure, ProcessedPart>> editPart(
    String partId,
    String content,
  );

  /// Saca la parte [partId] y corre las que la seguían. Devuelve la parte
  /// como estaba, para deshacer con [restorePart].
  Future<Either<Failure, ProcessedPart>> removePart(String partId);

  /// Devuelve [part] tal como estaba —su texto, su lugar y su ancla—: deshace
  /// [editPart] o [removePart].
  Future<Either<Failure, Unit>> restorePart(ProcessedPart part);
}
