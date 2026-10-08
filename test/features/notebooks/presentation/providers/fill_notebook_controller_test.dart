import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/fill_notebook_controller.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Qué elementos «pueden tener tarjetas» y cuáles ya tienen, a gusto de la
/// prueba.
class _FakeCoverage implements FlashcardCoverageReader {
  _FakeCoverage({this.eligible = const [], this.withCards = const {}});

  final List<String> eligible;
  final Set<String> withCards;

  /// Sobre qué elementos se preguntó, en orden.
  final asked = <Iterable<String>?>[];

  @override
  Future<Either<Failure, FlashcardCoverage>> coverageOf(
    Iterable<String>? itemIds,
  ) async {
    asked.add(itemIds);
    final inScope = itemIds?.toSet();
    return right(
      FlashcardCoverage(
        eligible: [
          for (final id in eligible)
            if (inScope == null || inScope.contains(id)) id,
        ],
        withCards: withCards,
      ),
    );
  }

  @override
  Stream<int> watchWithoutCardsCount() => const Stream.empty();

  @override
  Stream<bool> watchHasCards() => const Stream.empty();
}

KnowledgeItem _noteLike(String id) => KnowledgeItem(
  id: id,
  title: 'Guía',
  source: Source(
    id: 'src-$id',
    kind: SourceKind.manualNote,
    capturedAt: DateTime(2026, 10, 8),
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 10, 8),
  updatedAt: DateTime(2026, 10, 8),
);

