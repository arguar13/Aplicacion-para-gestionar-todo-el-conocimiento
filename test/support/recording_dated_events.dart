import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/repositories/dated_event_repository.dart';

/// Un repositorio de hechos fechados que solo anota lo que le piden agregar
/// (F40), para las pruebas de las pantallas que no tienen una base detrás.
class RecordingDatedEvents implements DatedEventRepository {
  /// Cada hecho agregado, con el elemento al que se agregó.
  final added = <({String itemId, DatedEventInput input})>[];

  @override
  Stream<List<DatedEvent>> watchForItem(String itemId) =>
      Stream.value(const []);

  @override
  Future<Either<Failure, DatedEvent>> add(
    String itemId,
    DatedEventInput input,
  ) async {
    added.add((itemId: itemId, input: input));
    return right(
      DatedEvent(
        id: 'h${added.length}',
        itemId: itemId,
        title: input.title,
        date: input.date,
        end: input.end,
        origin: ContentOrigin.user,
        renditionId: input.renditionId,
        startOffset: input.startOffset,
        endOffset: input.endOffset,
        excerpt: input.excerpt,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
