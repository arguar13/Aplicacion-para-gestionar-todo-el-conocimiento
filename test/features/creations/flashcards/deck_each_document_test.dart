import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_usage_bar.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/deck_each_document.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/processed_rows.dart';
import '../presentation/repasar_harness.dart';

/// Un pedido de «Para cada documento» que recibió la cola.
typedef _Request = ({
  List<String> ids,
  bool anotherBatch,
  FlashcardStyle style,
});

/// La cola de la IA de mentira: anota lo que la hoja le pide. Cómo hace las
/// tarjetas lo prueba `ai_organize_queue_test.dart`.
class _RecordingQueue implements AiOrganizeQueue {
  final requests = <_Request>[];

  @override
  void makeFlashcards(
    Iterable<String> itemIds, {
    bool anotherBatch = false,
    FlashcardStyle style = FlashcardStyle.plain,
  }) => requests.add((
    ids: itemIds.toList(),
    anotherBatch: anotherBatch,
    style: style,
  ));

  // Lo que el resto de la app le avisa a la cola, sin nada que hacer acá.
  @override
  void enqueueProcessedForOrganizing(String documentId) {}

  @override
  Future<void> start() async {}

  @override
  Future<void> wake() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// «Cómo» en la hoja de «Tarjetas didácticas» (F43, M18, decisión O): con
/// varios documentos, un mazo o «Para cada documento», que es lo que hacía
/// el ✨ de la barra de Repasar (F30) sobre lo procesado.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;
  late _RecordingQueue queue;
  late LanguageModelStatus status;

  setUp(() async {
    queue = _RecordingQueue();
    status = const LanguageModelReady(provider: AiProvider.gemini);
    final specs = ProviderContainer();
    addTearDown(specs.dispose);
    harness = await RepasarHarness.create(
      specs: [specs.read(flashcardsKindSpecProvider)],
      overrides: [
        aiOrganizeQueueProvider.overrideWithValue(queue),
        languageModelStatusProvider.overrideWith((ref) async => status),
      ],
    );
    // Tres con texto, uno de ellos ya con tarjetas, y uno sin nada que leer.
    await harness.processed('p-1', 'Éxodo');
    await harness.processed('p-2', 'Génesis', cards: 1);
    await harness.processed('p-3', 'Levítico');
    await insertProcessedRows(
      harness.library.database,
      id: 'p-4',
      title: 'Fotos del viaje',
      parts: const {},
    );
  });

