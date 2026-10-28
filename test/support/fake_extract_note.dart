import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/usecases/extract_note_to_processed.dart';

/// «Extraer como nota» que contesta siempre [outcome] y anota lo que se le
/// pidió (F41, decisión J). Por defecto, que es una nota propia: quien llama
/// saca la nota suelta vinculada de siempre. Para las pruebas de los visores
/// que no tienen base de datos.
class FakeExtractNote implements ExtractNoteToProcessed {
  FakeExtractNote([this.outcome = const ExtractLooseNote()]);

  ExtractNoteOutcome outcome;
  final asked = <({String itemId, String renditionId, int start, int end})>[];
  final undone = <ProcessUndo>[];

  @override
  Future<Either<Failure, ExtractNoteOutcome>> call({
    required String itemId,
    required String renditionId,
    required int start,
    required int end,
    required String excerpt,
  }) async {
    asked.add((
      itemId: itemId,
      renditionId: renditionId,
      start: start,
      end: end,
    ));
    return right(outcome);
  }

  @override
  Future<Either<Failure, Unit>> undo(ProcessUndo undo) async {
    undone.add(undo);
    return right(unit);
  }
}
