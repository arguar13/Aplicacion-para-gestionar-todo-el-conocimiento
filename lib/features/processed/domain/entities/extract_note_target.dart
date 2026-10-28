import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';

/// Adónde va «Extraer como nota» desde un elemento (F41, decisión J): lo
/// decide qué es el elemento, no la pantalla desde la que se extrae.
sealed class ExtractNoteTarget {
  const ExtractNoteTarget();
}

/// Una fuente viva: la nota va a su documento procesado, que nace con ella
/// si todavía no existe.
@immutable
final class ExtractToSource extends ExtractNoteTarget {
  const ExtractToSource(this.sourceItemId);

  final String sourceItemId;

  @override
  bool operator ==(Object other) =>
      other is ExtractToSource && other.sourceItemId == sourceItemId;

  @override
  int get hashCode => sourceItemId.hashCode;
}

/// Una fuente en la papelera: no acepta notas hasta que se restaura.
@immutable
final class ExtractSourceInTrash extends ExtractNoteTarget {
  const ExtractSourceInTrash(this.sourceItemId);

  final String sourceItemId;

  @override
  bool operator ==(Object other) =>
      other is ExtractSourceInTrash && other.sourceItemId == sourceItemId;

  @override
  int get hashCode => sourceItemId.hashCode;
}

/// Un documento procesado (decisión I): lo extraído va a sus propias notas,
/// como algo suyo. [sourceItemId] es la fuente de la que salió, o `null` si
/// se borró de verdad.
@immutable
final class ExtractToProcessed extends ExtractNoteTarget {
  const ExtractToProcessed(this.documentId, {this.sourceItemId});

  final String documentId;
  final String? sourceItemId;

  @override
  bool operator ==(Object other) =>
      other is ExtractToProcessed &&
      other.documentId == documentId &&
      other.sourceItemId == sourceItemId;

  @override
  int get hashCode => Object.hash(documentId, sourceItemId);
}

/// Una nota propia: no tiene documento procesado, así que sigue sacando una
/// nota suelta vinculada, como siempre.
@immutable
final class ExtractAsLooseNote extends ExtractNoteTarget {
  const ExtractAsLooseNote();

  @override
  bool operator ==(Object other) => other is ExtractAsLooseNote;

  @override
  int get hashCode => 0;
}

/// Lo que dejó extraer una nota (decisión J).
sealed class ExtractNoteOutcome {
  const ExtractNoteOutcome();
}

/// La nota quedó en el documento procesado [documentId] —que nació para ella
/// si [created]—, con [undo] para sacarla sola. Con [unchanged], ya estaba:
/// no se guardó nada de nuevo.
@immutable
final class ExtractedToProcessed extends ExtractNoteOutcome {
  const ExtractedToProcessed({
    required this.documentId,
    required this.created,
    required this.unchanged,
    required this.undo,
  });

  final String documentId;
  final bool created;
  final bool unchanged;
  final ProcessUndo undo;
}

/// La fuente [sourceItemId] está en la papelera: no se guardó nada.
@immutable
final class ExtractRefusedInTrash extends ExtractNoteOutcome {
  const ExtractRefusedInTrash(this.sourceItemId);

  final String sourceItemId;
}

/// No es de una fuente ni de un documento procesado: quien llama hace la nota
/// suelta de siempre.
final class ExtractLooseNote extends ExtractNoteOutcome {
  const ExtractLooseNote();
}