  Future<void> openSheet(WidgetTester tester) async {
    final tile = find.byKey(
      ValueKey('creation-kind-${StudyCreationKind.flashcards.storageKey}'),
    );
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder optionFinder(String key) =>
      find.byKey(ValueKey('creation-option-$key'));

  Future<void> chooseEach(WidgetTester tester) =>
      tapInSheet(tester, find.byKey(const ValueKey('creation-how-each')));

  FilledButton startButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('deck-each-start')));

  group('la pregunta', () {
    testWidgets('con varios documentos pregunta «Cómo», y abre en «Un mazo», '
        'que es lo de siempre', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester);

      expect(find.text(es.f43S21How), findsOneWidget);
      expect(find.text(es.f43S21HowOne), findsOneWidget);
      expect(find.text(es.f43S21HowEach), findsOneWidget);
      expect(find.byKey(const Key('creation-generate-now')), findsOneWidget);
      expect(find.byKey(const Key('deck-each-start')), findsNothing);

      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(harness.queue.requests.single.kind, StudyCreationKind.flashcards);
      expect(queue.requests, isEmpty);
    });

    testWidgets('con un solo documento no hay pregunta: es un mazo', (
      tester,
    ) async {
      harness.container.read(repasarScopeProvider.notifier).state =
          const CreationScope.document('p-1');
      await harness.openRepasar(tester);
      await openSheet(tester);

      expect(find.text(es.f43S21How), findsNothing);
      expect(find.byKey(const Key('creation-generate-now')), findsOneWidget);
    });

    testWidgets('destildar hasta dejar uno vuelve a un mazo', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester);
      await chooseEach(tester);
      expect(find.byKey(const Key('deck-each-start')), findsOneWidget);

      await tapInSheet(
        tester,
        find.byKey(const Key('creation-sources-toggle')),
      );
      for (final id in ['p-2', 'p-3', 'p-4']) {
        await tapInSheet(
          tester,
          find.byKey(ValueKey('creation-source-option-$id')),
        );
      }

      expect(find.text(es.f43S21How), findsNothing);
      expect(find.byKey(const Key('deck-each-start')), findsNothing);
      expect(find.byKey(const Key('creation-generate-now')), findsOneWidget);
    });
  });

  group('«Para cada documento»', () {
    testWidgets('cuenta los que entran y los que ya tienen; pide solo los que '
        'no tienen, con la cola de la IA y sin fila en «Lo creado»', (
      tester,
    ) async {
      await harness.openRepasar(tester);
      await openSheet(tester);
      await chooseEach(tester);

      expect(find.byKey(const Key('creation-how-each-hint')), findsOneWidget);
      // Lo de un mazo no va: las de cada documento entran siempre al repaso.
      expect(optionFinder(CreationOptionValues.images), findsNothing);
      expect(optionFinder('addToReview'), findsNothing);
      // Lo que vale para los dos, sí.
      expect(
        find.byKey(const ValueKey('creation-option-count-more')),
        findsOneWidget,
      );
      // «Uso de IA» estima un mazo: acá no.
      expect(find.byType(AiUsageBar), findsNothing);
      expect(find.byKey(const Key('creation-generate-later')), findsNothing);

      expect(find.text(es.f43S21Coverage(3)), findsOneWidget);
      expect(find.text(es.reviewAiCoverageWithCards(1)), findsOneWidget);
      expect(find.text(es.f43S21Start(2)), findsOneWidget);

      await tapInSheet(tester, find.byKey(const Key('deck-each-start')));

      final request = queue.requests.single;
      expect(request.ids.toSet(), {'p-1', 'p-3'});
      expect(request.anotherBatch, isFalse);
      expect(
        request.style,
        const FlashcardStyle(difficulty: FlashcardDifficulty.medium),
      );
      expect(harness.queue.requests, isEmpty);
      expect(find.byKey(const Key('creation-sheet')), findsNothing);
      expect(find.text(es.reviewAiStarted), findsOneWidget);
    });

    testWidgets(
      '«También los que ya tienen tarjetas» pide todos los que tienen '
      'texto, con otra tanda',
      (tester) async {
        await harness.openRepasar(tester);
        await openSheet(tester);
        await chooseEach(tester);

        await tapInSheet(
          tester,
          find.byKey(const Key('deck-each-also-with-cards')),
        );
        expect(find.text(es.f43S21Start(3)), findsOneWidget);
        await tapInSheet(tester, find.byKey(const Key('deck-each-start')));

        final request = queue.requests.single;
        expect(request.ids.toSet(), {'p-1', 'p-2', 'p-3'});
        expect(request.anotherBatch, isTrue);
      },
    );

    testWidgets(
      'el idioma, el tema, el número y la dificultad van al pedido, y '
      'se recuerdan para la próxima',
      (tester) async {
        await harness.openRepasar(tester);
        await openSheet(tester);
        await chooseEach(tester);

        await tapInSheet(
          tester,
          find.byKey(const ValueKey('creation-option-count-more')),
        );
        await tapInSheet(
          tester,
          find.byKey(const ValueKey('creation-option-difficulty-hard')),
        );
        await tapInSheet(tester, find.byKey(const Key('creation-language')));
        await tester.tap(find.byKey(const ValueKey('picker-item-en')).last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('creation-topic')),
          '  Moisés y Faraón ',
        );
        await tapInSheet(tester, find.byKey(const Key('deck-each-start')));

        expect(
          queue.requests.single.style,
          const FlashcardStyle(
            languageCode: 'en',
            difficulty: FlashcardDifficulty.hard,
            topic: 'Moisés y Faraón',
            amount: FlashcardAmount.more,
          ),
        );

        // La próxima vez abre con lo elegido, en un mazo.
        await openSheet(tester);
        await tapInSheet(
          tester,
          find.byKey(const Key('creation-generate-now')),
        );
        final deck = harness.queue.requests.single;
        expect(
          deck.options[CreationOptionValues.count],
          CreationOptionValues.more,
        );
        expect(deck.languageCode, 'en');
      },
    );

    testWidgets('sin el modelo de lenguaje no se puede, y ofrece bajarlo', (
      tester,
    ) async {
      status = const LanguageModelNeedsDownload();
      await harness.openRepasar(tester);
      await openSheet(tester);
      await chooseEach(tester);

      expect(find.text(es.flashcardsModelMissing), findsOneWidget);
      expect(startButton(tester).onPressed, isNull);
    });

    testWidgets('sin ninguno que pedir, el botón lo dice y no hace nada', (
      tester,
    ) async {
      await harness.openRepasar(tester);
      await openSheet(tester);
      // Solo los dos que no tienen texto o ya tienen tarjetas.
      await tapInSheet(
        tester,
        find.byKey(const Key('creation-sources-toggle')),
      );
      for (final id in ['p-1', 'p-3']) {
        await tapInSheet(
          tester,
          find.byKey(ValueKey('creation-source-option-$id')),
        );
      }
      await chooseEach(tester);

      expect(find.text(es.f43S21Coverage(1)), findsOneWidget);
      expect(find.text(es.f43S21Start(0)), findsOneWidget);
      expect(startButton(tester).onPressed, isNull);
    });

    for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
      testWidgets('en un teléfono de 360 dp con la letra al doble, en '
          '${theme.name}, entra sin cortarse y se lee entero', (tester) async {
        final semantics = tester.ensureSemantics();
        await harness.openRepasar(
          tester,
          size: const Size(360, 800),
          theme: theme,
          textScale: 2,
        );
        await openSheet(tester);
        await chooseEach(tester);
        await tester.ensureVisible(find.byKey(const Key('deck-each-coverage')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final label = tester
            .getSemantics(find.byKey(const Key('deck-each-coverage')))
            .label;
        expect(label, contains(es.f43S21Coverage(3)));
        expect(label, contains(es.reviewAiCoverageWithCards(1)));
        await tapInSheet(tester, find.byKey(const Key('deck-each-start')));
        expect(queue.requests, hasLength(1));
        semantics.dispose();
      });
    }
  });

  test('lo elegido en la hoja, dicho para la cola', () {
    expect(
      deckEachDocumentStyle(const {}, languageCode: 'es', topic: ''),
      const FlashcardStyle(difficulty: FlashcardDifficulty.medium),
    );
    expect(
      deckEachDocumentStyle(
        const {
          CreationOptionValues.count: CreationOptionValues.fewer,
          CreationOptionValues.difficulty: CreationOptionValues.easy,
        },
        languageCode: 'pt',
        topic: ' Alianza ',
      ),
      const FlashcardStyle(
        languageCode: 'pt',
        difficulty: FlashcardDifficulty.easy,
        topic: 'Alianza',
        amount: FlashcardAmount.fewer,
      ),
    );
    expect(deckEachDocument.onlyForOne, {
      CreationOptionValues.images,
      'addToReview',
    });
  });

  test('el tipo de las tarjetas didácticas ofrece «Cómo»; los demás, no', () {
    final specs = ProviderContainer();
    addTearDown(specs.dispose);
    expect(specs.read(flashcardsKindSpecProvider).eachDocument, isNotNull);
    expect(
      defaultCreationKindSpec(StudyCreationKind.quiz).eachDocument,
      isNull,
    );
    expect(
      const CreationKindSpec(
        kind: StudyCreationKind.mindMap,
        accent: CreationAccent(light: Colors.red, dark: Colors.red),
        sheetTitle: _title,
      ).copyWith(eachDocument: deckEachDocument).eachDocument,
      same(deckEachDocument),
    );
  });
}

String _title(AppLocalizations l10n) => l10n.f43S21How;
