import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/inbox/domain/usecases/triage_into_processed.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

import '../../../../support/library_harness.dart';

class _FailingInbox extends Mock implements InboxRepository {}

/// Triar a Procesado (F41): el documento procesado y el estado de la fuente,
/// las dos cosas o ninguna. Contra la base real del arnés.
void main() {
  late LibraryHarness harness;
  const text = 'Roma no se hizo en un día. Tardó siglos en hacerse imperio.';

  setUpAll(() => registerFallbackValue(ItemState.triaged));

  setUp(() async {
    harness = await LibraryHarness.create();
    final now = DateTime(2026, 10, 27, 9);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Historia de Roma',
            source: Source(
              id: 'src-fuente',
              kind: SourceKind.document,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: text,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  });

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<int> documents() async =>
      (await harness.database.select(harness.database.processedDocuments).get())
          .length;

  Future<Set<ProcessedSection>> sections() async => {
    for (final part
        in await harness.database.select(harness.database.processedParts).get())
      part.section,
  };

  TriageIntoProcessed triage() =>
      harness.container.read(triageIntoProcessedProvider);

  test(
    '«Listo» arma el documento con lo elegido y deja la fuente triada',
    () async {
      final outcome = await triage()('fuente', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      });

      expect(outcome.isRight(), isTrue);
      expect(outcome.getRight().toNullable()!.created, isTrue);
      expect(await stateOf('fuente'), ItemState.triaged);
      expect(await documents(), 1);
      expect(await sections(), {ProcessedSection.text});
    },
  );

  test(
    '«Pasar todo sin modificar» guarda solo el texto entero y la tría',
    () async {
      final outcome = await triage().passUnchanged('fuente');

      expect(outcome.isRight(), isTrue);
      expect(await stateOf('fuente'), ItemState.triaged);
      expect(await sections(), {ProcessedSection.text});
      final part = await harness.database
          .select(harness.database.processedParts)
          .getSingle();
      expect(part.content, text);
    },
  );

  test('si no hay nada que guardar, la fuente queda en la Bandeja', () async {
    final outcome = await triage()('fuente', const {});

    expect(outcome.isLeft(), isTrue);
    expect(await stateOf('fuente'), ItemState.processed);
    expect(await documents(), 0);
  });

  test('si la fuente no se puede triar, el documento se deshace: no queda un '
      'procesado de algo que sigue en la Bandeja', () async {
    final inbox = _FailingInbox();
    when(
      () => inbox.transitionState(
        itemId: any(named: 'itemId'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (_) async => left(const Failure.cache(message: 'La base no contestó.')),
    );
    final useCase = TriageIntoProcessed(
      inbox: inbox,
      process: harness.container.read(processSourceUseCaseProvider),
    );

    final outcome = await useCase.passUnchanged('fuente');

    expect(
      outcome.getLeft().toNullable(),
      const Failure.cache(message: 'La base no contestó.'),
    );
    expect(await documents(), 0);
    expect(await stateOf('fuente'), ItemState.processed);
  });
}
