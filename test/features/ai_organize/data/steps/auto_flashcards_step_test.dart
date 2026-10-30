import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/flashcard_target.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/processed_rows.dart';

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
  // Lo que lee el modelo elegido: Gemma, salvo que la prueba diga otro.
  late ModelTextBudget budget;

  setUp(() {
    vault = AiOrganizeHarness();
    model = _SentenceFlashcards();
    budget = kSmallWindowTextBudget;
    step = AutoFlashcardsStep(
      generator: model,
      flashcards: vault.flashcards,
      suggestions: vault.suggestions,
      runs: vault.runs,
      processed: vault.processed,
      textBudget: () => budget,
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

    test('«Menos» es la mitad y «Más», una vez y media, sobre lo que da el '
        'largo (F43, M18)', () {
      int target(int n, FlashcardAmount amount) =>
          flashcardTargetFor(words(n), amount: amount);
      expect(target(800, FlashcardAmount.fewer), 2);
      expect(target(800, FlashcardAmount.standard), 3);
      expect(target(800, FlashcardAmount.more), 5);
      expect(target(9000, FlashcardAmount.fewer), 5);
      expect(target(9000, FlashcardAmount.more), 14);
      expect(target(200000, FlashcardAmount.fewer), 6);
      expect(target(200000, FlashcardAmount.more), kMaxMoreAiFlashcards);
      expect(flashcardTargetFor(' ', amount: FlashcardAmount.more), 0);
    });
  });

  group('con lo elegido en «Para cada documento» (F43, M18)', () {
    late _SentenceFlashcards styledModel;
    late List<FlashcardStyle> styledWith;

    setUp(() {
      styledModel = _SentenceFlashcards();
      styledWith = [];
      step = AutoFlashcardsStep(
        generator: model,
        flashcards: vault.flashcards,
        suggestions: vault.suggestions,
        runs: vault.runs,
        processed: vault.processed,
        textBudget: () => budget,
        styled: (style) {
          styledWith.add(style);
          return styledModel;
        },
      );
    });

    test('el idioma, la dificultad y el tema van al generador con estilo, y '
        'cuántas, a la cantidad', () async {
      const style = FlashcardStyle(
        languageCode: 'en',
        difficulty: FlashcardDifficulty.hard,
        topic: 'el Senado',
        amount: FlashcardAmount.fewer,
      );
      final item = await vault.source('a', title: 'Roma', content: article);

      final report = await step.makeFlashcards(
        item,
        runId: await vault.startRun('a'),
        style: style,
      );

      // El artículo da 3; «Menos», 2.
      expect(report, const AiStepReport(applied: 2));
      expect(styledWith, [style]);
      expect(styledModel.contents, isNotEmpty);
      expect(model.contents, isEmpty);
    });

    test('«Más» pide más que lo de siempre, sin estilo en el pedido: el '
        'generador de siempre', () async {
      final item = await vault.source('a', title: 'Roma', content: article);

      final report = await step.makeFlashcards(
        item,
        runId: await vault.startRun('a'),
        style: const FlashcardStyle(amount: FlashcardAmount.more),
      );

      // Cinco pedidas (lo de siempre serían 3); el texto tiene cuatro
      // oraciones.
      expect(report, const AiStepReport(applied: 4));
      expect(styledWith, isEmpty);
      expect(model.contents, isNotEmpty);
    });

    test('lo de siempre no pasa por el generador con estilo', () async {
      final item = await vault.source('a', title: 'Roma', content: article);

      await step.organize(item, runId: await vault.startRun('a'));

      expect(styledWith, isEmpty);
      expect(await vault.db.select(vault.db.flashcards).get(), hasLength(3));
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

  test('de un documento procesado, del texto procesado y nunca de la fuente, '
      'sin fragmento (F41, decisión I)', () async {
    await vault.source('a', title: 'Roma', content: article);
    final process = ProcessSourceUseCase(vault.processed);
    expect((await process.passUnchanged('a')).isRight(), isTrue);
    final docId = processedDocumentIdFor('a');
    final page = (await vault.processed.partsOf(
      docId,
    )).getRight().toNullable()!.single;
    const edited =
        'Cartago fue destruida en el año 146. Aníbal cruzó los Alpes. '
        'Las guerras púnicas fueron tres.';
    await vault.processed.editPart(page.id, edited);
    final document = (await vault.library.findById(
      docId,
    )).getRight().toNullable()!;

    final report = await step.organize(
      document,
      runId: await vault.startRun(docId),
    );

    final cards = await vault.db.select(vault.db.flashcards).get();
    expect(report.applied, cards.length);
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.itemId, docId);
      expect(edited, contains(card.back));
      expect(article, isNot(contains(card.back)));
      expect(card.sourceCharStart, isNull);
      expect(card.sourceCharEnd, isNull);
    }
  });

  test(
    'un procesado con solo palabras clave da tarjetas de sus oraciones',
    () async {
      await insertProcessedRows(
        vault.db,
        id: 'claves',
        title: 'Roma',
        parts: {
          ProcessedSection.keywords: [article],
        },
      );
      final document = (await vault.library.findById(
        'claves',
      )).getRight().toNullable()!;

      final report = await step.organize(
        document,
        runId: await vault.startRun('claves'),
      );

      final cards = await vault.db.select(vault.db.flashcards).get();
      expect(cards, isNotEmpty);
      expect(report.applied, cards.length);
      for (final card in cards) {
        expect(card.itemId, 'claves');
        expect(article, contains(card.back));
        expect(card.sourceCharStart, isNull);
      }
    },
  );

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
    expect(model.contents.every((c) => c.length <= budget.partChars), isTrue);
    expect(model.counts.every((c) => c <= budget.maxDraftsPerCall), isTrue);
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

  group('con un modelo de ventana grande (F32)', () {
    String bookOf(String tag) => [
      for (var i = 0; i < 4000; i++) 'La idea $tag número $i es esta.',
    ].join(' ');

    test('lee partes de un capítulo y pide más tarjetas por pedido: las '
        'mismas doce con menos pedidos', () async {
      budget = textBudgetFor(1048576);
      final book = bookOf('a');
      final item = await vault.source('libro', title: 'Libro', content: book);

      final report = await step.organize(
        item,
        runId: await vault.startRun('libro'),
      );

      expect(report.applied, 12);
      expect(model.contents, hasLength(3));
      // Unos 123.000 caracteres: dos capítulos casi del tope, y lo que sobra.
      expect(model.contents.every((c) => c.length <= kMaxPartChars), isTrue);
      expect(
        model.contents.take(2).every((c) => c.length > kMaxPartChars * 0.9),
        isTrue,
      );
      expect(
        model.counts.every((c) => c > kSmallWindowTextBudget.maxDraftsPerCall),
        isTrue,
      );
    });

    test('pregunta cuánto lee el modelo en cada elemento: cambiar de modelo '
        'vale desde el siguiente', () async {
      final first = await vault.source(
        'uno',
        title: 'Uno',
        content: bookOf('a'),
      );
      await step.organize(first, runId: await vault.startRun('uno'));
      expect(model.contents, hasLength(6));

      budget = textBudgetFor(1048576);
      model.contents.clear();
      final second = await vault.source(
        'dos',
        title: 'Dos',
        content: bookOf('b'),
      );
      await step.organize(second, runId: await vault.startRun('dos'));
      expect(model.contents, hasLength(3));
    });
  });
}
