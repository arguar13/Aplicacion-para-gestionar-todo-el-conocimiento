import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';

/// En qué está el documento procesado de una fuente.
enum ProcessedDocumentStatus {
  /// Todavía no existe: procesar lo crea.
  absent,

  /// Existe y está a la vista en «Procesado».
  active,

  /// Está en la papelera: procesar lo saca de ahí —con lo que tenía— antes de
  /// cambiarlo, en vez de empezar otro de cero.
  trashed,
}

/// Lo que hace falta para deshacer un procesado (F41): cómo estaban las
/// secciones que se tocaron y en qué estaba el documento.
///
/// Vive en memoria, como `DatedEventRemoval`: un comprobante perdido solo
/// significa que ya no se puede deshacer. Deshacer nunca toca la fuente —el
/// procesado no la tocó—.
@immutable
class ProcessUndo {
  const ProcessUndo({
    required this.documentId,
    required this.previousStatus,
    required this.previous,
  });

  final String documentId;

  /// En qué estaba el documento antes: si no existía, deshacer lo borra; si
  /// estaba en la papelera, vuelve a ella.
  final ProcessedDocumentStatus previousStatus;

  /// Las secciones tocadas, tal como estaban —vacías si no tenían nada—.
  final Map<ProcessedSection, List<ProcessedPart>> previous;
}

/// Cuánto cambió una sección.
@immutable
class SectionChangeTally {
  const SectionChangeTally({
    required this.added,
    required this.removed,
    required this.kept,
  });

  final int added;
  final int removed;
  final int kept;

  /// Cuántas partes queda teniendo.
  int get total => added + kept;
}

/// Lo que dejó procesar una fuente (F41).
@immutable
class ProcessOutcome {
  const ProcessOutcome({
    required this.documentId,
    required this.created,
    required this.sections,
    required this.undo,
  });

  /// El documento procesado.
  final String documentId;

  /// Si el documento nació ahora.
  final bool created;

  /// Cuánto cambió cada sección que se pidió.
  final Map<ProcessedSection, SectionChangeTally> sections;

  /// Para «Deshacer».
  final ProcessUndo undo;

  /// Si no cambió nada: todo lo pedido ya estaba.
  bool get unchanged =>
      !created &&
      sections.values.every((tally) => tally.added == 0 && tally.removed == 0);
}

/// Cómo va a quedar una sección, para la vista previa de la hoja «¿Qué va a
/// Procesado?» (F41): sin guardar nada.
@immutable
class SectionPreview {
  const SectionPreview({
    required this.parts,
    required this.words,
    required this.tally,
  });

  /// Cuántas partes queda teniendo: páginas, oraciones, notas o fragmentos.
  final int parts;

  /// Cuántas palabras suma.
  final int words;

  /// Cuánto cambia respecto de lo que hay.
  final SectionChangeTally tally;
}
