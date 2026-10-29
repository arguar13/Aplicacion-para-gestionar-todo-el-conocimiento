import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart'
    as study;

import '../support/report_harness.dart';
import '../support/sample_reports.dart';

/// Lo que leen el visor y la hoja de los informes (F43, paso 10): las
/// palabras clave de las fuentes —sus marcas de estudiar, las mismas del
/// original (M8)— y las plantillas propias ya usadas.
void main() {
  late ReportHarness h;
  const text = 'Moisés guía al pueblo. Moisés llega al Sinaí con el pueblo.';

  setUp(() async {
    h = await ReportHarness.create();
    await h.processed('p-1', 'Éxodo', text: text);
    await h.processed('p-2', 'Génesis', text: 'Abraham sale de Ur.');
  });

  /// Marca [word] —todas las veces que está— como palabra clave de
  /// [documentId], como lo hace la persona en el original.
  Future<void> mark(String documentId, String content, String word) async {
    final studyText =
        (await h.container
                .read(processedRepositoryProvider)
                .studyTextOf(documentId))
            .getOrElse((f) => throw StateError('$f'))!;
    var at = studyText.content.indexOf(word);
    while (at >= 0) {
      final saved = await h.container
          .read(study.studyRepositoryProvider)
          .addUserMark(
            renditionId: studyText.key,
            content: studyText.content,
            kind: StudyMarkKind.keyword,
            start: at,
            end: at + word.length,
          );
      expect(saved.isRight(), isTrue);
      at = studyText.content.indexOf(word, at + word.length);
    }
  }

  Future<List<String>> keywordsOf(List<String> ids) => h.container.read(
    reportSourceKeywordsProvider(CreationSourceIds(ids)).future,
  );

  test('las de las marcas de estudiar, las más marcadas primero', () async {
    expect(await keywordsOf(['p-1']), isEmpty);
    await mark('p-1', text, 'Sinaí');
    await mark('p-1', text, 'Moisés');
    await mark('p-2', 'Abraham sale de Ur.', 'Abraham');
    h.container.invalidate(reportSourceKeywordsProvider);
    expect(await keywordsOf(['p-1', 'p-2']), ['Moisés', 'Abraham', 'Sinaí']);
  });

  test('las de un documento donde se ocultaron no cuentan', () async {
    await mark('p-1', text, 'Sinaí');
    await mark('p-2', 'Abraham sale de Ur.', 'Abraham');
    final hidden = h.container.listen(
      processedOriginalHiddenProvider('p-1').notifier,
      (_, _) {},
    );
    await hidden.read().setHidden(StudyMarkKind.keyword, hidden: true);
    h.container.invalidate(reportSourceKeywordsProvider);
    expect(await keywordsOf(['p-1', 'p-2']), ['Abraham']);
    // Y el visor arranca con el rosa apagado solo si se ocultaron en todas.
    expect(
      h.container.read(
        reportKeywordsShownByDefaultProvider(const CreationSourceIds(['p-1'])),
      ),
      isFalse,
    );
    expect(
      h.container.read(
        reportKeywordsShownByDefaultProvider(
          const CreationSourceIds(['p-1', 'p-2']),
        ),
      ),
      isTrue,
    );
    hidden.close();
  });

  test('sin las de las fuentes, las que destacó la IA en el informe', () async {
    final creation = await h.ready(sampleReport());
    final sub = h.container.listen(
      reportKeywordsProvider(reportKeywordsKeyOf(creation)),
      (_, _) {},
    );
    await h.container.read(
      reportSourceKeywordsProvider(
        CreationSourceIds(creation.sourceIds),
      ).future,
    );
    expect(sub.read(), ReportKeywords(const ['Sinaí', 'Alianza']));
    sub.close();
  });

  test(
    'las plantillas propias ya usadas, sin repetir y la más nueva primero',
    () async {
      StudyCreation report(String id, Map<String, Object?> options) =>
          StudyCreation(
            id: id,
            kind: StudyCreationKind.report,
            scope: const CreationScope.allProcessed(),
            options: options,
            languageCode: 'es',
            status: CreationStatus.ready,
            createdAt: DateTime(2026, 10, 29),
            updatedAt: DateTime(2026, 10, 29),
          );
      Map<String, Object?> custom(String text) => {
        CreationOptionValues.template: CreationOptionValues.custom,
        CreationOptionValues.customTemplate: text,
      };
      expect(
        usedReportCustomTemplates([
          report('1', custom('Una línea de tiempo')),
          report('2', custom('  ')),
          report('3', {
            CreationOptionValues.template: CreationOptionValues.glossary,
            CreationOptionValues.customTemplate: 'De otra plantilla',
          }),
          report('4', custom('una linea de tiempo')),
          report('5', custom('Preguntas y respuestas')),
          StudyCreation(
            id: '6',
            kind: StudyCreationKind.quiz,
            scope: const CreationScope.allProcessed(),
            options: custom('De un cuestionario'),
            languageCode: 'es',
            status: CreationStatus.ready,
            createdAt: DateTime(2026, 10, 29),
            updatedAt: DateTime(2026, 10, 29),
          ),
        ]),
        ['Una línea de tiempo', 'Preguntas y respuestas'],
      );
      expect(
        usedReportCustomTemplates([
          for (var i = 0; i < 9; i++) report('$i', custom('Plantilla $i')),
        ]),
        hasLength(kReportUsedTemplatesShown),
      );
    },
  );

  test('lo que se pliega, se responde y a dónde se salta', () {
    final sub = h.container.listen(
      reportReadingProvider('informe').notifier,
      (_, _) {},
    );
    final reading = sub.read();
    ReportReadingState state() =>
        h.container.read(reportReadingProvider('informe'));
    reading
      ..toggleFold(1)
      ..answer(0, 0, 2)
      ..answer(0, 0, 3);
    expect(state().folded, {1});
    expect(state().answers, {(0, 0): 2}, reason: 'la primera es la que cuenta');
    reading.jump(1);
    expect(state().folded, isEmpty, reason: 'saltar despliega');
    expect((state().jumpTo, state().jumps), (1, 1));
    reading
      ..foldAll(3)
      ..resetAnswers()
      ..setKeywords(shown: false);
    expect(state().folded, {0, 1, 2});
    expect(state().answers, isEmpty);
    expect(state().keywords, isFalse);
    reading.unfoldAll();
    expect(state().folded, isEmpty);
    sub.close();
  });
}
