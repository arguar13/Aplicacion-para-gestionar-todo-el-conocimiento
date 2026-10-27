import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_study_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/study/data/repositories/keyed_study_repository.dart';
import 'package:sinapsis/features/study/data/repositories/study_repository_impl.dart';
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

/// Estudiar el documento procesado en él mismo (F41, decisión I): la máquina de
/// estudiar de siempre, sobre el texto propio, guardando en el procesado.
void main() {
  const text =
      'Roma fundó colonias. Cartago perdió la guerra. '
      'Aníbal cruzó los Alpes. Escipión volvió a Roma.';
  late ProcessedHarness h;
  late KeyedStudyRepository study;
  final docId = processedDocumentIdFor('roma');
  final key = processedStudyKeyFor(docId);

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource('roma', title: 'Roma', text: text);
    study = KeyedStudyRepository(
      fallback: StudyRepositoryImpl(
        database: h.db,
        telemetry: _SilentTelemetry(),
      ),
      byPrefix: {
        kProcessedStudyKeyPrefix: ProcessedStudyRepositoryImpl(
          database: h.db,
          telemetry: _SilentTelemetry(),
          ids: FakeIdGenerator(prefix: 'estudio'),
          clock: () => h.vault.now,
        ),
      },
    );
  });
  tearDown(() => h.close());

  Future<ProcessedStudyText> studyText() async =>
      (await h.repository.studyTextOf(docId)).getRight().toNullable()!;

  Future<void> analyze(ProcessedStudyText text) =>
      AnalyzeForStudy(repository: study, marker: _FirstSentenceMarker())
          .call(
            renditionId: text.key,
            content: text.content,
            markdown: text.markdown,
          )
          .drain<void>();

  Future<List<ProcessedPart>> parts(ProcessedSection section) async =>
      (await h.repository.partsOf(
        docId,
        sections: {section},
      )).getRight().toNullable()!;

  group('el texto propio', () {
    test('son sus páginas, y su clave es la del procesado', () async {
      await h.process.passUnchanged('roma');

      final own = await studyText();

      expect(own.key, key);
      expect(own.content, text);
      expect(own.layout.hasPages, isTrue);
      expect(own.asStudyText.renditionId, key);
      expect(own.asStudyText.itemId, docId);
    });

    test(
      'sin «Texto», con la copia del original, es el de la fuente',
      () async {
        await h.vault.saveSource(
          'libro',
          text: text,
          originalName: 'libro.txt',
        );
        final id = processedDocumentIdFor('libro');
        final result = await h.process(
          'libro',
          const {},
          original: const OriginalEdit(ProcessedChange.add),
        );
        expect(result.isRight(), isTrue, reason: '$result');

        final own = (await h.repository.studyTextOf(
          id,
        )).getRight().toNullable()!;

        expect(own.content, text);
        expect(own.layout.hasPages, isFalse);
        expect(own.layout.sourceRenditionId, 'rend-libro');
      },
    );

    test('sin texto ni original, no hay qué estudiar', () async {
      await h.addSentence('m1', 'roma', text, start: 0, end: 20);
      await h.process('roma', {
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });

      expect(
        (await h.repository.studyTextOf(docId)).getRight().toNullable(),
        isNull,
      );
    });
  });

  group('estudiarlo con la máquina de siempre', () {
    setUp(() => h.process.passUnchanged('roma'));

    test('lo estudiado queda en el procesado, propio, con su lugar en el texto '
        'y en la fuente', () async {
      await analyze(await studyText());

      final summary = (await parts(ProcessedSection.summary)).single;
      expect(summary.origin, ProcessedPartOrigin.studied);
      expect(summary.content, 'Roma fundó colonias.');
      expect(summary.textRange, const ProcessedSpan(start: 0, end: 20));
      expect(summary.anchor?.renditionId, 'rend-roma');
      expect(summary.sourceOffsetOf(5), 5);
      final keywords = await parts(ProcessedSection.keywords);
      expect(keywords.map((p) => p.keywords), [
        ['Roma'],
        ['Cartago'],
        ['Aníbal'],
        ['Escipión'],
      ]);
      // Nada en la fuente.
      expect(await h.db.select(h.db.studyMarks).get(), isEmpty);

      final read = await study.read(key);
      expect(read.complete, isTrue);
      expect(read.analyzedUntil, text.length);
      expect(
        read.of(StudyMarkKind.summary).map((m) => (m.start, m.end, m.origin)),
        [(0, 20, ContentOrigin.ai)],
      );
      expect(read.of(StudyMarkKind.keyword), hasLength(4));
    });

    test('«Actualizar» desde la fuente no lo pisa; «Reemplazar», sí', () async {
      await analyze(await studyText());
      await h.addSentence('m1', 'roma', text, start: 21, end: 46);

      await h.process('roma', {ProcessedSection.summary: SectionEdit.update()});
      expect((await parts(ProcessedSection.summary)).map((p) => p.content), [
        'Roma fundó colonias.',
        'Cartago perdió la guerra.',
      ]);

      await h.process('roma', {
        ProcessedSection.summary: SectionEdit.replace(
          const SectionInput.fromSource(),
        ),
      });
      expect((await parts(ProcessedSection.summary)).map((p) => p.origin), [
        ProcessedPartOrigin.copied,
      ]);
    });

    test(
      'elegir a mano queda de la persona: volver a analizar no lo saca',
      () async {
        final own = await studyText();
        await study.addUserMark(
          renditionId: key,
          content: own.content,
          kind: StudyMarkKind.summary,
          start: 47,
          end: 70,
        );
        await study.addUserMark(
          renditionId: key,
          content: own.content,
          kind: StudyMarkKind.keyword,
          start: text.indexOf('cruzó'),
          end: text.indexOf('cruzó') + 'cruzó'.length,
        );

        await analyze(own);
        await study.clearAi(key);

        final summary = (await parts(ProcessedSection.summary)).single;
        expect(summary.origin, ProcessedPartOrigin.chosen);
        expect(summary.content, 'Aníbal cruzó los Alpes.');
        final keywords = await parts(ProcessedSection.keywords);
        expect(keywords.single.keywords, ['cruzó']);
        expect(keywords.single.spans.single.chosen, isTrue);
        final read = await study.read(key);
        expect(read.started, isFalse);
      },
    );

    test('sacar una marca la saca del procesado', () async {
      await analyze(await studyText());
      final read = await study.read(key);
      final keyword = read.of(StudyMarkKind.keyword).first;
      final summary = read.of(StudyMarkKind.summary).single;

      await study.removeMark(keyword.id);
      await study.removeMark(summary.id);

      expect(await parts(ProcessedSection.summary), isEmpty);
      expect((await parts(ProcessedSection.keywords)).map((p) => p.keywords), [
        ['Cartago'],
        ['Aníbal'],
        ['Escipión'],
      ]);
    });

    test('lo copiado de la fuente cuenta como de la persona: el análisis no '
        'lo rehace ni lo repite', () async {
      await h.addSentence('m1', 'roma', text, start: 0, end: 20);
      await h.process('roma', {
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });

      await analyze(await studyText());

      final summary = await parts(ProcessedSection.summary);
      expect(summary.single.origin, ProcessedPartOrigin.copied);
      final read = await study.read(key);
      expect(read.of(StudyMarkKind.summary).single.origin, ContentOrigin.user);
    });

    test('corregir una página corre lo que sigue y vuelve a empezar el '
        'análisis', () async {
      await analyze(await studyText());
      final page = (await parts(ProcessedSection.text)).single;

      await h.repository.editPart(page.id, 'Prólogo. $text');

      final summary = (await parts(ProcessedSection.summary)).single;
      expect(summary.textRange, const ProcessedSpan(start: 9, end: 29));
      final own = await studyText();
      expect(own.content.substring(9, 29), 'Roma fundó colonias.');
      final read = await study.read(key);
      expect(read.analyzedUntil, 0);
      expect(read.complete, isFalse);
      // Su ancla en la fuente sigue llevando a la fuente.
      expect(summary.anchor?.start, 0);
    });

    test('una oración con palabras clave copiadas de la fuente: la IA no le '
        'pone otras, la persona puede sumarle una', () async {
      await h.addSentence(
        'k1',
        'roma',
        text,
        start: 0,
        end: 4,
        kind: StudyMarkKind.keyword,
      );
      await h.process('roma', {
        ProcessedSection.keywords: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });
      final own = await studyText();

      await analyze(own);
      await study.addUserMark(
        renditionId: key,
        content: own.content,
        kind: StudyMarkKind.keyword,
        start: text.indexOf('colonias'),
        end: text.indexOf('colonias') + 'colonias'.length,
      );

      final keywords = await parts(ProcessedSection.keywords);
      final first = keywords.first;
      expect(first.origin, ProcessedPartOrigin.copied);
      expect(first.keywords, ['Roma', 'colonias']);
      expect(first.spans.last.chosen, isTrue);
      expect(keywords, hasLength(4));
    });

    test('si el texto se reemplaza por otro, lo estudiado que ya no está ahí '
        'se queda sin lugar en él', () async {
      await analyze(await studyText());
      await h.vault.saveSource('roma', text: 'Otro texto, otra cosa.');

      await h.process('roma', {
        ProcessedSection.text: SectionEdit.replace(
          const SectionInput.fromSource(),
        ),
      });

      final summary = (await parts(ProcessedSection.summary)).single;
      expect(summary.textRange, isNull);
      expect(summary.content, 'Roma fundó colonias.');
    });

    test(
      'corregir una página corre lo que está en las páginas que siguen',
      () async {
        final long = [
          for (var i = 0; i < 600; i++)
            'Esta es la oración número $i del libro.',
        ].join(' ');
        await h.vault.saveSource('largo', text: long);
        final id = processedDocumentIdFor('largo');
        await h.process.passUnchanged('largo');
        final own = (await h.repository.studyTextOf(
          id,
        )).getRight().toNullable()!;
        await AnalyzeForStudy(repository: study, marker: _FirstSentenceMarker())
            .call(
              renditionId: own.key,
              content: own.content,
              markdown: own.markdown,
            )
            .drain<void>();
        final pages = (await h.repository.partsOf(
          id,
          sections: {ProcessedSection.text},
        )).getRight().toNullable()!;
        expect(pages.length, greaterThan(1));
        final later =
            (await h.repository.partsOf(
                  id,
                  sections: {ProcessedSection.summary},
                ))
                .getRight()
                .toNullable()!
                .where((p) => p.textRange!.start >= pages.first.textEnd!)
                .first;

        await h.repository.editPart(pages.first.id, 'Corto.');

        final moved = (await h.repository.partsOf(
          id,
          sections: {ProcessedSection.summary},
        )).getRight().toNullable()!.firstWhere((p) => p.id == later.id);
        final delta = 'Corto.'.length - pages.first.content.length;
        expect(moved.textRange!.start, later.textRange!.start + delta);
        final again = (await h.repository.studyTextOf(
          id,
        )).getRight().toNullable()!;
        expect(
          again.content.substring(moved.textRange!.start, moved.textRange!.end),
          moved.content,
        );
      },
    );

    test('las claves de la Biblioteca siguen yendo a la Biblioteca', () async {
      await study.addUserMark(
        renditionId: 'rend-roma',
        content: text,
        kind: StudyMarkKind.summary,
        start: 0,
        end: 20,
      );

      expect(await h.db.select(h.db.studyMarks).get(), hasLength(1));
      expect(await parts(ProcessedSection.summary), isEmpty);
      expect(
        (await study.read('rend-roma')).of(StudyMarkKind.summary),
        hasLength(1),
      );
    });
  });
}
