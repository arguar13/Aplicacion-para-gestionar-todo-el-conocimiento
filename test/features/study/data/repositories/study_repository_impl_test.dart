import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

import '../../../../support/item_rows.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

class _CountingIds implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'm${_n++}';
}

/// Dónde se guarda lo estudiado de un texto (F36), contra SQLite real.
void main() {
  late AppDatabase db;
  late StudyRepositoryImpl repository;
  final now = DateTime(2026, 10, 22, 10);

  const content =
      'La revolución industrial empezó en Inglaterra. '
      'Las fábricas usaban vapor. '
      'El trabajo infantil era común. '
      'Hoy se estudia.';
  final sentences = splitStudySentences(content, markdown: false);

  StudyWord word(String text) {
    final start = content.indexOf(text);
    return StudyWord(start, start + text.length, text.toLowerCase());
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = StudyRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
      ids: _CountingIds(),
      clock: () => now,
    );
    await insertItemRows(
      db,
      id: 'libro',
      title: 'Libro',
      kind: SourceKind.document,
    );
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto',
            itemId: 'libro',
            kind: RenditionKind.plainText,
            content: const Value(content),
            isPrimary: true,
            createdAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> save({
    required int from,
    required int to,
    List<int> summary = const [],
    List<int> synthesis = const [],
    List<StudyWord> keywords = const [],
    bool completes = false,
  }) async {
    final result = await repository.savePart(
      renditionId: 'texto',
      content: content,
      partStart: sentences[from].start,
      partEnd: sentences[to].end,
      marks: StudyPartMarks(
        summary: [for (final i in summary) sentences[i]],
        synthesis: [for (final i in synthesis) sentences[i]],
        keywords: keywords,
      ),
      completes: completes,
    );
    expect(result.isRight(), isTrue);
  }

  List<String> textsOf(DocumentStudy study, StudyMarkKind kind) => [
    for (final mark in study.of(kind)) content.substring(mark.start, mark.end),
  ];

  test('sin analizar: nada marcado, nada empezado', () async {
    final study = await repository.read('texto');
    expect(study, DocumentStudy.notStarted);
    expect(study.started, isFalse);
  });

  test(
    'una parte guarda lo marcado, con su fragmento, y hasta dónde llegó',
    () async {
      await save(
        from: 0,
        to: 1,
        summary: [0, 1],
        synthesis: [0],
        keywords: [word('Inglaterra'), word('vapor')],
      );

      final study = await repository.read('texto');
      expect(textsOf(study, StudyMarkKind.summary), [
        'La revolución industrial empezó en Inglaterra.',
        'Las fábricas usaban vapor.',
      ]);
      expect(textsOf(study, StudyMarkKind.synthesis), [
        'La revolución industrial empezó en Inglaterra.',
      ]);
      expect(textsOf(study, StudyMarkKind.keyword), ['Inglaterra', 'vapor']);
      expect(study.marks.map((m) => m.origin), everyElement(ContentOrigin.ai));
      expect(study.analyzedUntil, sentences[1].end);
      expect(study.started, isTrue);
      expect(study.complete, isFalse);

      final rows = await db.select(db.studyMarks).get();
      for (final row in rows) {
        expect(row.excerpt, content.substring(row.startOffset, row.endOffset));
      }
    },
  );

  test('la última parte lo deja terminado', () async {
    await save(from: 0, to: 1, summary: [0]);
    await save(from: 2, to: 3, summary: [2], completes: true);

    final study = await repository.read('texto');
    expect(study.complete, isTrue);
    expect(study.analyzedUntil, content.length);
    expect(textsOf(study, StudyMarkKind.summary), [
      'La revolución industrial empezó en Inglaterra.',
      'El trabajo infantil era común.',
    ]);
  });

  test('rehacer una parte reemplaza lo de la IA en esa parte, no en las '
      'otras, y no duplica', () async {
    await save(from: 0, to: 1, summary: [0, 1], keywords: [word('vapor')]);
    await save(from: 2, to: 3, summary: [2]);

    // Un intento que se cortó y se rehace, o volver a analizar esa parte.
    await save(from: 0, to: 1, summary: [1]);

    final study = await repository.read('texto');
    expect(textsOf(study, StudyMarkKind.summary), [
      'Las fábricas usaban vapor.',
      'El trabajo infantil era común.',
    ]);
    expect(study.of(StudyMarkKind.keyword), isEmpty);
  });

  test('rehacer una parte no se lleva las palabras que eligió la persona, '
      'ni las duplica', () async {
    await save(from: 0, to: 1, summary: [0]);
    await repository.addKeyword(
      renditionId: 'texto',
      content: content,
      word: word('Inglaterra'),
    );

    await save(from: 0, to: 1, summary: [0], keywords: [word('Inglaterra')]);

    final keywords = (await repository.read('texto')).of(StudyMarkKind.keyword);
    expect(keywords, hasLength(1));
    expect(keywords.single.origin, ContentOrigin.user);
  });

  test('una parte fuera del texto no se guarda', () async {
    final result = await repository.savePart(
      renditionId: 'texto',
      content: content,
      partStart: 10,
      partEnd: content.length + 1,
      marks: const StudyPartMarks(summary: [], synthesis: [], keywords: []),
      completes: false,
    );
    expect(result.isLeft(), isTrue);
    expect(await db.select(db.studyAnalyses).get(), isEmpty);
  });

  group('las palabras clave a mano', () {
    test(
      'agregar una la marca como de la persona; dos veces, una sola',
      () async {
        for (var i = 0; i < 2; i++) {
          await repository.addKeyword(
            renditionId: 'texto',
            content: content,
            word: word('fábricas'),
          );
        }
        final keywords = (await repository.read(
          'texto',
        )).of(StudyMarkKind.keyword);
        expect(keywords, hasLength(1));
        expect(keywords.single.origin, ContentOrigin.user);
        expect(
          content.substring(keywords.single.start, keywords.single.end),
          'fábricas',
        );
      },
    );

    test('una palabra fuera del texto no se agrega', () async {
      final result = await repository.addKeyword(
        renditionId: 'texto',
        content: content,
        word: const StudyWord(content.length - 2, content.length + 3, 'x'),
      );
      expect(result.isLeft(), isTrue);
    });

    test('sacar una saca solo esa palabra, nunca una oración', () async {
      await save(
        from: 0,
        to: 1,
        summary: [0],
        keywords: [word('Inglaterra'), word('revolución')],
      );
      final study = await repository.read('texto');
      final inglaterra = study
          .of(StudyMarkKind.keyword)
          .firstWhere((m) => content.substring(m.start, m.end) == 'Inglaterra');

      await repository.removeKeyword(inglaterra.id);
      await repository.removeKeyword(study.of(StudyMarkKind.summary).single.id);

      final after = await repository.read('texto');
      expect(textsOf(after, StudyMarkKind.keyword), ['revolución']);
      expect(after.of(StudyMarkKind.summary), hasLength(1));
    });
  });

  test('borrar todo deja el texto como sin analizar', () async {
    await save(from: 0, to: 3, summary: [0], completes: true);
    await repository.addKeyword(
      renditionId: 'texto',
      content: content,
      word: word('vapor'),
    );

    await repository.clear('texto');

    expect(await repository.read('texto'), DocumentStudy.notStarted);
  });

  test('cada cambio se ve en lo que se escucha', () async {
    final seen = <int>[];
    final subscription = repository
        .watch('texto')
        .listen((study) => seen.add(study.marks.length));
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await save(from: 0, to: 1, summary: [0, 1]);
    await pumpEventQueue();

    expect(seen.first, 0);
    expect(seen.last, 2);
  });
}
