import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

/// Triar en la Bandeja (F41): armar el documento procesado de la fuente con lo
/// elegido y dejarla triada, **las dos cosas o ninguna**.
///
/// Primero el procesado —es lo que puede no tener nada que guardar— y después
/// el estado. Si el estado no se puede cambiar, el procesado se deshace: no
/// queda un documento en «Procesado» de una fuente que sigue en la Bandeja.
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
  /// [edits] y la tría.
  Future<Either<Failure, ProcessOutcome>> call(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits,
  ) => _thenTriage(sourceItemId, _process(sourceItemId, edits));

  /// «Pasar todo sin modificar»: el texto original entero, con su enlace, y
  /// nada más (ver `ProcessSourceUseCase.passUnchanged`), y la tría.
  Future<Either<Failure, ProcessOutcome>> passUnchanged(String sourceItemId) =>
      _thenTriage(sourceItemId, _process.passUnchanged(sourceItemId));

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
