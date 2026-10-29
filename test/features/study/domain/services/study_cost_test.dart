import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/services/study_cost.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Lo que va a pedirle a la IA analizar un texto (F43, paso 15): los pedidos
/// son las partes que arma el análisis, y los tokens, los que se cuentan para
/// repartir la ventana.
void main() {
  /// [count] oraciones de [length] caracteres, una detrás de la otra.
  List<StudySentence> sentences(int count, {int length = 40}) => [
    for (var i = 0; i < count; i++)
      StudySentence(i * (length + 1), i * (length + 1) + length),
  ];

  test('sin nada que analizar, nada que pedir', () {
    expect(
      planStudyAnalysis(const [], from: 0, charBudget: 1000),
      StudyAnalysisPlan.nothing,
    );
    expect(
      planStudyAnalysis(sentences(3), from: 3, charBudget: 1000).isEmpty,
      isTrue,
    );
  });

  test('una parte: la instrucción, sus oraciones a dos caracteres y medio '
      'por token, y la línea CLAVE de cada una', () {
    final plan = planStudyAnalysis(sentences(3), from: 0, charBudget: 10000);

    expect(plan.parts, 1);
    // 3 × (40 + 7) = 141 caracteres → 57 tokens, más la instrucción.
    expect(plan.inputTokens, kStudyInstructionTokens + 57);
    expect(plan.outputTokens, studyReplyTokens(3));
  });

  test('las partes son las que arma el análisis: cada una con su '
      'instrucción', () {
    final all = sentences(10);
    const budget = 250;
    var expected = 0;
    for (var next = 0; next < all.length; expected++) {
      next = studyPartEnd(all, next, charBudget: budget);
    }

    final plan = planStudyAnalysis(all, from: 0, charBudget: budget);

    expect(expected, greaterThan(1));
    expect(plan.parts, expected);
    expect(
      plan.inputTokens,
      greaterThanOrEqualTo(kStudyInstructionTokens * expected),
    );
  });

  test('desde la oración que sigue: lo ya analizado no se pide', () {
    final whole = planStudyAnalysis(sentences(6), from: 0, charBudget: 10000);
    final rest = planStudyAnalysis(sentences(6), from: 4, charBudget: 10000);

    expect(rest.parts, 1);
    expect(rest.outputTokens, studyReplyTokens(2));
    expect(rest.inputTokens, lessThan(whole.inputTokens));
  });

  test('desde un texto: parte las oraciones y empieza donde quedó el '
      'análisis', () {
    const content = 'Roma fundó colonias. Cartago perdió. Aníbal cruzó.';

    final whole = planStudyAnalysisOf((
      content: content,
      markdown: false,
      analyzedUntil: 0,
      charBudget: 10000,
    ));
    final rest = planStudyAnalysisOf((
      content: content,
      markdown: false,
      analyzedUntil: content.indexOf('Aníbal'),
      charBudget: 10000,
    ));
    final done = planStudyAnalysisOf((
      content: content,
      markdown: false,
      analyzedUntil: content.length,
      charBudget: 10000,
    ));

    expect(whole.outputTokens, studyReplyTokens(3));
    expect(rest.outputTokens, studyReplyTokens(1));
    expect(done, StudyAnalysisPlan.nothing);
  });
}
