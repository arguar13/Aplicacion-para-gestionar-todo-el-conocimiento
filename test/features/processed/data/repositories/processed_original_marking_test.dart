import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_original_study_repository.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_study_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/study/data/repositories/keyed_study_repository.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';

import '../../../../support/fake_id_generator.dart';
import '../../processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un modelo de mentira: de cada parte, la primera oración al resumen, la
/// segunda a la síntesis y la primera palabra de cada una como clave.
class _FirstSentenceMarker implements StudyMarker {
  @override
  int get partCharBudget => 10000;

  @override
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  }) async => StudyPartOutcome(
    analyzed: part.length,
    marks: StudyPartMarks(
      summary: part.take(1).toList(),
      synthesis: part.skip(1).take(1).toList(),
      keywords: [
        for (final sentence in part)
          () {
            final space = content.indexOf(' ', sentence.start);
            final end = space < 0 || space > sentence.end
                ? sentence.end
                : space;
            return StudyWord(
              sentence.start,
              end,
              content.substring(sentence.start, end),
            );
          }(),
      ],
    ),
  );
}

/// Marcar en el original de un documento procesado (F43, paso 15, M5): lo que
/// se elige sobre la copia —con su clave `procesado-original:…`— se guarda en
/// el procesado, como lo estudiado de su texto propio, y se ve en los dos
/// lados; sacar, borrar una clase y rehacer lo de la IA, también.
void main() {
  const text =
      'Roma fundó colonias. Cartago perdió la guerra. '
      'Aníbal cruzó los Alpes. Escipión volvió a Roma.';
  late ProcessedHarness h;
  late KeyedStudyRepository study;
  final docId = processedDocumentIdFor('roma');
  final ownKey = processedStudyKeyFor(docId);
  final originalKey = processedOriginalStudyKeyFor(docId);
  const add = OriginalEdit(ProcessedChange.add);

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource(
      'roma',
      title: 'Roma',
      text: text,
      originalName: 'roma.txt',
      originalContent: text,
    );
    final processed = ProcessedStudyRepositoryImpl(
      database: h.db,
      telemetry: _SilentTelemetry(),
      ids: FakeIdGenerator(prefix: 'estudio'),
      clock: () => h.vault.now,
    );
    study = KeyedStudyRepository(
      fallback: StudyRepositoryImpl(
        database: h.db,
        telemetry: _SilentTelemetry(),
      ),
      byPrefix: {
        kProcessedOriginalStudyKeyPrefix: ProcessedOriginalStudyRepository(
          h.repository,
          processed,
        ),
        kProcessedStudyKeyPrefix: processed,
      },
    );
  });
  tearDown(() => h.close());

  Future<List<ProcessedPart>> parts(ProcessedSection section) async =>
      (await h.repository.partsOf(
        docId,
        sections: {section},
      )).getRight().toNullable()!;

  Future<ProcessedStudyText> own() async =>
      (await h.repository.studyTextOf(docId)).getRight().toNullable()!;

  Future<void> analyze() async {
    final text = await own();
    await AnalyzeForStudy(repository: study, marker: _FirstSentenceMarker())
        .call(
          renditionId: text.key,
          content: text.content,
          markdown: text.markdown,
        )
        .drain<void>();
  }

  Future<void> markOnOriginal(
    String passage, {
    StudyMarkKind kind = StudyMarkKind.summary,
  }) async {
    final start = text.indexOf(passage);
    final saved = await study.addUserMark(
      renditionId: originalKey,
      content: text,
      kind: kind,
      start: start,
      end: start + passage.length,
    );
    expect(saved.isRight(), isTrue, reason: '$saved');
  }

  List<(int, int)> spans(Iterable<StudyMark> marks) => [
    for (final mark in marks) (mark.start, mark.end),
  ];

  group('sin «Texto»: el texto propio es el de la copia', () {
    setUp(() async {
      final result = await h.process('roma', const {}, original: add);
      expect(result.isRight(), isTrue, reason: '$result');
    });

    test('elegir una oración en el original la guarda en el procesado, como '
        'de la persona, y se ve en los dos lados en el mismo lugar', () async {
      await markOnOriginal('Cartago perdió la guerra.');

      final summary = (await parts(ProcessedSection.summary)).single;
      expect(summary.origin, ProcessedPartOrigin.chosen);
      expect(summary.content, 'Cartago perdió la guerra.');
      expect(summary.anchor?.start, 21);
      final start = text.indexOf('Cartago');
      final onOriginal = (await study.read(
        originalKey,
      )).of(StudyMarkKind.summary);
      expect(spans(onOriginal), [(start, start + 25)]);
      expect(onOriginal.single.origin, ContentOrigin.user);
      expect(spans((await study.read(ownKey)).of(StudyMarkKind.summary)), [
        (start, start + 25),
      ]);
      // Nada cae en la fuente.
      expect(await h.db.select(h.db.studyMarks).get(), isEmpty);
    });

    test('una palabra clave elegida en el original es de su oración', () async {
      await markOnOriginal('guerra', kind: StudyMarkKind.keyword);

      final keywords = (await parts(ProcessedSection.keywords)).single;
      expect(keywords.content, 'Cartago perdió la guerra.');
      expect(keywords.keywords, ['guerra']);
      expect(keywords.spans.single.chosen, isTrue);
      final start = text.indexOf('guerra');
      expect(spans((await study.read(originalKey)).of(StudyMarkKind.keyword)), [
        (start, start + 6),
      ]);
    });

    test('las marcas del original llevan el id del procesado: sacarla desde '
        'el original va directo a su parte', () async {
      await markOnOriginal('Cartago perdió la guerra.');
      await markOnOriginal('Aníbal', kind: StudyMarkKind.keyword);
      final read = await study.read(originalKey);
      for (final mark in read.marks) {
        expect(mark.id, startsWith(kProcessedStudyKeyPrefix));
      }

      for (final mark in read.marks) {
        expect((await study.removeMark(mark.id)).isRight(), isTrue);
      }

      expect(await parts(ProcessedSection.summary), isEmpty);
      expect(await parts(ProcessedSection.keywords), isEmpty);
      expect((await study.read(originalKey)).marks, isEmpty);
    });

    test('el análisis corre sobre el texto propio y lo que marca se ve en el '
        'original; rehacer lo de la IA desde el original deja lo '
        'elegido', () async {
      await markOnOriginal('Escipión volvió a Roma.');
      await analyze();

      final marked = await study.read(originalKey);
      expect(spans(marked.of(StudyMarkKind.summary)), [
        (0, 20),
        (text.indexOf('Escipión'), text.length),
      ]);
      expect(marked.of(StudyMarkKind.synthesis), hasLength(1));
      expect(marked.of(StudyMarkKind.keyword), hasLength(4));

      expect((await study.clearAi(originalKey)).isRight(), isTrue);

      final after = await study.read(originalKey);
      expect(spans(after.of(StudyMarkKind.summary)), [
        (text.indexOf('Escipión'), text.length),
      ]);
      expect(after.of(StudyMarkKind.synthesis), isEmpty);
      final ownAfter = await study.read(ownKey);
      expect(ownAfter.started, isFalse);
    });

    test('el original no se analiza por su clave: eso va por el texto '
        'propio', () async {
      expect(
        (await study.savePart(
          renditionId: originalKey,
          content: text,
          partStart: 0,
          partEnd: 20,
          marks: const StudyPartMarks(summary: [], synthesis: [], keywords: []),
          completes: false,
        )).isLeft(),
        isTrue,
      );
      expect(
        (await study.addAiKeywords(
          renditionId: originalKey,
          content: text,
          words: const [StudyWord(0, 4, 'Roma')],
        )).isLeft(),
        isTrue,
      );
      expect(await parts(ProcessedSection.keywords), isEmpty);
    });
  });

  group('con «Texto»: la posición del original se lleva a la del texto', () {
    setUp(() async {
      final result = await h.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      }, original: add);
      expect(result.isRight(), isTrue, reason: '$result');
    });

    test('lo elegido en el original queda en su lugar del texto propio y en '
        'el de la fuente', () async {
      await markOnOriginal('Aníbal cruzó los Alpes.');

      final summary = (await parts(ProcessedSection.summary)).single;
      final start = text.indexOf('Aníbal');
      expect(summary.textRange, ProcessedSpan(start: start, end: start + 23));
      expect(summary.anchor?.start, start);
      expect(spans((await study.read(ownKey)).of(StudyMarkKind.summary)), [
        (start, start + 23),
      ]);
      expect(spans((await study.read(originalKey)).of(StudyMarkKind.summary)), [
        (start, start + 23),
      ]);
    });

    test('lo que en el texto propio ya no es la fuente —una página editada— '
        'no tiene dónde guardarse: falla y no guarda nada', () async {
      final page = (await parts(ProcessedSection.text)).single;
      await h.repository.editPart(page.id, 'Otro comienzo. $text');

      final start = text.indexOf('Cartago');
      final saved = await study.addUserMark(
        renditionId: originalKey,
        content: text,
        kind: StudyMarkKind.summary,
        start: start,
        end: start + 25,
      );

      expect(saved.isLeft(), isTrue);
      expect(await parts(ProcessedSection.summary), isEmpty);
    });
  });

  group('borrar las marcas de una clase', () {
    setUp(() async {
      await h.addSentence('s1', 'roma', text, start: 0, end: 20);
      await h.addSentence(
        'k1',
        'roma',
        text,
        start: 0,
        end: 4,
        kind: StudyMarkKind.keyword,
      );
      final result = await h.process('roma', {
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
        ProcessedSection.keywords: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      }, original: add);
      expect(result.isRight(), isTrue, reason: '$result');
    });

    test('borra las copiadas de la fuente y las elegidas, y solo de esa '
        'clase', () async {
      await markOnOriginal('Cartago perdió la guerra.');
      expect(
        (await study.read(originalKey)).of(StudyMarkKind.summary),
        hasLength(2),
      );

      expect(
        (await study.clearKind(originalKey, StudyMarkKind.summary)).isRight(),
        isTrue,
      );

      expect(await parts(ProcessedSection.summary), isEmpty);
      expect(
        (await study.read(originalKey)).of(StudyMarkKind.summary),
        isEmpty,
      );
      expect((await parts(ProcessedSection.keywords)).single.keywords, [
        'Roma',
      ]);
    });

    test('sacarle una palabra a una oración copiada deja las otras a la '
        'vista, ahora elegidas: «Actualizar» no las pisa', () async {
      await markOnOriginal('colonias', kind: StudyMarkKind.keyword);
      final copied = (await parts(ProcessedSection.keywords)).single;
      expect(copied.keywords, ['Roma', 'colonias']);
      // Se saca la que eligió la persona: la copiada que queda pasa a ser
      // elegida, y no deja de verse.
      final colonias = (await study.read(
        originalKey,
      )).of(StudyMarkKind.keyword).last;

      await study.removeMark(colonias.id);

      final left = (await parts(ProcessedSection.keywords)).single;
      expect(left.keywords, ['Roma']);
      expect(left.edited, isFalse);
      expect(left.isVerbatim, isTrue);
      expect(left.isPristineCopy, isFalse);
      expect(left.spans.single.chosen, isTrue);
      expect(spans((await study.read(originalKey)).of(StudyMarkKind.keyword)), [
        (0, 4),
      ]);
    });
  });

  test('en la Biblioteca, borrar una clase borra solo esa, solo de ese '
      'texto', () async {
    await h.vault.saveSource('otra', text: text);
    for (final id in ['roma', 'otra']) {
      for (final kind in StudyMarkKind.values) {
        await study.addUserMark(
          renditionId: 'rend-$id',
          content: text,
          kind: kind,
          start: 0,
          end: kind == StudyMarkKind.keyword ? 4 : 20,
        );
      }
    }

    await study.clearKind('rend-roma', StudyMarkKind.summary);

    final roma = await study.read('rend-roma');
    expect(roma.of(StudyMarkKind.summary), isEmpty);
    expect(roma.of(StudyMarkKind.synthesis), hasLength(1));
    expect(roma.of(StudyMarkKind.keyword), hasLength(1));
    expect(
      (await study.read('rend-otra')).of(StudyMarkKind.summary),
      hasLength(1),
    );
  });
}
