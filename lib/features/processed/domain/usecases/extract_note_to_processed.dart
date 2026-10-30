import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

/// «Extraer como nota» (F41, decisión J): un pasaje de una fuente va siempre
/// a las notas de su documento procesado, desde cualquier pantalla —el
/// detalle, el modo lectura, cualquier visor—. Un mismo gesto no deja la nota
/// en dos lugares según dónde se hizo.
///
/// - **De una fuente viva**: el pasaje, tal cual y con su ancla, a la sección
///   Notas. Si la fuente todavía no tiene documento procesado, nace con esa
///   sola nota. **No la tría** ni toca su estado de la Bandeja: extraer es
///   un pedido explícito, y triar sigue siendo elegir qué más va.
/// - **De una fuente en la papelera**: nada; quien llama ofrece restaurarla.
/// - **De un documento procesado** (decisión I): a sus propias notas, como
///   algo suyo —el texto que se ve ahí no es el de la fuente, así que no lleva
///   ancla—.
/// - **De una nota propia**: [ExtractLooseNote], y quien llama saca la nota
///   suelta vinculada de siempre.
///
/// Lo que se guarda pasa por [ProcessSourceUseCase]: agregar sin repetir, y
/// su [ProcessUndo] saca solo esa nota —y el documento, si nació para ella—.
class ExtractNoteToProcessed {
  const ExtractNoteToProcessed(this._repository, this._process);

  final ProcessedRepository _repository;
  final ProcessSourceUseCase _process;

  /// Extrae `[start, end)` del texto de la forma [renditionId] de [itemId];
  /// [excerpt] es ese tramo, como se ve.
  Future<Either<Failure, ExtractNoteOutcome>> call({
    required String itemId,
    required String renditionId,
    required int start,
    required int end,
    required String excerpt,
  }) async {
    final target = await _repository.extractTargetOf(itemId);
    return target.match(left, (target) async {
      switch (target) {
        case ExtractAsLooseNote():
          return right(const ExtractLooseNote());
        case ExtractSourceInTrash(:final sourceItemId):
          return right(ExtractRefusedInTrash(sourceItemId));
        case ExtractToSource(:final sourceItemId):
          return _saved(
            await _process(sourceItemId, {
              ProcessedSection.notes: SectionEdit.add(
                SectionInput.drafts([
                  ProcessedDraft.cut(
                    ProcessedAnchor(
                      renditionId: renditionId,
                      start: start,
                      end: end,
                    ),
                  ),
                ]),
              ),
            }),
          );
        case ExtractToProcessed(:final sourceItemId):
          if (sourceItemId == null) {
            return left(
              const Failure.validation(
                message:
                    'Este documento procesado perdió su fuente: sus notas se '
                    'escriben desde el documento.',
              ),
            );
          }
          return _saved(
            await _process(sourceItemId, {
              ProcessedSection.notes: SectionEdit.add(
                SectionInput.drafts([ProcessedDraft.written(excerpt)]),
              ),
            }),
          );
      }
    });
  }

  /// Una nota escrita a mano en las notas del documento procesado
  /// [documentId] (F45, paso 7b: «Nota», en «Crear»): el mismo camino que lo
  /// extraído de él, como algo suyo y sin ancla. Una nota vacía no se guarda.
  ///
  /// Solo de un documento procesado con su fuente: su sección Notas se arma
  /// contra ella ([ProcessSourceUseCase]).
  Future<Either<Failure, ExtractNoteOutcome>> write({
    required String documentId,
    required String text,
  }) async {
    final note = text.trim();
    if (note.isEmpty) {
      return left(const Failure.validation(message: 'La nota está vacía.'));
    }
    final target = await _repository.extractTargetOf(documentId);
    return target.match(left, (target) async {
      if (target case ExtractToProcessed(:final sourceItemId?)) {
        return _saved(
          await _process(sourceItemId, {
            ProcessedSection.notes: SectionEdit.add(
              SectionInput.drafts([ProcessedDraft.written(note)]),
            ),
          }),
        );
      }
      return left(
        const Failure.validation(
          message:
              'Solo un documento procesado con su fuente suma notas escritas '
              'a mano.',
        ),
      );
    });
  }

  /// Deshace lo que dejó [ExtractedToProcessed]: saca esa nota sola.
  Future<Either<Failure, Unit>> undo(ProcessUndo undo) => _process.undo(undo);

  static Either<Failure, ExtractNoteOutcome> _saved(
    Either<Failure, ProcessOutcome> outcome,
  ) => outcome.map(
    (outcome) => ExtractedToProcessed(
      documentId: outcome.documentId,
      created: outcome.created,
      unchanged: outcome.unchanged,
      undo: outcome.undo,
    ),
  );
}
