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
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/domain/usecases/fill_study_keywords.dart';

import '../../../../support/item_rows.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Completar las palabras clave de lo ya analizado, sin IA, contra la base
/// real: el libro que el dueño analizó cuando el modelo todavía salteaba
/// oraciones.
void main() {
  late AppDatabase db;
  late StudyRepositoryImpl repository;
  final now = DateTime(2026, 10, 27, 10);

  const content = '''
The Project Gutenberg eBook of Don Quijote

This eBook is for the use of anyone anywhere in the United States and most other parts of the world at no cost and with almost no restrictions whatsoever. You may copy it, give it away or re-use it under the terms of the Project Gutenberg License included with this eBook or online at www.gutenberg.org. If you are not located in the United States, you will have to check the laws of the country where you are located before using this eBook.

## ÍNDICE

1. Que trata de la condición y ejercicio del famoso hidalgo D. Quijote de la Mancha
2. Que trata de la primera salida que de su tierra hizo el ingenioso Don Quijote
3. Donde se cuenta la graciosa manera que tuvo don Quijote en armarse caballero
4. Del buen suceso que el valeroso don Quijote tuvo en la espantable aventura
''';
  final sentences = splitStudySentences(content, markdown: true);

  StudyWord word(String text, {int from = 0}) {
    final start = content.indexOf(text, from);
    return StudyWord(start, start + text.length, text.toLowerCase());
  }

  /// Lo que quedó guardado por un análisis de antes: la parte entera, con los
  /// resúmenes y solo las palabras clave que el modelo no salteó.
  Future<void> analyzedBefore({
    List<StudyWord> keywords = const [],
    int? last,
    bool completes = true,
  }) async {
    final saved = await repository.savePart(
      renditionId: 'texto',
      content: content,
      partStart: sentences.first.start,
      partEnd: sentences[last ?? sentences.length - 1].end,
      marks: StudyPartMarks(
        summary: [sentences[1], sentences[5]],
        synthesis: [sentences[1]],
        keywords: keywords,
      ),
      completes: completes,
    );
    expect(saved.isRight(), isTrue);
  }

  /// Cuántas palabras clave tiene cada oración.
  Future<List<int>> perSentence() async {
    final keywords = (await repository.read('texto')).of(StudyMarkKind.keyword);
    return [
      for (final s in sentences)
        keywords.where((k) => k.start >= s.start && k.end <= s.end).length,
    ];
  }

  FillStudyKeywords fill({StudyFillRunner? runner}) =>
      FillStudyKeywords(repository: repository, runner: runner);

  Future<int> run([FillStudyKeywords? useCase]) => (useCase ?? fill())(
    renditionId: 'texto',
    content: content,
    markdown: true,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = StudyRepositoryImpl(
      database: db,
      telemetry: _SilentTelemetry(),
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

  test('el libro de la captura: las cuatro palabras de la primera oración '
      'quedan, y todas las demás reciben las suyas', () async {
    expect(sentences.length, 9);
    await analyzedBefore(
      keywords: [
        word('eBook', from: content.indexOf('This eBook')),
        word('United'),
        word('States'),
        word('restrictions'),
      ],
    );
    expect(
      (await perSentence()).where((n) => n == 0).length,
      8,
      reason: 'como en el teléfono: casi ninguna tenía',
    );

    final added = await run();

    final counts = await perSentence();
    expect(counts.every((n) => n >= 1 && n <= kMaxKeywordsPerSentence), isTrue);
    expect(counts[1], 4, reason: 'la que ya tenía sus cuatro no se toca');
    expect(added, counts.fold<int>(0, (a, b) => a + b) - 4);
    // Lo de antes (resumen y síntesis) sigue donde estaba.
    final study = await repository.read('texto');
    expect(study.of(StudyMarkKind.summary), hasLength(2));
    expect(study.of(StudyMarkKind.synthesis), hasLength(1));
    expect(study.complete, isTrue);
  });

  test('es idempotente: sobre un texto completo no agrega nada', () async {
    await analyzedBefore();
    await run();
    final first = await perSentence();

    expect(await run(), 0);

    expect(await perSentence(), first);
  });

  test('lo agregado es de la IA y lo elegido a mano sigue siendo de la '
      'persona, y esa oración no recibe más', () async {
    await analyzedBefore();
    final mine = word('Quijote', from: content.indexOf('2. Que trata'));
    final saved = await repository.addUserMark(
      renditionId: 'texto',
      content: content,
      kind: StudyMarkKind.keyword,
      start: mine.start,
      end: mine.end,
    );
    expect(saved.isRight(), isTrue);

    await run();

    final keywords = (await repository.read('texto')).of(StudyMarkKind.keyword);
    final inSecond = keywords.where(
      (k) => k.start >= sentences[6].start && k.end <= sentences[6].end,
    );
    expect(inSecond.single.origin, ContentOrigin.user);
    expect(keywords.where((k) => k.origin == ContentOrigin.ai), isNotEmpty);
    expect((await perSentence()).every((n) => n >= 1), isTrue);
  });

  test('un análisis a medias completa solo hasta donde llegó: lo que falta '
      'lo trae el propio análisis', () async {
    await analyzedBefore(last: 3, completes: false);

    await run();

    final counts = await perSentence();
    expect(counts.take(4).every((n) => n >= 1), isTrue, reason: '$counts');
    expect(counts.skip(4), everyElement(0), reason: '$counts');
  });

  test('un texto sin analizar no se toca, y ni siquiera se mira', () async {
    var looked = false;
    final added = await run(
      fill(
        runner: (job) async {
          looked = true;
          return const [];
        },
      ),
    );

    expect(added, 0);
    expect(looked, isFalse);
    expect((await repository.read('texto')).marks, isEmpty);
  });

  test('si no falta nada no guarda nada', () async {
    await analyzedBefore();
    await run();
    final marks = (await repository.read('texto')).marks;

    await run();

    expect((await repository.read('texto')).marks, marks);
  });

  test(
    'le pasa al que corre lo que hay y hasta dónde llega lo analizado',
    () async {
      await analyzedBefore(
        keywords: [word('United')],
        last: 3,
        completes: false,
      );
      StudyFillJob? seen;

      await run(
        fill(
          runner: (job) async {
            seen = job;
            return const [];
          },
        ),
      );

      expect(seen!.markdown, isTrue);
      expect(seen!.until, sentences[3].end);
      expect(seen!.keywordRanges, [(word('United').start, word('United').end)]);
    },
  );

  test('una falla al guardar sale como error, no en silencio', () async {
    await analyzedBefore();

    await expectLater(
      run(
        fill(
          runner: (job) async => [const StudyWord(0, content.length + 9, 'x')],
        ),
      ),
      throwsA(isA<StudySaveException>()),
    );
    expect((await perSentence()).every((n) => n == 0), isTrue);
  });
}
