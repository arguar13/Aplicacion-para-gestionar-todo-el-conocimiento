import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_review_switch_offer.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_review_queue.dart';
import '../../../../support/library_harness.dart';
import '../fake_ai_run_repository.dart';

/// El aviso al cambiar a un modelo más capaz (F33, decisión D): una vez por
/// modelo, cuando está listo y tiene algo de uno menos capaz para revisar.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeAiRunRepository runs;
  late FakeAiReviewQueue queue;
  final reviewer = StateProvider<String>((ref) => 'gemini-3.8-flash');
  final status = StateProvider<LanguageModelStatus>(
    (ref) => const LanguageModelReady(provider: AiProvider.gemini),
  );

  setUp(() async {
    runs = FakeAiRunRepository()
      ..work = const [
        AiModelWork(model: 'gemma4E4b', things: 312, items: 85),
        AiModelWork(model: 'gemini-3.8-pro', things: 4, items: 1),
      ]
      ..candidates = const [AiReviewCandidate(itemId: 'a', cards: 3)];
    queue = FakeAiReviewQueue();
    harness = await LibraryHarness.create(
      extraOverrides: [
        aiRunRepositoryProvider.overrideWithValue(runs),
        aiReviewQueueProvider.overrideWithValue(queue),
        aiReviewerNameProvider.overrideWith((ref) => ref.watch(reviewer)),
        languageModelStatusProvider.overrideWith(
          (ref) async => ref.watch(status),
        ),
        languageModelTextBudgetProvider.overrideWithValue(
          () => kSmallWindowTextBudget,
        ),
      ],
    );
  });

  Future<void> pump(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiReviewSwitchOfferListener(
            navigatorKey: navigatorKey,
            child: const Scaffold(body: Text('biblioteca')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final title = es.aiRecheckSwitchTitle('Gemini 3.8 Flash');

  testWidgets('con un modelo más capaz y listo, ofrece revisar lo del '
      'anterior —el de más cosas que sea menos capaz—', (tester) async {
    await pump(tester);

    expect(find.text(title), findsOneWidget);
    expect(
      find.text(
        es.aiRecheckSwitchBody(
          'Gemma 4 E4B',
          es.aiRecheckThings(312),
          es.aiRecheckItems(85),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(es.aiRecheckWith('Gemini 3.8 Flash')), findsOneWidget);
  });

  testWidgets('«No, gracias» lo cierra, y para ese modelo no vuelve a salir', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ai-review-switch-later')));
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(queue.requests, isEmpty);

    // La app vuelta a abrir, con lo mismo para revisar.
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.text(title), findsNothing);
  });

  testWidgets('«Revisar con …» empieza por el costo, solo con lo del modelo '
      'anterior', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ai-review-switch-review')));
    await tester.pumpAndSettle();

    expect(runs.candidateQueries, [
      (reviewer: 'gemini-3.8-flash', madeBy: 'gemma4E4b', itemId: null),
    ]);
    await tester.tap(find.byKey(const Key('ai-review-cost-start')));
    await tester.pumpAndSettle();
    expect(queue.requests.single.itemIds, ['a']);
    expect(queue.requests.single.skipOwnWork, isTrue);
  });

  testWidgets('espera a que el modelo esté listo: no mientras la persona '
      'todavía carga la clave', (tester) async {
    harness.container.read(status.notifier).state =
        const LanguageModelNeedsAccount(provider: AiProvider.gemini);
    await pump(tester);
    expect(find.text(title), findsNothing);

    harness.container.read(status.notifier).state = const LanguageModelReady(
      provider: AiProvider.gemini,
    );
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('al cambiar de modelo: una vez por cada uno', (tester) async {
    harness.container.read(reviewer.notifier).state = 'gemma4E4b';
    await pump(tester);
    // Gemma no es más capaz que nada de lo hecho.
    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);

    harness.container.read(reviewer.notifier).state = 'gemini-3.8-flash';
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-review-switch-later')));
    await tester.pumpAndSettle();

    harness.container.read(reviewer.notifier).state = 'gemini-3.8-pro';
    await tester.pumpAndSettle();
    expect(
      find.text(es.aiRecheckSwitchTitle('Gemini 3.8 Pro')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('ai-review-switch-later')));
    await tester.pumpAndSettle();

    harness.container.read(reviewer.notifier).state = 'gemini-3.8-flash';
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);
  });

  testWidgets('a otro proveedor no avisa: no se sabe si es más capaz, y '
      'queda el botón', (tester) async {
    runs.work = const [
      AiModelWork(model: 'gemini-3.8-pro', things: 4, items: 1),
    ];
    harness.container.read(reviewer.notifier).state = 'claude-sonnet-5';
    await pump(tester);

    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);
    // Ni lo da por ofrecido: si después elige uno más capaz, avisa.
    expect(
      harness.container
          .read(aiReviewSwitchOffersProvider)
          .wasOffered('claude-sonnet-5'),
      isFalse,
    );
  });

  testWidgets('sin nada de un modelo menos capaz, no avisa', (tester) async {
    runs.work = const [];
    await pump(tester);

    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);
  });

  testWidgets('con una revisión a la vista, no avisa', (tester) async {
    harness.container.read(aiReviewBatchProvider.notifier).state =
        const AiReviewBatch(done: 1, total: 3);
    await pump(tester);

    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);
  });

  testWidgets('al cambiar, no avisa con lo que se contó para el modelo de '
      'antes, mientras se vuelve a contar', (tester) async {
    // Para Gemma queda lo de Gemini Flash Lite; para Gemini Flash, nada.
    runs.work = const [
      AiModelWork(model: 'gemini-3.8-flash-lite', things: 7, items: 2),
    ];
    harness.container.read(reviewer.notifier).state = 'gemma4E4b';
    await pump(tester);

    runs.work = const [];
    harness.container.read(reviewer.notifier).state = 'gemini-3.8-flash';
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-review-switch-later')), findsNothing);
  });
}
