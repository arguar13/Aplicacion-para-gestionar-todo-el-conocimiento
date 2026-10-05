import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_suggestions_controller.dart';

import '../../../../support/fake_id_generator.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

class _FakeReader implements NotebookTopicReader {
  final sampled = <String>[];

  @override
  Stream<List<NotebookTopic>> watchTopics() => const Stream.empty();

  @override
  Future<List<String>> sampleTitles(
    NotebookSuggestion suggestion, {
    int limit = kNotebookSuggestionSampleTitles,
  }) async {
    sampled.add(suggestion.key);
    return ['Uno de ${suggestion.topic.name}'];
  }
}

class _FakeNamer implements NotebookNamer {
  _FakeNamer(this.answer);

  final Future<Map<int, NotebookNaming>> Function(
    List<NotebookNamingInput> inputs,
  )
  answer;
  final calls = <List<NotebookNamingInput>>[];

  @override
  Future<Map<int, NotebookNaming>> nameNotebooks(
    List<NotebookNamingInput> inputs,
  ) {
    calls.add(inputs);
    return answer(inputs);
  }
}

NotebookSuggestion _suggestion(
  String id,
  String name, {
  NotebookTopicKind kind = NotebookTopicKind.space,
}) => NotebookSuggestion(
  topic: NotebookTopic(kind: kind, id: id, name: name, itemCount: 5),
);

void main() {
  late AppDatabase db;
  late NotebookRepositoryImpl notebooks;
  late MockTelemetryService telemetry;
  late _FakeReader reader;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(),
      clock: () => DateTime(2026, 10, 8),
    );
    telemetry = MockTelemetryService();
    reader = _FakeReader();
  });

  tearDown(() => db.close());

  NotebookSuggestionsController controller({
    required List<NotebookSuggestion> suggestions,
    _FakeNamer? namer,
    bool languageModel = true,
  }) => NotebookSuggestionsController(
    suggestions: suggestions,
    reader: reader,
    namer: namer ?? _FakeNamer((_) async => {}),
    languageModelReady: () async => languageModel,
    notebooks: notebooks,
    telemetry: telemetry,
  );

  test('nacen sin marcar, con el nombre del tema: la persona elige', () {
    final notifier = controller(
      suggestions: [_suggestion('s1', 'Roma'), _suggestion('s2', 'Grecia')],
    );

    expect(notifier.state.drafts.map((d) => d.name), ['Roma', 'Grecia']);
    expect(notifier.state.checkedCount, 0);
  });

  test('crear hace un cuaderno por consulta de cada marcado, y de ningún '
      'otro', () async {
    final notifier =
        controller(
            suggestions: [
              _suggestion('s1', 'Roma'),
              _suggestion('t1', 'Filosofía', kind: NotebookTopicKind.tag),
              _suggestion('s2', 'Grecia'),
            ],
          )
          ..toggle('space:s1')
          ..toggle('tag:t1');

    final created = await notifier.create();

    expect(created.map((n) => n.name), ['Roma', 'Filosofía']);
    expect(created.every((n) => n.mode == NotebookMode.query), isTrue);
    expect(created[0].query, const LibraryQuery(spaceId: 's1'));
    expect(created[1].query, const LibraryQuery(tagIds: {'t1'}));
    expect(await notebooks.watchAll().first, hasLength(2));
  });

  test('marcar todos, y desmarcar todos si ya estaban', () {
    final notifier = controller(
      suggestions: [_suggestion('s1', 'Roma'), _suggestion('s2', 'Grecia')],
    )..toggleAll();
    expect(notifier.state.checkedCount, 2);

    notifier.toggleAll();
    expect(notifier.state.checkedCount, 0);
  });

  test('la IA nombra de a cinco, con títulos de ejemplo, y su nombre y su '
      'línea quedan en el cuaderno que se crea', () async {
    final suggestions = [
      for (var i = 0; i < 7; i++) _suggestion('s$i', 'Tema $i'),
    ];
    final namer = _FakeNamer(
      (inputs) async => {
        0: (name: 'Nombre de ${inputs.first.topic}', description: 'Una línea'),
      },
    );
    final notifier = controller(suggestions: suggestions, namer: namer);

    await notifier.nameWithAi();

    expect(namer.calls.map((c) => c.length), [5, 2]);
    expect(namer.calls.first.first.titles, ['Uno de Tema 0']);
    expect(namer.calls.first.first.itemCount, 5);
    final drafts = notifier.state.drafts;
    expect(drafts[0].name, 'Nombre de Tema 0');
    expect(drafts[0].description, 'Una línea');
    expect(drafts[1].name, 'Tema 1');
    expect(drafts[5].name, 'Nombre de Tema 5');
    expect(notifier.state.naming, isFalse);

    notifier.toggle('space:s0');
    final created = await notifier.create();
    expect(created.single.name, 'Nombre de Tema 0');
  });

  test('sin el modelo de lenguaje, nadie nombra', () async {
    final namer = _FakeNamer((_) async => {});
    final notifier = controller(
      suggestions: [_suggestion('s1', 'Roma')],
      namer: namer,
      languageModel: false,
    );

    await notifier.nameWithAi();

    expect(namer.calls, isEmpty);
    expect(notifier.state.naming, isFalse);
  });

  test('si la IA falla, se registra, lo dice y quedan los nombres de los '
      'temas', () async {
    final notifier = controller(
      suggestions: [_suggestion('s1', 'Roma')],
      namer: _FakeNamer((_) async => throw StateError('el modelo falló')),
    );

    await notifier.nameWithAi();

    expect(notifier.state.namingFailed, isTrue);
    expect(notifier.state.naming, isFalse);
    expect(notifier.state.drafts.single.name, 'Roma');
    verify(
      () =>
          telemetry.recordError(any<Object>(), any(), hint: any(named: 'hint')),
    ).called(1);
  });

  group('«Ahora no»', () {
    test('queda recordado entre aperturas', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = NotebookSuggestionDismissals(prefs: prefs);
      expect(first.state, isEmpty);
      await first.dismiss(['space:s1', 'tag:t1']);
      await first.dismiss(['space:s2']);

      final reopened = NotebookSuggestionDismissals(prefs: prefs);
      expect(reopened.state, {'space:s1', 'tag:t1', 'space:s2'});
    });
  });
}
