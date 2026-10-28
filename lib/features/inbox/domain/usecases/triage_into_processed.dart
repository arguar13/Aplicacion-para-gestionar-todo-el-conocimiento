import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

/// Lo que dejó «Volver a triar» una fuente (F41, paso 4): lo que cambió en su
/// documento procesado y, si la fuente todavía no estaba triada, desde dónde
/// se la trió —para devolverla ahí al deshacer—.
@immutable
class RetriageOutcome {
  const RetriageOutcome({
    required this.sourceItemId,
    required this.processed,
    this.triagedFrom,
  });

  final String sourceItemId;

  /// Lo que cambió en el documento procesado, con su «Deshacer».
  final ProcessOutcome processed;

  /// Dónde estaba la fuente respecto de la Bandeja si «Volver a triar» la
  /// trió —esperando, o descartada—; `null` si ya estaba triada y su estado
  /// no se tocó.
  final InboxStatus? triagedFrom;
}

/// Triar en la Bandeja (F41): armar el documento procesado de la fuente con lo
/// elegido y dejarla triada, **las dos cosas o ninguna**.
///
/// Primero el procesado —es lo que puede no tener nada que guardar— y después
/// el estado. Si el estado no se puede cambiar, el procesado se deshace: no
/// queda un documento en «Procesado» de una fuente que sigue en la Bandeja.
///
/// «Volver a triar» ([retriage]) es el mismo camino desde cualquier lado: lo
/// que no estaba triado queda triado, y lo que ya lo estaba no cambia de
/// estado.
///
/// Nunca toca la fuente más que en su estado de la Bandeja: ni su texto, ni
/// su archivo, ni sus datos (decisión G).
class TriageIntoProcessed {
  const TriageIntoProcessed({
    required InboxRepository inbox,
    required ProcessSourceUseCase process,
  }) : _inbox = inbox,
       _process = process;

  final InboxRepository _inbox;
  final ProcessSourceUseCase _process;

  /// «Listo» en la hoja «¿Qué va a Procesado?»: procesa [sourceItemId] con
  /// [edits] —y, si se pidió, con la copia de su original ([original])— y la
  /// tría.
  Future<Either<Failure, ProcessOutcome>> call(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits, {
    OriginalEdit? original,
  }) => _thenTriage(
    sourceItemId,
    _process(sourceItemId, edits, original: original),
  );

  /// «Pasar todo sin modificar»: el texto original entero, con su enlace, y
  /// nada más (ver `ProcessSourceUseCase.passUnchanged`), y la tría.
  Future<Either<Failure, ProcessOutcome>> passUnchanged(String sourceItemId) =>
      _thenTriage(sourceItemId, _process.passUnchanged(sourceItemId));

  /// «Volver a triar» (F41, paso 4): procesa [sourceItemId] con [edits]
  /// —agregar, actualizar, reemplazar o quitar, por sección— desde donde sea:
  /// la Bandeja, el documento procesado o el detalle de la fuente.
  ///
  /// - Si la fuente ya estaba triada (o destilada), solo cambia su documento:
  ///   su estado no se toca.
  /// - Si no —espera en la Bandeja, o se descartó—, queda triada como al
  ///   triarla en la Bandeja, las dos cosas o ninguna.
  ///
  /// Con [original], también la copia de su original (decisión H).
  ///
  /// Falla, sin escribir nada, si [sourceItemId] no es una fuente viva.
  Future<Either<Failure, RetriageOutcome>> retriage(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits, {
    OriginalEdit? original,
  }) async {
    final status = await _inbox.statusOf(sourceItemId);
    if (status.getLeft().toNullable() case final failure?) return left(failure);
    final from = status.getRight().toNullable();
    if (from == null) {
      return left(
        const Failure.validation(
          message:
              'Solo se vuelve a triar una fuente de la Biblioteca que no esté '
              'en la papelera.',
        ),
      );
    }
    if (from == InboxStatus.triaged) {
      final processed = await _process(sourceItemId, edits, original: original);
      return processed.map(
        (outcome) =>
            RetriageOutcome(sourceItemId: sourceItemId, processed: outcome),
      );
    }
    final triaged = await call(sourceItemId, edits, original: original);
    return triaged.map(
      (outcome) => RetriageOutcome(
        sourceItemId: sourceItemId,
        processed: outcome,
        triagedFrom: from,
      ),
    );
  }

  /// Deshace lo que dejó [retriage]: el documento procesado vuelve a como
  /// estaba y, si la fuente se trió ahí, vuelve adonde estaba —a la Bandeja,
  /// al estado de espera que le toque ahora, o a descartada—.
  ///
  /// Primero el procesado, como en la Bandeja: si no se puede deshacer
  /// —alguien lo cambió mientras tanto—, la fuente queda triada con su
  /// documento, sin contradecirse.
  Future<Either<Failure, Unit>> undoRetriage(RetriageOutcome outcome) async {
    final undone = await _process.undo(outcome.processed.undo);
    if (undone.isLeft()) return undone;
    final id = outcome.sourceItemId;
    return switch (outcome.triagedFrom) {
      InboxStatus.pending => _inbox.returnToInbox(id),
      InboxStatus.discarded => _inbox.transitionState(
        itemId: id,
        to: ItemState.discarded,
      ),
      InboxStatus.triaged || null => right(unit),
    };
  }

  Future<Either<Failure, ProcessOutcome>> _thenTriage(
    String sourceItemId,
    Future<Either<Failure, ProcessOutcome>> processing,
  ) async {
    final processed = await processing;
    return processed.match(left, (outcome) async {
      final triaged = await _inbox.transitionState(
        itemId: sourceItemId,
        to: ItemState.triaged,
      );
      return triaged.match((failure) async {
        // Lo que no se pudo deshacer no tapa el fallo de verdad: es el que
        // explica por qué la fuente sigue en la Bandeja.
        await _process.undo(outcome.undo);
        return left(failure);
      }, (_) => right(outcome));
    });
  }
}
