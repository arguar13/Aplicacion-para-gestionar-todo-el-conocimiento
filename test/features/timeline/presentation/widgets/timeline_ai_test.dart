import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_dates_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_events_painter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/library_harness.dart';

/// «Organizar con IA» en la línea de tiempo (F40): qué se puede elegir, qué le
/// pide a la cola de la IA, cómo se ve el avance y qué dice cuando la IA no
/// puede trabajar todavía.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeAiOrganizeQueue queue;

  final now = DateTime(2026, 9, 11, 10);

  Future<void> create({
    bool modelsReady = true,
    LanguageModelStatus? cloud,
  }) async {
    queue = FakeAiOrganizeQueue();
    harness = await LibraryHarness.create(
      chatModelReady: modelsReady,
      embeddingModelReady: modelsReady,
      extraOverrides: [
        aiOrganizeQueueProvider.overrideWithValue(queue),
        if (cloud != null)
          languageModelStatusCheckProvider.overrideWithValue(
            ({bool background = false}) async => cloud,
          ),
      ],
    );
  }

  Future<void> seed(
    String id, {
    String? title,
    ProcessingState state = ProcessingState.ready,
    SourceKind kind = SourceKind.webPage,
  }) => harness.container
      .read(libraryRepositoryProvider)
      .save(
        KnowledgeItem(
          id: id,
          title: title ?? 'Doc $id',
          source: Source(
            id: 'src-$id',
            kind: kind,
            capturedAt: now,
            url: kind == SourceKind.manualNote ? null : 'https://e.org/$id',
          ),
          processingState: state,
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// Un tema con esos elementos adentro; devuelve su id.
  Future<String> space(String name, List<String> itemIds) async {
    final created =
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: itemIds, spaceIds: {created.id});
    return created.id;
  }

  GoRouter router() => GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TimelineScreen()),
      GoRoute(
        path: RoutePaths.aiActivity,
        builder: (_, state) => Scaffold(
          body: Text(
            'actividad: ${state.uri.queryParameters['item'] ?? 'todo'}',
          ),
        ),
      ),
    ],
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('timeline-ai-action')));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('timeline-ai-start')));
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String key) {
    final tile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(ListTile),
      ),
    );
    return tile.selected;
  }

  group('la acción', () {
    testWidgets('está en la barra de la línea, con su nombre', (tester) async {
      await create();
      await pumpScreen(tester);

      expect(find.byKey(const Key('timeline-ai-action')), findsOneWidget);
      expect(find.byTooltip(es.timelineAiAction), findsOneWidget);
    });

    testWidgets('abre la hoja: qué hace y tres opciones, con «Todo» '
        'elegido', (tester) async {
      await create();
      await pumpScreen(tester);

      await openSheet(tester);

      expect(find.text(es.timelineAiAction), findsWidgets);
      expect(find.text(es.timelineAiSheetHint), findsOneWidget);
      expect(selected(tester, 'timeline-ai-all'), isTrue);
      expect(selected(tester, 'timeline-ai-topic'), isFalse);
      expect(selected(tester, 'timeline-ai-document'), isFalse);
      expect(find.text(es.timelineAiScopeAllHint), findsOneWidget);
      expect(find.text(es.timelineAiScopeTopicHint), findsOneWidget);
      expect(find.text(es.timelineAiScopeDocumentHint), findsOneWidget);
      // Una rama del Atlas no se elige acá.
      expect(find.byKey(const ValueKey('timeline-ai-branch')), findsNothing);
    });

    testWidgets('cerrar la hoja sin elegir no pide nada', (tester) async {
      await create();
      await seed('a');
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tapAt(const Offset(450, 20));
      await tester.pumpAndSettle();

      expect(queue.dateRequests, isEmpty);
      expect(find.text(es.timelineAiSheetHint), findsNothing);
    });
  });

  group('todo', () {
    testWidgets('pide las fechas de todo lo que está listo, y de nada más', (
      tester,
    ) async {
      await create();
      await seed('a');
      await seed('b', kind: SourceKind.manualNote);
      await seed('procesando', state: ProcessingState.processing);
      await seed('fallido', state: ProcessingState.failed);
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(queue.dateRequests.single.toSet(), {'a', 'b'});
      // No pidió organizarlo entero.
      expect(queue.organizeNowCalls, isEmpty);
      expect(find.text(es.datesAskQueued(2)), findsOneWidget);
      // La hoja se cerró antes de pedirlo.
      expect(find.text(es.timelineAiSheetHint), findsNothing);
    });

    testWidgets('con la biblioteca vacía, avisa que no hay nada para '
        'recorrer', (tester) async {
      await create();
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(queue.dateRequests, isEmpty);
      expect(find.text(es.timelineAiNothing), findsOneWidget);
    });
  });

  group('un tema', () {
    testWidgets('elegirlo en la hoja de temas lo deja marcado, con su '
        'nombre', (tester) async {
      await create();
      await seed('a');
      await space('Historia', ['a']);
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historia'));
      await tester.pumpAndSettle();

      expect(selected(tester, 'timeline-ai-topic'), isTrue);
      expect(selected(tester, 'timeline-ai-all'), isFalse);
      expect(find.text('Historia'), findsOneWidget);
    });

    testWidgets('pide solo lo que está en ese tema', (tester) async {
      await create();
      await seed('a');
      await seed('b');
      await seed('c');
      await space('Historia', ['a', 'b']);
      await space('Física', ['c']);
      await pumpScreen(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historia'));
      await tester.pumpAndSettle();

      await start(tester);

      expect(queue.dateRequests.single.toSet(), {'a', 'b'});
      expect(find.text(es.datesAskQueued(2)), findsOneWidget);
    });

    testWidgets('un tema sin nada listo: avisa y no pide', (tester) async {
      await create();
      await seed('a', state: ProcessingState.processing);
      await space('Historia', ['a']);
      await pumpScreen(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historia'));
      await tester.pumpAndSettle();

      await start(tester);

      expect(queue.dateRequests, isEmpty);
      expect(find.text(es.timelineAiNothing), findsOneWidget);
    });

    testWidgets('cerrar la hoja de temas sin elegir deja lo que estaba, '
        'sea lo que sea', (tester) async {
      await create();
      await seed('a', title: 'Darwin');
      await space('Historia', ['a']);
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(const TimelineScope.document(itemId: 'a', label: 'Darwin'));
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(450, 20));
      await tester.pumpAndSettle();

      expect(selected(tester, 'timeline-ai-document'), isTrue);
      expect(selected(tester, 'timeline-ai-all'), isFalse);
    });

    testWidgets('cerrar la hoja de temas sin elegir deja lo que estaba', (
      tester,
    ) async {
      await create();
      await seed('a');
      await space('Historia', ['a']);
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(450, 20));
      await tester.pumpAndSettle();

      expect(selected(tester, 'timeline-ai-all'), isTrue);
      expect(selected(tester, 'timeline-ai-topic'), isFalse);
    });
  });

  group('un documento', () {
    testWidgets('la hoja lista cualquiera de la biblioteca, con fechas o '
        'sin ellas, y deja afuera lo que no está listo', (tester) async {
      await create();
      await seed('a', title: 'Biografía de Darwin');
      await seed('b', title: 'Una receta');
      await seed(
        'c',
        title: 'Todavía procesando',
        state: ProcessingState.processing,
      );
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-document')));
      await tester.pumpAndSettle();

      expect(find.text('Biografía de Darwin'), findsOneWidget);
      expect(find.text('Una receta'), findsOneWidget);
      expect(find.text('Todavía procesando'), findsNothing);
    });

    testWidgets('la hoja tiene su buscador', (tester) async {
      await create();
      await seed('a', title: 'Biografía de Darwin');
      await seed('b', title: 'Una receta');
      await pumpScreen(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('timeline-ai-document')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'darwín',
      );
      await tester.pumpAndSettle();

      expect(find.text('Biografía de Darwin'), findsOneWidget);
      expect(find.text('Una receta'), findsNothing);
    });

    testWidgets('pide las fechas de ese documento y de ningún otro', (
      tester,
    ) async {
      await create();
      await seed('a', title: 'Biografía de Darwin');
      await seed('b', title: 'Una receta');
      await pumpScreen(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('timeline-ai-document')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biografía de Darwin'));
      await tester.pumpAndSettle();
      expect(selected(tester, 'timeline-ai-document'), isTrue);

      await start(tester);

      expect(queue.dateRequests, [
        ['a'],
      ]);
      expect(find.text(es.datesAskQueued(1)), findsOneWidget);
    });

    testWidgets('con la biblioteca vacía, la hoja lo dice', (tester) async {
      await create();
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-document')));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineAiDocumentsEmpty), findsOneWidget);
    });
  });

  group('el recorte que la línea ya tiene viene elegido', () {
    testWidgets('un tema', (tester) async {
      await create();
      await seed('a');
      await seed('b');
      final topic = await space('Historia', ['a']);
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(TimelineScope.topic(spaceId: topic, label: 'Historia'));
      await pumpScreen(tester);

      await openSheet(tester);

      expect(selected(tester, 'timeline-ai-topic'), isTrue);
      expect(find.text('Historia'), findsWidgets);
      await start(tester);
      expect(queue.dateRequests, [
        ['a'],
      ]);
    });

    testWidgets('un documento', (tester) async {
      await create();
      await seed('a', title: 'Darwin');
      await seed('b');
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(const TimelineScope.document(itemId: 'a', label: 'Darwin'));
      await pumpScreen(tester);

      await openSheet(tester);

      expect(selected(tester, 'timeline-ai-document'), isTrue);
      await start(tester);
      expect(queue.dateRequests, [
        ['a'],
      ]);
    });

    testWidgets('una rama del Atlas: aparece como una opción más y se '
        'recorre solo lo que tiene ese valor', (tester) async {
      await create();
      await seed('a');
      await seed('b');
      final fecha =
          (await (harness.database.select(harness.database.propertyDefinitions)
                    ..where(
                      (d) =>
                          d.isSystem.equals(true) &
                          d.name.equals(kFechaDelHechoCategoryName),
                    ))
                  .getSingle())
              .id;
      final organize = harness.container.read(organizeRepositoryProvider);
      final value = (await organize.getOrCreateHistoricalPropertyValue(
        definitionId: fecha,
        date: const HistoricalDate(year: 1809, precision: DatePrecision.year),
      )).getRight().toNullable()!;
      await organize.assignProperty(
        itemId: 'a',
        definitionId: fecha,
        value: value.value,
      );
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(TimelineScope.branch(valueId: value.id, label: '1809'));
      await pumpScreen(tester);

      await openSheet(tester);

      expect(selected(tester, 'timeline-ai-branch'), isTrue);
      expect(find.text(es.timelineAiScopeBranchHint), findsOneWidget);
      await start(tester);
      expect(queue.dateRequests, [
        ['a'],
      ]);
    });

    testWidgets('se puede cambiar a «Todo» y pedir toda la biblioteca', (
      tester,
    ) async {
      await create();
      await seed('a');
      await seed('b');
      final topic = await space('Historia', ['a']);
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(TimelineScope.topic(spaceId: topic, label: 'Historia'));
      await pumpScreen(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-ai-all')));
      await tester.pumpAndSettle();
      await start(tester);

      expect(queue.dateRequests.single.toSet(), {'a', 'b'});
    });

    testWidgets('recorrer un tema no cambia lo que la línea está mostrando', (
      tester,
    ) async {
      await create();
      await seed('a');
      final topic = await space('Historia', ['a']);
      await pumpScreen(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('timeline-ai-topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historia'));
      await tester.pumpAndSettle();

      await start(tester);

      expect(topic, isNotEmpty);
      expect(harness.container.read(timelineFilterProvider).scope, isNull);
    });
  });

  group('sin la IA lista', () {
    testWidgets('sin el modelo de lenguaje, lo pide igual y dice que falta '
        'bajarlo', (tester) async {
      await create(modelsReady: false);
      await seed('a');
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskNeedsModel(1)), findsOneWidget);
    });

    testWidgets('con la IA en pausa, lo pide igual y dice cuándo sigue', (
      tester,
    ) async {
      await create();
      await seed('a');
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(queue.dateRequests, hasLength(1));
      expect(find.text(es.datesAskPaused(1)), findsOneWidget);
    });

    testWidgets('sin clave de la nube, dice que falta la clave', (
      tester,
    ) async {
      await create(
        cloud: const LanguageModelNeedsAccount(provider: AiProvider.gemini),
      );
      await seed('a');
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(find.text(es.datesAskNeedsKey(1)), findsOneWidget);
    });

    testWidgets('sin cuota, dice que espera', (tester) async {
      await create(
        cloud: LanguageModelOutOfQuota(
          provider: AiProvider.gemini,
          accounts: 1,
          resetsAt: DateTime(2026, 10, 17, 4),
        ),
      );
      await seed('a');
      await pumpScreen(tester);
      await openSheet(tester);

      await start(tester);

      expect(find.text(es.datesAskWaits(1)), findsOneWidget);
    });
  });

  group('«Ver» del aviso', () {
    testWidgets('de todo, abre lo que hizo la IA', (tester) async {
      await create();
      await seed('a');
      await pumpScreen(tester);
      await openSheet(tester);
      await start(tester);

      await tester.tap(find.text(es.aiItemLineSee));
      await tester.pumpAndSettle();

      expect(find.text('actividad: todo'), findsOneWidget);
    });

    testWidgets('de un documento, abre lo que hizo la IA con ese '
        'elemento', (tester) async {
      await create();
      await seed('a', title: 'Darwin');
      harness.container
          .read(timelineFilterProvider.notifier)
          .focusOn(const TimelineScope.document(itemId: 'a', label: 'Darwin'));
      await pumpScreen(tester);
      await openSheet(tester);
      await start(tester);

      await tester.tap(find.text(es.aiItemLineSee));
      await tester.pumpAndSettle();

      expect(find.text('actividad: a'), findsOneWidget);
    });
  });

  testWidgets('un documento elegido que todavía se procesa no se recorre', (
    tester,
  ) async {
    await create();
    await seed('a', title: 'Darwin', state: ProcessingState.processing);
    harness.container
        .read(timelineFilterProvider.notifier)
        .focusOn(const TimelineScope.document(itemId: 'a', label: 'Darwin'));
    await pumpScreen(tester);
    await openSheet(tester);

    await start(tester);

    expect(queue.dateRequests, isEmpty);
    expect(find.text(es.timelineAiNothing), findsOneWidget);
  });

  testWidgets('la hoja de documentos los ordena por título', (tester) async {
    await create();
    await seed('a', title: 'Zorro');
    await seed('b', title: 'Alfa');
    await pumpScreen(tester);
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('timeline-ai-document')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alfa')).dy,
      lessThan(tester.getTopLeft(find.text('Zorro')).dy),
    );
  });

  testWidgets('terminado, no habla de la pausa aunque la IA esté en '
      'pausa', (tester) async {
    await create();
    await harness.container
        .read(aiOrganizeSettingsProvider.notifier)
        .set(AiOrganizeToggle.enabled, on: false);
    await pumpScreen(tester);

    harness.container.read(aiDatesBatchProvider.notifier).state =
        const AiDatesBatch(total: 1, done: 1, created: 2);
    await tester.pumpAndSettle();

    expect(find.text(es.timelineAiDone), findsOneWidget);
    expect(find.text(es.reviewAiBatchAiPaused), findsNothing);
    expect(find.byKey(const Key('timeline-ai-resume')), findsNothing);
  });

  testWidgets('al terminar, el lector de pantalla lo anuncia solo; mientras '
      'corre, no', (tester) async {
    final semantics = tester.ensureSemantics();
    await create();
    await pumpScreen(tester);
    bool isLive() => tester
        .getSemantics(find.byKey(const Key('timeline-ai-progress')))
        .getSemanticsData()
        .flagsCollection
        .isLiveRegion;

    harness.container.read(aiDatesBatchProvider.notifier).state =
        const AiDatesBatch(total: 2, done: 1);
    await tester.pumpAndSettle();
    expect(isLive(), isFalse);

    harness.container.read(aiDatesBatchProvider.notifier).state =
        const AiDatesBatch(total: 2, done: 2, created: 3);
    await tester.pumpAndSettle();
    expect(isLive(), isTrue);
    semantics.dispose();
  });

  group('el avance, en la propia línea', () {
    void setBatch(AiDatesBatch? batch) =>
        harness.container.read(aiDatesBatchProvider.notifier).state = batch;

    testWidgets('sin pedido no ocupa lugar', (tester) async {
      await create();
      await pumpScreen(tester);

      expect(find.byKey(const Key('timeline-ai-progress')), findsNothing);
    });

    testWidgets('mientras corre dice cuántos elementos van, cuántas fechas '
        'salieron y puede cancelarse', (tester) async {
      await create();
      await pumpScreen(tester);

      setBatch(
        const AiDatesBatch(
          total: 4,
          done: 1,
          created: 3,
          currentTitle: 'Darwin',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('timeline-ai-progress')), findsOneWidget);
      expect(find.text(es.timelineAiWorking), findsOneWidget);
      expect(
        find.text(
          '${es.reviewAiBatchProgress(1, 4)} · ${es.timelineAiFound(3)}',
        ),
        findsOneWidget,
      );
      expect(find.text(es.reviewAiBatchCurrent('Darwin')), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('timeline-ai-progress-bar')),
      );
      expect(bar.value, 0.25);

      await tester.tap(find.byKey(const Key('timeline-ai-cancel')));
      await tester.pump();
      expect(queue.datesCancelled, 1);
    });

    testWidgets('al terminar queda el resultado, sin barra, hasta cerrarlo', (
      tester,
    ) async {
      await create();
      await pumpScreen(tester);

      setBatch(const AiDatesBatch(total: 2, done: 2, created: 5));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineAiDone), findsOneWidget);
      expect(find.text(es.timelineAiFound(5)), findsOneWidget);
      expect(find.byKey(const Key('timeline-ai-progress-bar')), findsNothing);
      expect(find.byKey(const Key('timeline-ai-cancel')), findsNothing);

      await tester.tap(find.byKey(const Key('timeline-ai-dismiss')));
      await tester.pump();
      expect(queue.datesDismissed, 1);
    });

    testWidgets('sin ninguna fecha nueva, lo dice', (tester) async {
      await create();
      await pumpScreen(tester);

      setBatch(const AiDatesBatch(total: 1, done: 1));
      await tester.pumpAndSettle();

      expect(find.text(es.timelineAiFound(0)), findsOneWidget);
    });

    testWidgets('con la IA en pausa lo dice y ofrece reanudarla', (
      tester,
    ) async {
      await create();
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await pumpScreen(tester);

      setBatch(const AiDatesBatch(total: 3));
      await tester.pumpAndSettle();

      expect(find.text(es.reviewAiBatchAiPaused), findsOneWidget);
      await tester.tap(find.byKey(const Key('timeline-ai-resume')));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiOrganizeSettingsProvider).enabled,
        isTrue,
      );
      expect(find.byKey(const Key('timeline-ai-resume')), findsNothing);
    });

    testWidgets('el pedido sale de la vista cuando se cierra', (tester) async {
      await create();
      await pumpScreen(tester);
      setBatch(const AiDatesBatch(total: 1, done: 1));
      await tester.pumpAndSettle();

      setBatch(null);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('timeline-ai-progress')), findsNothing);
    });

    testWidgets('los hechos nuevos aparecen solos en el eje, sin recargar', (
      tester,
    ) async {
      await create();
      await seed('a', title: 'Darwin');
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('timeline-events')), findsNothing);

      final runs = harness.container.read(aiRunRepositoryProvider);
      final run = (await runs.startRun('a')).getRight().toNullable()!;
      await harness.container
          .read(datedEventRepositoryProvider)
          .addFromAi(
            itemId: 'a',
            runId: run,
            drafts: [
              const DatedEventInput(
                title: 'Nace Darwin',
                date: HistoricalDate(year: 1809, precision: DatePrecision.year),
                excerpt: 'nació en 1809',
              ),
            ],
          );
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('timeline-events'));
      expect(canvas, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(canvas).painter! as TimelineEventsPainter;
      expect(painter.frame.boxes.map((b) => b.event.title), ['Nace Darwin']);
    });
  });
}
