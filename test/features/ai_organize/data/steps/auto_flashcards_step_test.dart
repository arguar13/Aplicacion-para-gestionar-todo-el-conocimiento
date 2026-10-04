import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcards_by_parts.dart';

import '../../../../support/ai_organize_harness.dart';

/// Un modelo de tarjetas de mentira: una tarjeta por oración del tramo que
/// recibe, con la oración como cita. [inventedQuote] agrega primero una cuya
/// cita no está en el texto.
class _SentenceFlashcards implements FlashcardGenerator {
  bool inventedQuote = false;

  /// Si la cita de cada tarjeta llega parafraseada: en minúsculas, sin
  /// puntuación y con «antes de Cristo» como «a. C.», como la escribe un
  /// modelo chico.
  bool paraphrase = false;

  /// Si todas las citas son inventadas, cada una con otra pregunta.
  bool allInvented = false;

  /// Cada tramo que recibió, en orden.
  final contents = <String>[];
  final counts = <int>[];

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async {
    contents.add(content);
    counts.add(count);
    if (allInvented) {
      return [
        for (var i = 0; i < count; i++)
          FlashcardDraft(
            front: '¿Inventada ${contents.length}.$i?',
            back: 'Sí',
            quote: 'Algo que el texto no dice $i.',
          ),
      ];
    }
    final sentences = RegExp(
      r'[^.]+\.',
    ).allMatches(content).map((m) => m.group(0)!.trim()).toList();
    return [
      if (inventedQuote)
        const FlashcardDraft(
          front: '¿Algo inventado?',
          back: 'Sí',
          quote: 'Una frase que el texto no tiene.',
        ),
      for (final sentence in sentences)
        FlashcardDraft(
          front: '¿Qué dice «$sentence»?',
          back: sentence,
          quote: paraphrase ? _paraphrased(sentence) : sentence,
        ),
    ].take(count).toList();
  }
}

/// [sentence] como la cambia un modelo chico.
String _paraphrased(String sentence) => sentence
    .toLowerCase()
    .replaceAll('antes de cristo', 'a. c.')
    .replaceAll('asesoraba', 'aconsejaba')
    .replaceAll('.', '');

