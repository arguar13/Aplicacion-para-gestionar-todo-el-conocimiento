import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
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
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

class _FailingInbox extends Mock implements InboxRepository {}

class _FailingProcess extends Mock implements ProcessSourceUseCase {}

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

  /// Una fuente con su archivo: lo que se puede copiar a Procesado.
  Future<void> saveWithFile() async {
    final now = DateTime(2026, 10, 27, 9);
    final file = await harness.files.save(
      bytes: Uint8List.fromList(text.codeUnits),
      suggestedName: 'notas.txt',
      id: 'con-archivo',
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'con-archivo',
            title: 'Con archivo',
            source: Source(
              id: 'src-con-archivo',
              kind: SourceKind.document,
              capturedAt: now,
              originalFilePath: file,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-con-archivo',
                itemId: 'con-archivo',
                kind: RenditionKind.plainText,
                content: text,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  test(
    'con la copia del original pedida, la guarda y la tría (decisión H)',
    () async {
      await saveWithFile();

      final outcome = await triage()(
        'con-archivo',
        const {},
        original: const OriginalEdit(ProcessedChange.add),
      );

      expect(outcome.isRight(), isTrue);
      expect(await stateOf('con-archivo'), ItemState.triaged);
      expect(
        await harness.database
            .select(harness.database.processedOriginals)
            .get(),
        hasLength(1),
      );
    },
  );

  test('volver a triar también lleva la copia del original', () async {
    await saveWithFile();
    await triage()('con-archivo', {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    });

    final outcome = await triage().retriage(
      'con-archivo',
      const {},
      original: const OriginalEdit(ProcessedChange.add),
    );

    expect(outcome.isRight(), isTrue);
    expect(
      await harness.database.select(harness.database.processedOriginals).get(),
      hasLength(1),
    );
  });

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

  group('«Volver a triar» (paso 4)', () {
    final text = {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    };
    final note = {
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Una idea mía')]),
      ),
    };

    Future<void> setState(ItemState state) =>
        (harness.database.update(harness.database.knowledgeEntries)
              ..where((e) => e.id.equals('fuente')))
            .write(KnowledgeEntriesCompanion(state: Value(state)));

    test('una fuente ya triada cambia solo su documento: su estado no se '
        'toca, y deshacer deja el documento como estaba', () async {
      await triage()('fuente', text);
      final before = await stateOf('fuente');

      final outcome = (await triage().retriage(
        'fuente',
        note,
      )).getOrElse((failure) => throw StateError('$failure'));

      expect(outcome.triagedFrom, isNull);
      expect(outcome.sourceItemId, 'fuente');
      expect(await stateOf('fuente'), before);
      expect(await sections(), {ProcessedSection.text, ProcessedSection.notes});

      expect((await triage().undoRetriage(outcome)).isRight(), isTrue);
      expect(await sections(), {ProcessedSection.text});
      expect(await stateOf('fuente'), ItemState.triaged);
    });

    test(
      'una destilada cuenta como triada: tampoco cambia de estado',
      () async {
        await setState(ItemState.distilled);

        final outcome = await triage().retriage('fuente', text);

        expect(outcome.getRight().toNullable()!.triagedFrom, isNull);
        expect(await stateOf('fuente'), ItemState.distilled);
        expect(await documents(), 1);
      },
    );

    test('una que espera en la Bandeja queda triada, y deshacer la devuelve '
        'sin su documento', () async {
      final outcome = (await triage().retriage(
        'fuente',
        text,
      )).getOrElse((failure) => throw StateError('$failure'));

      expect(outcome.triagedFrom, InboxStatus.pending);
      expect(await stateOf('fuente'), ItemState.triaged);
      expect(await documents(), 1);

      expect((await triage().undoRetriage(outcome)).isRight(), isTrue);
      expect(await documents(), 0);
      expect(await stateOf('fuente'), ItemState.processed);
    });

    test('una descartada queda triada, y deshacer la vuelve a descartar —no '
        'a la Bandeja—', () async {
      await setState(ItemState.discarded);

      final outcome = (await triage().retriage(
        'fuente',
        text,
      )).getOrElse((failure) => throw StateError('$failure'));

      expect(outcome.triagedFrom, InboxStatus.discarded);
      expect(await stateOf('fuente'), ItemState.triaged);

      expect((await triage().undoRetriage(outcome)).isRight(), isTrue);
      expect(await documents(), 0);
      expect(await stateOf('fuente'), ItemState.discarded);
    });

    test(
      'si no hay nada que guardar, una que espera sigue esperando',
      () async {
        final outcome = await triage().retriage('fuente', const {});

        expect(outcome.isLeft(), isTrue);
        expect(await stateOf('fuente'), ItemState.processed);
        expect(await documents(), 0);
      },
    );

    test('una fuente en la papelera no se vuelve a triar, y no se escribe '
        'nada', () async {
      await trashItemRows(harness.database, 'fuente');

      final outcome = await triage().retriage('fuente', text);

      expect(outcome.getLeft().toNullable(), isA<ValidationFailure>());
      expect(await documents(), 0);
    });

    test('si el documento no se puede deshacer, la fuente no se mueve: queda '
        'triada con su documento, sin contradecirse', () async {
      final outcome = (await triage().retriage(
        'fuente',
        text,
      )).getOrElse((failure) => throw StateError('$failure'));
      final process = _FailingProcess();
      when(() => process.undo(outcome.processed.undo)).thenAnswer(
        (_) async => left(const Failure.cache(message: 'Cambió mientras.')),
      );
      final inbox = _FailingInbox();
      final useCase = TriageIntoProcessed(inbox: inbox, process: process);

      final undone = await useCase.undoRetriage(outcome);

      expect(
        undone.getLeft().toNullable(),
        const Failure.cache(message: 'Cambió mientras.'),
      );
      verifyNever(() => inbox.returnToInbox(any()));
      expect(await stateOf('fuente'), ItemState.triaged);
    });
  });

  group('lo triado va a la IA (F41, paso 6)', () {
    final text = {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    };
    final note = {
      ProcessedSection.notes: SectionEdit.add(
        const SectionInput.drafts([ProcessedDraft.written('Una idea mía')]),
      ),
    };

    String documentOf(Either<Failure, ProcessOutcome> outcome) =>
        outcome.getOrElse((failure) => throw StateError('$failure')).documentId;

    test('triar en la Bandeja le pasa el documento a la IA', () async {
      final outcome = await triage()('fuente', text);

      expect(harness.triagedForOrganizing, [documentOf(outcome)]);
    });

    test('pasar sin modificar, también', () async {
      final outcome = await triage().passUnchanged('fuente');

      expect(harness.triagedForOrganizing, [documentOf(outcome)]);
    });

    test(
      'volver a triar una ya triada, también: es una pasada nueva',
      () async {
        final first = documentOf(await triage()('fuente', text));

        final again = await triage().retriage('fuente', note);

        expect(again.isRight(), isTrue);
        expect(harness.triagedForOrganizing, [first, first]);
      },
    );

    test(
      'volver a triar una que esperaba la tría y la pasa una sola vez',
      () async {
        final outcome = (await triage().retriage(
          'fuente',
          text,
        )).getOrElse((failure) => throw StateError('$failure'));

        expect(harness.triagedForOrganizing, [outcome.processed.documentId]);
      },
    );

    test('«Sin cambios» no la pasa: no hay nada nuevo que organizar', () async {
      await triage()('fuente', text);
      harness.triagedForOrganizing.clear();

      final again = (await triage().retriage(
        'fuente',
        text,
      )).getOrElse((failure) => throw StateError('$failure'));

      expect(again.processed.unchanged, isTrue);
      expect(harness.triagedForOrganizing, isEmpty);
    });

    test('si no hay nada que guardar, no la pasa', () async {
      await triage()('fuente', const {});
      await triage().retriage('fuente', const {});

      expect(harness.triagedForOrganizing, isEmpty);
    });

    test('si el triado falla y se deshace, no la pasa', () async {
      final inbox = _FailingInbox();
      when(
        () => inbox.transitionState(
          itemId: any(named: 'itemId'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.cache(message: 'La base no contestó.')),
      );
      final organized = <String>[];
      final useCase = TriageIntoProcessed(
        inbox: inbox,
        process: harness.container.read(processSourceUseCaseProvider),
        organize: organized.add,
      );

      expect((await useCase.passUnchanged('fuente')).isLeft(), isTrue);
      expect((await useCase('fuente', text)).isLeft(), isTrue);

      expect(organized, isEmpty);
      expect(await documents(), 0);
    });
  });
}
