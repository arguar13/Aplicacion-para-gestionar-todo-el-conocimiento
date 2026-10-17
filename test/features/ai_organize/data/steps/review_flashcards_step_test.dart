import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/data/steps/review_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_reviewer.dart';

import '../../../../support/ai_organize_harness.dart';

/// Un revisor de mentira: contesta lo que diga [verdictFor] de cada tarjeta,
/// por su pregunta, y anota cada tanda que le llega.
class _FakeReviewer implements FlashcardReviewer {
  FlashcardVerdict? Function(int index, FlashcardToReview card) verdictFor =
      (_, _) => null;

  final batches = <List<FlashcardToReview>>[];

  @override
  Future<List<FlashcardVerdict>> reviewFlashcards(
    List<FlashcardToReview> cards,
  ) async {
    batches.add(cards);
    return [
      for (final (index, card) in cards.indexed) ?verdictFor(index, card),
    ];
  }
}

void main() {
  late AiOrganizeHarness vault;
  late _FakeReviewer reviewer;
  late ReviewFlashcardsStep step;
  late ModelTextBudget budget;

  setUp(() {
    vault = AiOrganizeHarness();
    reviewer = _FakeReviewer();
    budget = kSmallWindowTextBudget;
    step = ReviewFlashcardsStep(
      reviewer: reviewer,
      flashcards: vault.flashcards,
      suggestions: vault.suggestions,
      textBudget: () => budget,
    );
  });

  tearDown(() => vault.close());

  final article = [
    'El Quijote lo escribió Miguel de Cervantes.',
    for (var i = 0; i < 60; i++) 'Relleno número $i del texto.',
    'Roma cayó en el año 476.',
  ].join(' ');

  Future<String> reviewRun() async => (await vault.runs.startRun(
    'a',
    model: 'gemini-3.8-flash',
    scope: AiRunScope.review,
  )).getOrElse((f) => fail('$f'));

  /// Una tarjeta de la IA anclada a [quote] dentro del artículo.
  Future<String> aiCard(
    String run,
    String front,
    String back, {
    String? quote,
  }) async {
    final start = quote == null ? null : article.indexOf(quote);
    return (await vault.flashcards.create(
      itemId: 'a',
      front: front,
      back: back,
      sourceCharStart: start,
      sourceCharEnd: start == null ? null : start + quote!.length,
      ai: AiProvenance(runId: run),
    )).getOrElse((f) => fail('$f')).id;
  }

  Future<List<CorrectionSuggestion>> corrections() async =>
      (await vault.suggestions.suggestionsFor('a'))
          .getOrElse((f) => fail('$f'))
          .whereType<CorrectionSuggestion>()
          .toList();

  test('revisa solo las tarjetas que siguen siendo de la IA, cada una con su '
      'pasaje', () async {
    final item = await vault.source('a', title: 'Libros', content: article);
    final organized = await vault.startRun('a');
    await aiCard(
      organized,
      '¿Quién escribió el Quijote?',
      'Lope de Vega.',
      quote: 'El Quijote lo escribió Miguel de Cervantes.',
    );
    await aiCard(
      organized,
      '¿Cuándo cayó Roma?',
      'En 476.',
      quote: 'Roma cayó en el año 476.',
    );
    // Una de la persona y una que la persona adoptó: no se revisan.
    await vault.flashcards.create(itemId: 'a', front: '¿Mía?', back: 'Sí.');
    final adopted = await aiCard(organized, '¿Adoptada?', 'Sí.');
    await vault.flashcards.update(
      id: adopted,
      front: '¿Adoptada?',
      back: 'Sí!',
    );

    await step.review(item, runId: await reviewRun());

    final seen = reviewer.batches.expand((b) => b).toList();
    expect(seen.map((c) => c.front), [
      '¿Quién escribió el Quijote?',
      '¿Cuándo cayó Roma?',
    ]);
    expect(seen[0].passage, contains('Miguel de Cervantes'));
    expect(seen[0].passage, isNot(contains('476')));
    expect(seen[1].passage, contains('Roma cayó en el año 476'));
    expect(seen[1].passage, isNot(contains('Cervantes')));
  });

  test('deja cada corrección y cada tarjeta para sacar en «Revisión», con el '
      'antes, el después, el porqué y la pasada', () async {
    final item = await vault.source('a', title: 'Libros', content: article);
    final organized = await vault.startRun('a');
    final wrong = await aiCard(
      organized,
      '¿Quién escribió el Quijote?',
      'Lope de Vega.',
    );
    final useless = await aiCard(organized, '¿Relleno?', 'Sí.');
    await aiCard(organized, '¿Cuándo cayó Roma?', 'En 476.');
    reviewer.verdictFor = (index, card) => switch (card.front) {
      '¿Quién escribió el Quijote?' => FlashcardCorrection(
        index: index,
        reason: 'El pasaje dice Cervantes.',
        front: card.front,
        back: 'Miguel de Cervantes.',
      ),
      '¿Relleno?' => FlashcardRemoval(index: index, reason: 'No enseña nada.'),
      _ => null,
    };
    final run = await reviewRun();

    final report = await step.review(
      item,
      runId: run,
      model: 'gemini-3.8-flash',
    );

    expect(report, const AiStepReport(forReview: 2));
    final made = await corrections();
    final fix = made.firstWhere((c) => c.subjectId == wrong);
    expect(fix.subject, CorrectionSubject.flashcard);
    expect(fix.before, {
      FlashcardCorrectionField.front: '¿Quién escribió el Quijote?',
      FlashcardCorrectionField.back: 'Lope de Vega.',
    });
    expect(fix.after, {
      FlashcardCorrectionField.front: '¿Quién escribió el Quijote?',
      FlashcardCorrectionField.back: 'Miguel de Cervantes.',
    });
    expect(fix.reason, 'El pasaje dice Cervantes.');
    expect(fix.aiRunId, run);
    expect(fix.model, 'gemini-3.8-flash');
    expect(fix.status, SuggestionStatus.pending);
    final drop = made.firstWhere((c) => c.subjectId == useless);
    expect(drop.after, isNull);
    expect(drop.reason, 'No enseña nada.');
    // Nada cambió: lo decide la persona.
    final cards = await vault.db.select(vault.db.flashcards).get();
    expect(cards.map((c) => c.back), contains('Lope de Vega.'));
    expect(cards, hasLength(3));
  });

  test('pide de a tantas tarjetas como lee el modelo, con el pasaje '
      'repartido entre ellas', () async {
    final item = await vault.source('a', title: 'Libros', content: article);
    final organized = await vault.startRun('a');
    for (var i = 0; i < 6; i++) {
      await aiCard(organized, '¿Pregunta $i?', 'Respuesta $i.');
    }

    await step.review(item, runId: await reviewRun());

    // Gemma: de a cuatro, 3000 caracteres repartidos.
    expect(reviewer.batches.map((b) => b.length), [4, 2]);
    for (final card in reviewer.batches.expand((b) => b)) {
      expect(card.passage.length, lessThanOrEqualTo(752));
      expect(card.passage.length, greaterThan(600));
    }
  });

  test('con un modelo de ventana grande, de a ocho y con más pasaje, pero '
      'nunca más que el tope', () async {
    budget = textBudgetFor(1000000);
    final long = List.filled(3000, 'palabra').join(' ');
    final item = await vault.source('a', title: 'Largo', content: long);
    final organized = await vault.startRun('a');
    for (var i = 0; i < 9; i++) {
      await aiCard(organized, '¿Pregunta $i?', 'Respuesta $i.');
    }

    await step.review(item, runId: await reviewRun());

    expect(reviewer.batches.map((b) => b.length), [8, 1]);
    expect(
      reviewer.batches.first.first.passage.length,
      lessThanOrEqualTo(kMaxReviewPassageChars + 2),
    );
    expect(
      reviewer.batches.first.first.passage.length,
      greaterThan(kMaxReviewPassageChars - 50),
    );
  });

  test(
    'no vuelve a revisar una tarjeta con una corrección pendiente',
    () async {
      final item = await vault.source('a', title: 'Libros', content: article);
      final organized = await vault.startRun('a');
      await aiCard(organized, '¿Quién escribió el Quijote?', 'Lope de Vega.');
      reviewer.verdictFor = (index, _) =>
          FlashcardRemoval(index: index, reason: 'Mal.');
      await step.review(item, runId: await reviewRun());
      reviewer.batches.clear();

      final report = await step.review(item, runId: await reviewRun());

      expect(report, AiStepReport.nothing);
      expect(reviewer.batches, isEmpty);
    },
  );

  test('no vuelve a proponer lo que la persona descartó, pero sí otra '
      'corrección distinta', () async {
    final item = await vault.source('a', title: 'Libros', content: article);
    final organized = await vault.startRun('a');
    await aiCard(organized, '¿Quién escribió el Quijote?', 'Lope de Vega.');
    var answer = 'Miguel de Cervantes.';
    reviewer.verdictFor = (index, card) => FlashcardCorrection(
      index: index,
      reason: 'r',
      front: card.front,
      back: answer,
    );
    await step.review(item, runId: await reviewRun());
    await vault.suggestions.reject((await corrections()).single.id);

    // Lo mismo, con otras mayúsculas y espacios: no.
    answer = '  miguel de   cervantes. ';
    expect(
      await step.review(item, runId: await reviewRun()),
      AiStepReport.nothing,
    );
    // Otra cosa: sí.
    answer = 'Cervantes, en 1605.';
    expect(
      await step.review(item, runId: await reviewRun()),
      const AiStepReport(forReview: 1),
    );
  });

  test('sin tarjetas de la IA no le pide nada al modelo', () async {
    final item = await vault.source('a', title: 'Libros', content: article);
    await vault.flashcards.create(itemId: 'a', front: '¿Mía?', back: 'Sí.');

    expect(
      await step.review(item, runId: await reviewRun()),
      AiStepReport.nothing,
    );
    expect(reviewer.batches, isEmpty);
  });
}