void main() {
  late AiOrganizeHarness vault;
  late _SentenceFlashcards model;
  late AutoFlashcardsStep step;

  setUp(() {
    vault = AiOrganizeHarness();
    model = _SentenceFlashcards();
    step = AutoFlashcardsStep(
      generator: model,
      flashcards: vault.flashcards,
      suggestions: vault.suggestions,
      runs: vault.runs,
    );
  });

  tearDown(() => vault.close());

  const article =
      'Roma fue fundada en el año 753 antes de Cristo. El Senado asesoraba '
      'a los cónsules. Los cónsules se elegían cada año. La república duró '
      'casi cinco siglos.';

  group('cuántas según el largo', () {
    String words(int n) => List.filled(n, 'palabra').join(' ');

    test('de 3 en un texto corto a 12 en uno largo', () {
      expect(flashcardTargetFor(words(800)), 3);
      expect(flashcardTargetFor(words(3000)), 5);
      expect(flashcardTargetFor(words(9000)), 9);
      expect(flashcardTargetFor(words(200000)), 12);
    });

    test('sin texto, ninguna', () {
      expect(flashcardTargetFor('  \n '), 0);
    });
  });

  test('crea las tarjetas ancladas a su frase, marcadas como de la IA y '
      'listas para repasar', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    final run = await vault.startRun('a');

    final report = await step.organize(item, runId: run);

    expect(report, const AiStepReport(applied: 3));
    final cards = await vault.db.select(vault.db.flashcards).get();
    expect(cards, hasLength(3));
    for (final card in cards) {
      expect(card.origin, ContentOrigin.ai);
      expect(card.aiRunId, run);
      expect(
        article.substring(card.sourceCharStart!, card.sourceCharEnd),
        card.back,
      );
      expect(card.dueAt.isAfter(vault.now), isFalse);
    }
  });

  test('la tarjeta cuya cita no se ubica no entra sola: va a «Para '
      'revisar» (F30)', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    model.inventedQuote = true;

    final report = await step.organize(item, runId: await vault.startRun('a'));

    final cards = await vault.db.select(vault.db.flashcards).get();
    expect(cards.map((c) => c.front), isNot(contains('¿Algo inventado?')));
    expect(cards, hasLength(3));
    expect(report, const AiStepReport(applied: 3, forReview: 1));

    final review = (await vault.suggestions.suggestionsFor(
      'a',
    )).getOrElse((f) => fail('$f')).whereType<FlashcardSuggestion>();
    expect(review.single.front, '¿Algo inventado?');
    expect(review.single.quote, 'Una frase que el texto no tiene.');
    expect(review.single.status, SuggestionStatus.pending);
  });

  test('aceptarla en «Para revisar» crea la tarjeta, de la persona y sin '
      'fragmento', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    model.inventedQuote = true;
    await step.organize(item, runId: await vault.startRun('a'));
    final proposal = (await vault.suggestions.suggestionsFor(
      'a',
    )).getOrElse((f) => fail('$f')).whereType<FlashcardSuggestion>().single;

    expect((await vault.suggestions.accept(proposal.id)).isRight(), isTrue);

    final adopted = (await vault.db.select(vault.db.flashcards).get())
        .singleWhere((c) => c.front == '¿Algo inventado?');
    expect(adopted.origin, ContentOrigin.user);
    expect(adopted.aiRunId, isNull);
    expect(adopted.sourceCharStart, isNull);
    expect(adopted.dueAt.isAfter(vault.now), isFalse);
  });

  test(
    'una que se descartó en «Para revisar» no se vuelve a proponer',
    () async {
      final item = await vault.source('a', title: 'Roma', content: article);
      model.inventedQuote = true;
      await step.organize(item, runId: await vault.startRun('a'));
      final proposal = (await vault.suggestions.suggestionsFor(
        'a',
      )).getOrElse((f) => fail('$f')).whereType<FlashcardSuggestion>().single;
      await vault.suggestions.reject(proposal.id);

      // Otra pasada sobre el mismo elemento, sin sus tarjetas: el modelo vuelve
      // a inventar la misma.
      await vault.db.delete(vault.db.flashcards).go();
      await step.organize(item, runId: await vault.startRun('a'));

      final proposals = (await vault.suggestions.suggestionsFor(
        'a',
      )).getOrElse((f) => fail('$f')).whereType<FlashcardSuggestion>();
      expect(proposals.single.status, SuggestionStatus.rejected);
    },
  );

  test('un modelo que inventa todo no llena «Para revisar»', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    model.allInvented = true;

    await step.organize(item, runId: await vault.startRun('a'));

    final review = (await vault.suggestions.suggestionsFor(
      'a',
    )).getOrElse((f) => fail('$f'));
    expect(review, hasLength(kMaxFlashcardsForReview));
    expect(await vault.db.select(vault.db.flashcards).get(), isEmpty);
  });

  test(
    'una cita parafraseada se ancla al pasaje real del texto (F30)',
    () async {
      final item = await vault.source('a', title: 'Roma', content: article);
      model.paraphrase = true;

      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      expect(report, const AiStepReport(applied: 3));
      final cards = await vault.db.select(vault.db.flashcards).get();
      for (final card in cards) {
        // El fragmento es el del texto, no el de la cita cambiada: la
        // respuesta de la tarjeta de mentira es la oración entera, y el pasaje
        // va de su primera palabra con contenido a la última.
        final fragment = article.substring(
          card.sourceCharStart!,
          card.sourceCharEnd,
        );
        expect(card.back, contains(fragment));
        expect(fragment, isNot(contains('a. c.')));
      }
    },
  );

  test('no repite una pregunta que ya tiene ni una que «no era»', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    // La misma pregunta, escrita distinto, ya la tiene la persona.
    await vault.flashcards.create(
      itemId: 'a',
      front: 'que dice «roma fue fundada en el año 753 antes de cristo.»',
      back: 'x',
    );
    // Y una que la IA hizo antes y la persona dijo que «no era».
    final earlier = await vault.startRun('a');
    final wrong = (await vault.flashcards.create(
      itemId: 'a',
      front: '¿Qué dice «El Senado asesoraba a los cónsules.»?',
      back: 'x',
      ai: AiProvenance(runId: earlier),
    )).getOrElse((f) => fail('$f'));
    await vault.flashcards.rejectAiFlashcard(wrong.id);

    await step.organize(item, runId: await vault.startRun('a'));

    final fronts = (await vault.db.select(vault.db.flashcards).get())
        .map((c) => c.front)
        .toList();
    expect(
      fronts.where((f) => f.toLowerCase().contains('roma fue fundada')),
      hasLength(1),
    );
    expect(fronts.where((f) => f.contains('Senado')), isEmpty);
    // Lo que ya tenía cuenta: pide solo las dos que faltan para llegar a 3,
    // más una de repuesto.
    expect(model.counts, [3]);
    expect(fronts, hasLength(2));
  });

  test('con su cantidad hecha no suma ninguna; con «otra tanda» (F30), sí, '
      'sin repetir preguntas', () async {
    final item = await vault.source('a', title: 'Roma', content: article);
    await step.organize(item, runId: await vault.startRun('a'));
    expect(await vault.db.select(vault.db.flashcards).get(), hasLength(3));

    final again = await step.makeFlashcards(
      item,
      runId: await vault.startRun('a'),
    );
    expect(again, AiStepReport.nothing);

    final another = await step.makeFlashcards(
      item,
      runId: await vault.startRun('a'),
      anotherBatch: true,
    );
    // El texto tiene cuatro oraciones: la única que faltaba.
    expect(another, const AiStepReport(applied: 1));
    final fronts = (await vault.db.select(vault.db.flashcards).get())
        .map((c) => c.front)
        .toList();
    expect(fronts.toSet(), hasLength(fronts.length));
  });

  test('un texto largo se recorre por partes, repartidas, sin pasarse de '
      'la ventana', () async {
    final sentences = [
      for (var i = 0; i < 4000; i++) 'La idea número $i del libro es esta.',
    ];
    final book = sentences.join(' ');
    final item = await vault.source('libro', title: 'Libro', content: book);

    final report = await step.organize(
      item,
      runId: await vault.startRun('libro'),
    );

    expect(report.applied, 12);
    expect(model.contents, hasLength(6));
    expect(
      model.contents.every((c) => c.length <= kFlashcardPartChars),
      isTrue,
    );
    expect(model.counts.every((c) => c <= kMaxFlashcardsPerCall), isTrue);
    // Del principio al final del libro, no solo los primeros tramos.
    expect(model.contents.first, isNot(contains('número 0 ')));
    expect(model.contents.last, contains('número 3'));
    final cards = await vault.db.select(vault.db.flashcards).get();
    for (final card in cards) {
      expect(
        book.substring(card.sourceCharStart!, card.sourceCharEnd),
        card.back,
      );
    }
  });
}