void main() {
  late AppDatabase db;
  late NotebookRepositoryImpl notebooks;
  late LibraryRepositoryImpl library;
  late String notebookId;

  /// Lo que pasó, en orden: «cards» y «guide».
  late List<String> events;
  late List<List<String>> requested;
  late List<GenerateDerivedNoteParams> generated;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => DateTime(2026, 10, 8),
    );
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    for (final id in ['a', 'b', 'c']) {
      await insertItemRows(db, id: id, title: 'Elemento $id');
    }
    notebookId = (await notebooks.create(
      name: 'Roma',
      mode: NotebookMode.manual,
    )).id;
    await notebooks.addItems(notebookId: notebookId, itemIds: ['a', 'b', 'c']);
    events = [];
    requested = [];
    generated = [];
  });

  tearDown(() => db.close());

  FillNotebookController controller({
    _FakeCoverage? coverage,
    Future<Either<Failure, DerivedNoteResult>> Function(
      GenerateDerivedNoteParams params,
    )?
    generate,
  }) => FillNotebookController(
    notebookId: notebookId,
    notebooks: notebooks,
    library: library,
    coverage:
        coverage ?? _FakeCoverage(eligible: ['a', 'b', 'c'], withCards: {'b'}),
    makeFlashcards: (ids) {
      events.add('cards');
      requested.add(ids.toList());
    },
    generate:
        generate ??
        (params) async {
          events.add('guide');
          generated.add(params);
          params.onProgress?.call(0, 2);
          params.onProgress?.call(2, 2);
          return right(
            DerivedNoteResult(note: _noteLike('guia'), inNotebook: true),
          );
        },
  );

  Future<void> run(FillNotebookController notifier) =>
      notifier.start(guideTitle: 'Guía de estudio: Roma', model: 'gemma-3n');

  test('nace con la nota y las tarjetas elegidas, y se puede cambiar', () {
    final notifier = controller();

    expect(notifier.state.guide, isTrue);
    expect(notifier.state.cards, isTrue);
    expect(notifier.state.type, DerivedNoteType.studyGuide);
    expect(notifier.state.canStart, isTrue);

    notifier
      ..setGuide(value: false)
      ..setCards(value: false);
    expect(notifier.state.canStart, isFalse);
    notifier.setType(DerivedNoteType.timeline);
    expect(notifier.state.type, DerivedNoteType.timeline);
  });

  test('pide tarjetas solo de lo del cuaderno que no las tiene, ANTES de '
      'generar la nota, y la nota recibe el cuaderno y el progreso', () async {
    final coverage = _FakeCoverage(
      eligible: ['a', 'b', 'c', 'fuera'],
      withCards: {'b'},
    );
    final notifier = controller(coverage: coverage);
    final partsSeen = <(int, int)>[];
    notifier.addListener(
      (state) => partsSeen.add((state.partsRead, state.partsTotal)),
    );

    await run(notifier);

    expect(events, ['cards', 'guide']);
    expect(requested, [
      ['a', 'c'],
    ]);
    // Sobre los elementos del cuaderno, no sobre toda la biblioteca.
    expect(coverage.asked.single!.toSet(), {'a', 'b', 'c'});
    final params = generated.single;
    expect(params.notebookId, notebookId);
    expect(params.type, DerivedNoteType.studyGuide);
    expect(params.title, 'Guía de estudio: Roma');
    expect(params.model, 'gemma-3n');
    expect(partsSeen, contains((2, 2)));

    final state = notifier.state;
    expect(state.finished, isTrue);
    expect(state.running, isFalse);
    expect(state.cardsOutcome!.queued, 2);
    expect(state.cardsOutcome!.eligible, 3);
    expect(state.guideOutcome!.result!.inNotebook, isTrue);
    expect(state.guideOutcome!.failure, isNull);
  });

  test('con otro tipo de nota, genera ese', () async {
    final notifier = controller()..setType(DerivedNoteType.outline);

    await run(notifier);

    expect(generated.single.type, DerivedNoteType.outline);
  });

  test('solo la nota: no pide tarjetas', () async {
    final notifier = controller()..setCards(value: false);

    await run(notifier);

    expect(events, ['guide']);
    expect(notifier.state.cardsOutcome, isNull);
  });

  test('solo las tarjetas: no genera ninguna nota', () async {
    final notifier = controller()..setGuide(value: false);

    await run(notifier);

    expect(events, ['cards']);
    expect(notifier.state.guideOutcome, isNull);
    expect(notifier.state.finished, isTrue);
  });

  test('si todo ya tiene tarjetas, no pide ninguna y lo dice', () async {
    final notifier = controller(
      coverage: _FakeCoverage(
        eligible: ['a', 'b', 'c'],
        withCards: {'a', 'b', 'c'},
      ),
    )..setGuide(value: false);

    await run(notifier);

    expect(events, isEmpty);
    expect(notifier.state.cardsOutcome!.alreadyHadAll, isTrue);
  });

  test('si nada tiene texto, lo dice y no pide nada', () async {
    final notifier = controller(coverage: _FakeCoverage())
      ..setGuide(value: false);

    await run(notifier);

    expect(events, isEmpty);
    expect(notifier.state.cardsOutcome!.nothingToMake, isTrue);
  });

  test('si la nota falla, las tarjetas ya pedidas quedan y el fallo se '
      'cuenta', () async {
    final notifier = controller(
      generate: (params) async =>
          left(const Failure.validation(message: 'No hay fuentes que citar.')),
    );

    await run(notifier);

    expect(requested, hasLength(1));
    expect(notifier.state.guideOutcome!.failure, isA<ValidationFailure>());
    expect(notifier.state.guideOutcome!.result, isNull);
    expect(notifier.state.finished, isTrue);
  });

  test('una nota que quedó fuera del cuaderno, lo dice', () async {
    final notifier = controller(
      generate: (params) async =>
          right(DerivedNoteResult(note: _noteLike('guia'), inNotebook: false)),
    );

    await run(notifier);

    expect(notifier.state.guideOutcome!.result!.inNotebook, isFalse);
  });

  test('una vez hecho, no se repite', () async {
    final notifier = controller();
    await run(notifier);

    await run(notifier);

    expect(events, ['cards', 'guide']);
  });
}
