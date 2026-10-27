import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_step.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_history.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

import '../../../../support/library_harness.dart';

/// El historial de «Deshacer» de la Bandeja (F28), sin pantalla: contra la
/// base real del arnés.
void main() {
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  InboxHistory history() =>
      harness.container.read(inboxHistoryProvider.notifier);

  KnowledgeItem sourceItem(int n, ProcessingState processing) {
    final now = DateTime(2026, 9, 18, 10);
    return KnowledgeItem(
      id: 'item-$n',
      title: 'Fuente $n',
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: processing,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<String> seedSource({
    ProcessingState processing = ProcessingState.ready,
  }) async {
    final item = sourceItem(counter++, processing);
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item.id;
  }

  Future<InboxStep> decide(String id, ItemState to) async {
    await harness.container
        .read(inboxRepositoryProvider)
        .transitionState(itemId: id, to: to);
    final step = InboxStep(
      itemId: id,
      title: id,
      kind: to == ItemState.discarded
          ? InboxStepKind.discarded
          : InboxStepKind.triaged,
    );
    history().record(step);
    return step;
  }

  Future<ItemState> stateOf(String id) async {
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    return row.state;
  }

  test('sin nada que deshacer devuelve null', () async {
    expect(await history().undoLast(), isNull);
  });

  test('deshace del último al primero, devolviendo cada paso', () async {
    final first = await seedSource();
    final second = await seedSource();
    final triaged = await decide(first, ItemState.triaged);
    final discarded = await decide(second, ItemState.discarded);

    expect((await history().undoLast())!.getRight().toNullable(), discarded);
    expect(await stateOf(second), ItemState.processed);
    expect(await stateOf(first), ItemState.triaged);

    expect((await history().undoLast())!.getRight().toNullable(), triaged);
    expect(await stateOf(first), ItemState.processed);
    expect(history().last, isNull);
  });

  test('deshacer devuelve a la espera que le toca ahora (F41): lo que se '
      'descartó mientras se procesaba y después terminó vuelve listo; lo que '
      'todavía se procesa, como recién guardado', () async {
    final terminado = await seedSource(processing: ProcessingState.processing);
    final sigue = await seedSource(processing: ProcessingState.processing);
    expect(await stateOf(terminado), ItemState.captured);
    await decide(sigue, ItemState.discarded);
    await decide(terminado, ItemState.discarded);
    // El procesamiento termina con la fuente ya descartada: el espejo no pisa
    // la decisión.
    await harness.container
        .read(libraryRepositoryProvider)
        .save(sourceItem(0, ProcessingState.ready));
    expect(await stateOf(terminado), ItemState.discarded);

    await history().undoLast();
    await history().undoLast();

    expect(await stateOf(terminado), ItemState.processed);
    expect(await stateOf(sigue), ItemState.captured);
  });

  test('recuerda hasta su capacidad: el más viejo se suelta', () async {
    for (var i = 0; i <= InboxHistory.capacity; i++) {
      history().record(
        InboxStep(
          itemId: 'item-$i',
          title: 'Fuente $i',
          kind: InboxStepKind.triaged,
        ),
      );
    }

    final steps = harness.container.read(inboxHistoryProvider);
    expect(steps, hasLength(InboxHistory.capacity));
    expect(steps.first.itemId, 'item-1');
    expect(steps.last.itemId, 'item-${InboxHistory.capacity}');
  });

  test('un paso que ya no se puede deshacer se informa y se suelta, sin '
      'trabar los anteriores', () async {
    final kept = await seedSource();
    await decide(kept, ItemState.triaged);
    history().record(
      const InboxStep(
        itemId: 'borrada-para-siempre',
        title: 'Ya no existe',
        kind: InboxStepKind.discarded,
      ),
    );

    final failed = await history().undoLast();
    expect(failed!.getLeft().toNullable(), isA<Failure>());

    final undone = await history().undoLast();
    expect(undone!.getRight().toNullable()!.itemId, kept);
    expect(await stateOf(kept), ItemState.processed);
  });
}
