import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';

/// Lo que quitar un hecho dejó, para poder deshacerlo mientras el aviso sigue
/// a la vista.
///
/// Si el hecho era de la IA, quitarlo también lo anota como «no era» para que
/// no vuelva: [rejectionId] es esa nota, y deshacer la olvida. Vive en
/// memoria, como `AiRejectionReceipt`: un comprobante perdido solo significa
/// que ya no se puede deshacer.
@immutable
class DatedEventRemoval {
  const DatedEventRemoval({required this.event, this.rejectionId});

  /// El hecho tal como estaba.
  final DatedEvent event;

  /// La fila de `ai_rejections` que lo recuerda; `null` si el hecho era de la
  /// persona.
  final String? rejectionId;
}

/// Los hechos fechados dentro de los documentos (F40).
abstract interface class DatedEventRepository {
  /// Los hechos fechados de [itemId], en orden cronológico, emitiendo de nuevo
  /// cada vez que algo cambia.
  Stream<List<DatedEvent>> watchForItem(String itemId);

  /// Pone un hecho a mano en [itemId]: es de la persona.
  Future<Either<Failure, DatedEvent>> add(String itemId, DatedEventInput input);

  /// Pone los hechos [drafts] que la pasada [runId] leyó de [itemId]: son de
  /// la IA, y deshacer la pasada los saca. Devuelve cuántos agregó.
  ///
  /// No agrega lo que ya está —la misma fecha con la misma cita en el
  /// elemento, venga de quien venga—, lo que la persona ya quitó
  /// («no era»), ni un borrador que no es válido; tampoco repite dos veces
  /// lo mismo dentro de [drafts]. Lo que sobra no es un error: la pasada
  /// cuenta lo que de verdad puso.
  Future<Either<Failure, int>> addFromAi({
    required String itemId,
    required String runId,
    required List<DatedEventInput> drafts,
  });

  /// Cambia el título y las fechas de [id]. Editar un hecho de la IA lo vuelve
  /// de la persona: deja de ser de su pasada y deshacerla ya no se lo lleva.
  Future<Either<Failure, DatedEvent>> update(
    String id, {
    required String title,
    required HistoricalDate date,
    HistoricalDate? end,
  });

  /// Quita [id]. Si era de la IA, queda anotado como «no era».
  Future<Either<Failure, DatedEventRemoval>> remove(String id);

  /// Devuelve lo que [remove] quitó, con su pasada, y olvida el «no era».
  Future<Either<Failure, Unit>> undoRemove(DatedEventRemoval removal);
}
