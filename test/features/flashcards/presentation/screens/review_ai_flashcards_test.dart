import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La cola de la IA de mentira: anota lo que la pantalla le pide. Cómo hace
/// las tarjetas lo prueba `ai_organize_queue_test.dart`.
class _RecordingQueue implements AiOrganizeQueue {
  final requests = <({List<String> ids, bool anotherBatch})>[];
  final calls = <String>[];

  @override
  void makeFlashcards(Iterable<String> itemIds, {bool anotherBatch = false}) =>
      requests.add((ids: itemIds.toList(), anotherBatch: anotherBatch));

  @override
  void pauseFlashcards() => calls.add('pausar');

  @override
  void resumeFlashcards() => calls.add('seguir');

  @override
  void cancelFlashcards() => calls.add('cancelar');

  @override
  void dismissFlashcards() => calls.add('cerrar');

  // Lo que el resto de la app le avisa a la cola, sin nada que hacer acá.
  @override
  void itemProcessed(String itemId) {}

  @override
  Future<void> start() async {}

  @override
  Future<void> wake() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Repasar con IA (F30): el ✨ de la barra, la hoja que elige de qué y
/// cuenta, y el aviso de cómo va el pedido.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late _RecordingQueue queue;

  Future<void> setUpWith({bool modelReady = true}) async {
    queue = _RecordingQueue();
    harness = await LibraryHarness.create(
      chatModelReady: modelReady,
      extraOverrides: [aiOrganizeQueueProvider.overrideWithValue(queue)],
    );
  }

  /// Tres elementos con texto; el de [withCards], con una tarjeta.
  Future<Map<String, String>> seed({String? withCards}) async {
    for (final title in ['Roma', 'Cartago', 'Grecia']) {
      await harness.capture('$title\n\nTexto sobre $title.', title: title);
    }
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getOrElse((f) => fail('$f'));
    final ids = {for (final item in items) item.title: item.id};
    if (withCards != null) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: ids[withCards]!, front: '¿Qué?', back: 'Eso.');
    }
    return ids;
  }

  Future<void> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const ReviewScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('review-ai-create')));
    await tester.pumpAndSettle();
  }

  group('la hoja', () {
    testWidgets('de toda la biblioteca: cuántos entran y cuántos ya tienen; '
        'pide solo los que no tienen', (tester) async {
      await setUpWith();
      final ids = await seed(withCards: 'Roma');
      await pumpReview(tester);
      await openSheet(tester);

      expect(find.text(es.reviewAiSheetTitle), findsWidgets);
      expect(find.text(es.reviewAiCoverage(3)), findsOneWidget);
      expect(find.text(es.reviewAiCoverageWithCards(1)), findsOneWidget);

      await tester.tap(find.text(es.reviewAiStart(2)));
      await tester.pumpAndSettle();

      expect(queue.requests.single.anotherBatch, isFalse);
      expect(queue.requests.single.ids.toSet(), {
        ids['Cartago'],
        ids['Grecia'],
      });
      expect(find.text(es.reviewAiStarted), findsOneWidget);
      expect(find.text(es.reviewAiSheetIntro), findsNothing);
    });

    testWidgets('«también los que ya tienen» pide todos, con otra tanda', (
      tester,
    ) async {
      await setUpWith();
      await seed(withCards: 'Roma');
      await pumpReview(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('ai-cards-also-with-cards')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.reviewAiStart(3)));
      await tester.pumpAndSettle();

      expect(queue.requests.single.ids, hasLength(3));
      expect(queue.requests.single.anotherBatch, isTrue);
    });

    testWidgets('de un cuaderno: hay que elegirlo, y cuenta solo lo suyo', (
      tester,
    ) async {
      await setUpWith();
      final ids = await seed();
      final notebooks = harness.container.read(notebookRepositoryProvider);
      final notebook = await notebooks.create(
        name: 'Tesis',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: notebook.id, itemId: ids['Roma']!);
      await pumpReview(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('ai-cards-scope-notebook')));
      await tester.pumpAndSettle();
      // Sin elegir cuál, no hay nada que pedir.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-cards-start')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('ai-cards-pick-notebook')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tesis').last);
      await tester.pumpAndSettle();

      expect(find.text(es.reviewAiCoverage(1)), findsOneWidget);
      await tester.tap(find.text(es.reviewAiStart(1)));
      await tester.pumpAndSettle();
      expect(queue.requests.single.ids, [ids['Roma']]);
    });

    testWidgets('sin el modelo de lenguaje no se puede, y ofrece bajarlo', (
      tester,
    ) async {
      await setUpWith(modelReady: false);
      await seed();
      await pumpReview(tester);
      await openSheet(tester);

      expect(find.text(es.flashcardsModelMissing), findsOneWidget);
      expect(find.text(es.flashcardsDownloadModel), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-cards-start')))
            .onPressed,
        isNull,
      );
    });
  });

  group('el aviso de cómo va', () {
    void publish(AiFlashcardsBatch? batch) =>
        harness.container.read(aiFlashcardsBatchProvider.notifier).state =
            batch;

    testWidgets('sin pedido no ocupa lugar', (tester) async {
      await setUpWith();
      await pumpReview(tester);

      expect(find.byKey(const Key('ai-cards-banner')), findsNothing);
    });

    testWidgets('trabajando: cuántos de cuántos y qué lee; pausar y cancelar', (
      tester,
    ) async {
      await setUpWith();
      await pumpReview(tester);
      publish(
        const AiFlashcardsBatch(
          total: 5,
          done: 2,
          created: 4,
          forReview: 1,
          currentTitle: 'Roma',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(es.reviewAiBatchWorking), findsOneWidget);
      expect(
        find.text(
          '${es.reviewAiBatchProgress(2, 5)} · ${es.reviewAiBatchCreated(4)} · '
          '${es.reviewAiBatchForReview(1)}',
        ),
        findsOneWidget,
      );
      expect(find.text(es.reviewAiBatchCurrent('Roma')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-cards-pause')));
      await tester.tap(find.byKey(const Key('ai-cards-cancel')));
      expect(queue.calls, ['pausar', 'cancelar']);
    });

    testWidgets('en pausa ofrece seguir; con la IA apagada, reanudarla', (
      tester,
    ) async {
      await setUpWith();
      await pumpReview(tester);
      publish(const AiFlashcardsBatch(total: 5, paused: true));
      await tester.pumpAndSettle();

      expect(find.text(es.reviewAiBatchPaused), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-cards-resume')));
      expect(queue.calls, ['seguir']);

      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      await tester.pumpAndSettle();
      expect(find.text(es.reviewAiBatchAiPaused), findsOneWidget);
      await tester.tap(find.text(es.reviewAiResumeAi));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(aiOrganizeSettingsProvider).enabled,
        isTrue,
      );
    });

    testWidgets('terminado: el resultado, «Para revisar» y cerrar', (
      tester,
    ) async {
      await setUpWith();
      await pumpReview(tester);
      publish(
        const AiFlashcardsBatch(total: 3, done: 3, created: 7, forReview: 2),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.reviewAiBatchDone), findsOneWidget);
      expect(find.text(es.reviewAiBatchSeeReview), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.byKey(const Key('ai-cards-dismiss')));
      expect(queue.calls, ['cerrar']);
    });
  });
}
