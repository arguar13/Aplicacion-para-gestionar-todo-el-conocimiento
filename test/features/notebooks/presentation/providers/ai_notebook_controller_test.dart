import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/ai_notebook_controller.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

class _FakeFinder implements NotebookCandidateFinder {
  _FakeFinder(this.candidates);

  final List<NotebookCandidate> candidates;
  final topics = <String>[];

  @override
  Future<NotebookSearchResult> find(
    String topic, {
    int limit = kNotebookCandidateLimit,
  }) async {
    topics.add(topic);
    return NotebookSearchResult(
      candidates: candidates,
      senseSearch: SenseSearch.used,
    );
  }
}

/// Contesta cada tanda con lo que diga `answer`: un valor, o un futuro que la
/// prueba completa cuando quiere.
class _FakeJudge implements NotebookCandidateJudge {
  _FakeJudge(this.answer);

  final FutureOr<Set<int>?> Function(List<String> titles) answer;
  final batches = <List<String>>[];

  @override
  Future<Set<int>?> judgeNotebookCandidates({
    required String topic,
    required List<({String title, String excerpt})> candidates,
  }) async {
    final titles = [for (final c in candidates) c.title];
    batches.add(titles);
    return answer(titles);
  }
}

/// El estado de ahora, sin `debugState` (deprecado): el oyente lo recibe en
/// el acto.
AiNotebookState? _stateOf(AiNotebookController notifier) {
  AiNotebookState? current;
  notifier.addListener((state) => current = state)();
  return current;
}

NotebookCandidate _candidate(int i, {bool text = true}) => NotebookCandidate(
  itemId: 'e$i',
  title: 'Elemento $i',
  excerpt: 'Fragmento $i',
  kind: SourceKind.webPage,
  matchedText: text,
);

void main() {
  late AppDatabase db;
  late NotebookRepositoryImpl notebooks;
  late MockTelemetryService telemetry;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => DateTime(2026, 10, 4),
    );
    telemetry = MockTelemetryService();
  });

  tearDown(() => db.close());

  AiNotebookController controller({
    required List<NotebookCandidate> candidates,
    _FakeJudge? judge,
    bool languageModel = true,
  }) => AiNotebookController(
    finder: _FakeFinder(candidates),
    judge: judge ?? _FakeJudge((_) => const {}),
    languageModelReady: () async => languageModel,
    notebooks: notebooks,
    telemetry: telemetry,
  );

  test('sin el modelo de lenguaje, marca lo que encontró la búsqueda y nadie '
      'revisa', () async {
    final judge = _FakeJudge((_) => const {});
    final notifier = controller(
      candidates: [_candidate(0), _candidate(1, text: false)],
      judge: judge,
      languageModel: false,
    );

    await notifier.search('  Roma ');

    final state = _stateOf(notifier)!;
    expect(state.topic, 'Roma');
    expect(state.toReview, 0);
    expect(state.reviewing, isFalse);
    expect(state.picks.map((p) => p.checked), [true, false]);
    expect(judge.batches, isEmpty);
  });

  test('la IA revisa por tandas los primeros, y lo que dice corrige las '
      'marcas', () async {
    final candidates = [for (var i = 0; i < 30; i++) _candidate(i)];
    // De cada tanda, solo el primero va.
    final judge = _FakeJudge((_) => const {0});
    final notifier = controller(candidates: candidates, judge: judge);

    await notifier.search('Roma');

    final state = _stateOf(notifier)!;
    expect(judge.batches.map((b) => b.length), [8, 8, 8]);
    expect(state.reviewed, kNotebookJudgeMax);
    expect(state.reviewing, isFalse);
    for (var i = 0; i < kNotebookJudgeMax; i++) {
      expect(state.picks[i].fits, i % 8 == 0, reason: 'elemento $i');
      expect(state.picks[i].checked, i % 8 == 0, reason: 'elemento $i');
    }
    // Lo que no revisó queda como lo marcó la búsqueda.
    expect(state.picks.skip(kNotebookJudgeMax).every((p) => p.checked), isTrue);
    expect(
      state.picks.skip(kNotebookJudgeMax).every((p) => p.fits == null),
      isTrue,
    );
  });

  test('lo que la persona tocó, la IA ya no lo cambia', () async {
    final gate = Completer<Set<int>?>();
    final judge = _FakeJudge((_) => gate.future);
    final notifier = controller(
      candidates: [_candidate(0), _candidate(1)],
      judge: judge,
    );

    final searching = notifier.search('Roma');
    await pumpEventQueue();
    expect(_stateOf(notifier)!.reviewing, isTrue);
    notifier.toggle('e1');
    expect(_stateOf(notifier)!.picks[1].checked, isFalse);

    // La IA dice que van los dos: el que la persona destildó sigue afuera.
    gate.complete({0, 1});
    await searching;

    final picks = _stateOf(notifier)!.picks;
    expect(picks[0].checked, isTrue);
    expect(picks[1].fits, isTrue);
    expect(picks[1].checked, isFalse);
  });

  test('si la IA no se pudo leer, la tanda queda como estaba', () async {
    final notifier = controller(
      candidates: [_candidate(0), _candidate(1, text: false)],
      judge: _FakeJudge((_) => null),
    );

    await notifier.search('Roma');

    final state = _stateOf(notifier)!;
    expect(state.picks.map((p) => p.checked), [true, false]);
    expect(state.picks.every((p) => p.fits == null), isTrue);
    expect(state.reviewing, isFalse);
  });

  test('si la IA falla, se registra, lo dice y deja lo marcado por la '
      'búsqueda', () async {
    final notifier = controller(
      candidates: [_candidate(0)],
      judge: _FakeJudge((_) => throw StateError('el modelo falló')),
    );

    await notifier.search('Roma');

    expect(_stateOf(notifier)!.reviewFailed, isTrue);
    expect(_stateOf(notifier)!.picks.single.checked, isTrue);
    verify(
      () =>
          telemetry.recordError(any<Object>(), any(), hint: any(named: 'hint')),
    ).called(1);
  });

  test('crear arma un cuaderno manual con los marcados, de una vez, y lo que '
      'faltaba revisar ya no cambia nada', () async {
    await insertItemRows(db, id: 'e0', title: 'Elemento 0');
    await insertItemRows(db, id: 'e1', title: 'Elemento 1');
    await insertItemRows(db, id: 'e2', title: 'Elemento 2');
    final gate = Completer<Set<int>?>();
    final notifier = controller(
      candidates: [_candidate(0), _candidate(1), _candidate(2, text: false)],
      judge: _FakeJudge((_) => gate.future),
    );

    final searching = notifier.search('Roma');
    await pumpEventQueue();
    final notebook = await notifier.create('Mi tesis sobre Roma');
    gate.complete(const {});
    await searching;

    expect(notebook.name, 'Mi tesis sobre Roma');
    expect(notebook.mode, NotebookMode.manual);
    expect((await notebooks.resolveQuery(notebook.id)).ids, {'e0', 'e1'});
    expect(_stateOf(notifier)!.picks.every((p) => p.fits == null), isTrue);
  });

  test(
    'volver a escribir deja sin efecto lo que se estaba revisando',
    () async {
      final gate = Completer<Set<int>?>();
      final notifier = controller(
        candidates: [_candidate(0)],
        judge: _FakeJudge((_) => gate.future),
      );

      final searching = notifier.search('Roma');
      await pumpEventQueue();
      notifier.restart();
      gate.complete(const {});
      await searching;

      expect(_stateOf(notifier), isNull);
    },
  );
}
