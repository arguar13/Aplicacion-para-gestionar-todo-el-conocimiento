import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/screens/ai_activity_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../fake_ai_run_repository.dart';

/// «Lo que hizo la IA» (F27): el estado de la cola, «Para revisar» y la
/// actividad con su «Deshacer», de a páginas.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeAiRunRepository runs;

  Future<void> setUpWith(List<AiRun> initial) async {
    runs = FakeAiRunRepository(initial);
    harness = await LibraryHarness.create(
      extraOverrides: [aiRunRepositoryProvider.overrideWithValue(runs)],
    );
  }

  Future<void> pumpScreen(WidgetTester tester, {String? itemId}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(AiActivityScreen(itemId: itemId)));
    await tester.pumpAndSettle();
  }

  void setStatus(AiOrganizeStatus status) =>
      harness.container.read(aiOrganizeStatusProvider.notifier).state = status;

  group('vacío', () {
    testWidgets('sin pasadas ni nada para revisar, lo dice con calma', (
      tester,
    ) async {
      await setUpWith(const []);
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-activity-empty')), findsOneWidget);
      expect(find.text(es.aiActivityEmptyTitle), findsOneWidget);
      expect(find.text(es.aiActivityEmptyMessage), findsOneWidget);
      expect(find.text(es.aiReviewTitle), findsNothing);
      // La cola se ve igual: decir que está al día también es información.
      expect(find.text(es.aiStatusIdleTitle), findsOneWidget);
    });
  });

  group('la cola', () {
    setUp(() => setUpWith(const []));

    testWidgets('organizando: qué y cuántos esperan', (tester) async {
      await pumpScreen(tester);
      setStatus(
        const AiOrganizeWorking(
          itemTitle: 'Roma',
          pending: 3,
          source: AiWorkSource.fresh,
        ),
      );
      // La barra de la cola es indeterminada y anima siempre: alcanza con
      // dejar pasar la transición.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(es.aiStatusWorkingTitle('Roma')), findsOneWidget);
      expect(find.text(es.aiStatusWorkingMessage(3)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('esperando el cargador: cuántos faltan', (tester) async {
      await pumpScreen(tester);
      setStatus(const AiOrganizePaused(pending: 12, waitingForCharger: true));
      await tester.pumpAndSettle();

      expect(find.text(es.aiStatusChargerTitle), findsOneWidget);
      expect(find.text(es.aiStatusChargerMessage(12)), findsOneWidget);
      expect(find.byKey(const Key('ai-status-resume')), findsNothing);
    });

    testWidgets('con la IA apagada, en pausa; «Reanudar» la prende', (
      tester,
    ) async {
      await pumpScreen(tester);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      setStatus(const AiOrganizePaused(pending: 4));
      await tester.pumpAndSettle();

      expect(find.text(es.aiStatusPausedTitle), findsOneWidget);
      expect(find.text(es.aiStatusPausedMessage(4)), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-status-resume')));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiOrganizeSettingsProvider).enabled,
        isTrue,
      );
    });

    testWidgets('apagada, no importa que falte un modelo: está en pausa', (
      tester,
    ) async {
      await pumpScreen(tester);
      await harness.container
          .read(aiOrganizeSettingsProvider.notifier)
          .set(AiOrganizeToggle.enabled, on: false);
      setStatus(
        const AiOrganizeModelMissing(
          chatModelMissing: true,
          embeddingModelMissing: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.aiStatusPausedTitle), findsOneWidget);
      expect(find.text(es.aiStatusModelTitle), findsNothing);
    });

    testWidgets('falta un modelo: invita a bajar justo el que falta', (
      tester,
    ) async {
      await pumpScreen(tester);
      setStatus(
        const AiOrganizeModelMissing(
          chatModelMissing: true,
          embeddingModelMissing: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.aiStatusModelTitle), findsOneWidget);
      expect(find.text(es.aiStatusModelChat), findsOneWidget);
      expect(find.byKey(const Key('ai-status-download-chat')), findsOneWidget);
      expect(
        find.byKey(const Key('ai-status-download-embedding')),
        findsNothing,
      );

      setStatus(
        const AiOrganizeModelMissing(
          chatModelMissing: true,
          embeddingModelMissing: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ai-status-download-embedding')),
        findsOneWidget,
      );
    });

    testWidgets('el botón del modelo lleva a su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setStatus(
        const AiOrganizeModelMissing(
          chatModelMissing: true,
          embeddingModelMissing: false,
        ),
      );
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.aiActivity);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-status-download-chat')));
      await tester.pumpAndSettle();

      expect(find.byType(ChatModelScreen), findsOneWidget);
    });
  });

  group('la actividad', () {
    testWidgets('por día y por elemento, con lo que sigue siendo de la IA', (
      tester,
    ) async {
      await setUpWith([
        fakeRun('r3', itemId: 'a', itemTitle: 'Roma antigua'),
        fakeRun(
          'r2',
          itemId: 'a',
          itemTitle: 'Roma antigua',
          startedAt: DateTime(2026, 9, 11, 8),
          remaining: const AiRunTally(properties: 3),
        ),
        fakeRun(
          'r1',
          itemId: 'b',
          itemTitle: 'Cartago',
          startedAt: DateTime(2026, 9, 10, 18),
          remaining: const AiRunTally(flashcards: 6),
        ),
      ]);
      await pumpScreen(tester);

      expect(find.text(es.aiActivitySection), findsOneWidget);
      expect(find.text(es.aiActivityToday), findsOneWidget);
      expect(find.text(es.aiActivityYesterday), findsOneWidget);
      // Las dos pasadas de hoy sobre «Roma antigua» son una sola tarjeta.
      expect(find.byKey(const Key('ai-activity-item-a')), findsOneWidget);
      expect(find.text('Roma antigua'), findsOneWidget);
      expect(find.text(es.aiTallyRelations(2)), findsOneWidget);
      expect(find.text(es.aiTallyProperties(3)), findsOneWidget);
      expect(find.text(es.aiTallyFlashcards(6)), findsOneWidget);
      // Más de una pasada que deshacer: también «Deshacer todo».
      expect(find.byKey(const Key('ai-activity-undo-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-activity-undo-item-b')), findsNothing);
      expect(find.byKey(const Key('ai-activity-empty')), findsNothing);
    });

    testWidgets('lo que ya se adoptó o se borró no se ofrece deshacer', (
      tester,
    ) async {
      await setUpWith([
        fakeRun(
          'r1',
          itemId: 'a',
          remaining: const AiRunTally(),
          created: const AiRunTally(relations: 2),
        ),
        fakeRun('r0', itemId: 'b', undone: true),
      ]);
      await pumpScreen(tester);

      expect(find.text(es.aiRunNothingLeft), findsOneWidget);
      expect(find.text(es.aiRunUndone), findsOneWidget);
      expect(find.text(es.aiRunUndo), findsNothing);
    });

    testWidgets('deshacer una pasada pregunta, la deshace y avisa cuánto', (
      tester,
    ) async {
      await setUpWith([fakeRun('r1', itemId: 'a', itemTitle: 'Roma')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-run-undo-r1')));
      await tester.pumpAndSettle();
      expect(find.text(es.aiUndoRunTitle), findsOneWidget);
      expect(
        find.text(es.aiUndoMessage('Roma', '2 vínculos · 1 tarjeta')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai-undo-confirm')));
      await tester.pumpAndSettle();

      expect(runs.undoneRuns, ['r1']);
      expect(
        find.text(es.aiUndoDone('2 vínculos · 1 tarjeta')),
        findsOneWidget,
      );
      // Releída: la pasada se ve deshecha, sin botón.
      expect(find.text(es.aiRunUndone), findsOneWidget);
      expect(find.byKey(const Key('ai-run-undo-r1')), findsNothing);
    });

    testWidgets('cancelar la confirmación no deshace nada', (tester) async {
      await setUpWith([fakeRun('r1', itemId: 'a')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-run-undo-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(runs.undoneRuns, isEmpty);
      expect(find.byKey(const Key('ai-run-undo-r1')), findsOneWidget);
    });

    testWidgets('«Deshacer todo» de un elemento se lleva todas sus pasadas', (
      tester,
    ) async {
      await setUpWith([
        fakeRun('r2', itemId: 'a', itemTitle: 'Roma'),
        fakeRun(
          'r1',
          itemId: 'a',
          itemTitle: 'Roma',
          startedAt: DateTime(2026, 9, 11, 8),
          remaining: const AiRunTally(properties: 1),
        ),
      ]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-activity-undo-item-a')));
      await tester.pumpAndSettle();
      expect(find.text(es.aiUndoItemTitle), findsOneWidget);
      expect(
        find.text(
          es.aiUndoMessage(
            'Roma',
            '2 vínculos · 1 tarjeta · 1 etiqueta o propiedad',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ai-undo-confirm')));
      await tester.pumpAndSettle();

      expect(runs.undoneItems, ['a']);
      expect(find.text(es.aiRunUndone), findsNWidgets(2));
    });

    testWidgets('trae la página siguiente al llegar al final', (tester) async {
      await setUpWith([
        for (var i = 0; i < 45; i++)
          fakeRun(
            'r$i',
            itemId: 'item$i',
            itemTitle: 'Elemento $i',
            startedAt: DateTime(2026, 9, 11, 9, 59 - i),
          ),
      ]);
      await pumpScreen(tester);

      expect(runs.pages.first, (itemId: null, limit: 30, offset: 0));
      expect(find.text('Elemento 44'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Elemento 44'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(runs.pages, contains((itemId: null, limit: 30, offset: 30)));
      expect(find.text('Elemento 44'), findsOneWidget);
      // Con la última página corta no pide más.
      expect(runs.pages.where((p) => p.offset == 45), isEmpty);
    });

    testWidgets('si la lectura falla, lo dice y deja reintentar', (
      tester,
    ) async {
      await setUpWith([fakeRun('r1', itemId: 'a', itemTitle: 'Roma')]);
      runs.nextListFailure = const Failure.unexpected(message: 'roto');
      await pumpScreen(tester);

      expect(find.text(es.aiActivityLoadError), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-activity-retry')));
      await tester.pumpAndSettle();

      expect(find.text(es.aiActivityLoadError), findsNothing);
      expect(find.text('Roma'), findsOneWidget);
    });

    testWidgets('se vuelve a leer cuando la cola termina una pasada', (
      tester,
    ) async {
      await setUpWith(const []);
      await pumpScreen(tester);
      expect(find.byKey(const Key('ai-activity-empty')), findsOneWidget);

      // La cola cerró una pasada sobre «Roma» y pasó a estar al día.
      runs.add(fakeRun('r1', itemId: 'a', itemTitle: 'Roma'));
      setStatus(const AiOrganizePaused(pending: 1, waitingForCharger: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-activity-empty')), findsNothing);
      expect(find.byKey(const Key('ai-activity-item-a')), findsOneWidget);
    });

    testWidgets('tocar un elemento lo abre, con el router real', (
      tester,
    ) async {
      await setUpWith([fakeRun('r1', itemId: 'a', itemTitle: 'Roma')]);
      await insertItemRows(harness.database, id: 'a', title: 'Roma');
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.aiActivity);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Roma'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });
  });

  group('solo un elemento', () {
    testWidgets('muestra solo sus pasadas y su filtro', (tester) async {
      await setUpWith([
        fakeRun('r2', itemId: 'a', itemTitle: 'Roma'),
        fakeRun('r1', itemId: 'b', itemTitle: 'Cartago'),
      ]);
      await insertItemRows(harness.database, id: 'a', title: 'Roma');
      await pumpScreen(tester, itemId: 'a');

      expect(runs.pages.first.itemId, 'a');
      expect(find.byKey(const Key('ai-activity-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-activity-item-b')), findsNothing);
      expect(find.byKey(const Key('ai-activity-item-filter')), findsOneWidget);
    });
  });

  group('para revisar', () {
    setUp(() async {
      await setUpWith(const []);
      for (final (id, title) in [
        ('a', 'Roma'),
        ('b', 'Cartago'),
        ('c', 'Grecia'),
      ]) {
        await insertItemRows(harness.database, id: id, title: title);
      }
    });

    /// Una sugerencia de vínculo pendiente de [from] hacia [to]; devuelve su
    /// id.
    Future<String> suggestRelation(String from, String to, String title) async {
      final created = await harness.container
          .read(suggestionRepositoryProvider)
          .createRelationSuggestion(
            targetItemId: from,
            relatedItemId: to,
            relatedItemTitle: title,
            kind: RelationKind.relatedTo,
            reason: 'Hablan de la misma guerra',
            confidence: 0.55,
          );
      return created.getOrElse((f) => fail('$f')).id;
    }

    Future<SuggestionStatus> statusOf(String id) async {
      final row = await (harness.database.select(
        harness.database.suggestions,
      )..where((s) => s.id.equals(id))).getSingle();
      return row.status;
    }

    /// Deja pasar el «Deshacer» de un lote sin tocarlo. El aviso empieza a
    /// contar recién cuando terminó de entrar: primero se lo deja entrar,
    /// después pasa su tiempo y por último se va.
    Future<void> waitOutBatchUndo(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    }

    Future<int> relationCount() async =>
        (await harness.database.select(harness.database.relations).get())
            .length;

    testWidgets('lo dudoso, agrupado por elemento y con cuántas son', (
      tester,
    ) async {
      await suggestRelation('a', 'b', 'Cartago');
      await suggestRelation('a', 'c', 'Grecia');
      await suggestRelation('b', 'c', 'Grecia');
      await pumpScreen(tester);

      expect(find.text(es.aiReviewTitle), findsOneWidget);
      expect(find.text(es.aiReviewHint), findsOneWidget);
      expect(find.byKey(const Key('ai-review-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-review-item-b')), findsOneWidget);
      expect(find.text('Hablan de la misma guerra'), findsNWidgets(3));
      expect(find.text('3'), findsOneWidget);
      // Hay algo que mirar: no es el vacío.
      expect(find.byKey(const Key('ai-activity-empty')), findsNothing);
    });

    testWidgets('aceptar uno lo aplica y se va', (tester) async {
      final id = await suggestRelation('a', 'b', 'Cartago');
      await pumpScreen(tester);

      await tester.tap(find.byKey(Key('ai-review-accept-$id')));
      await tester.pumpAndSettle();

      expect(await statusOf(id), SuggestionStatus.accepted);
      expect(await relationCount(), 1);
      expect(find.text(es.aiReviewTitle), findsNothing);
    });

    testWidgets('una tarjeta cuya cita no se ubicó: su pregunta y su '
        'respuesta, y aceptarla la crea (F30)', (tester) async {
      final created = await harness.container
          .read(suggestionRepositoryProvider)
          .createFlashcardSuggestion(
            targetItemId: 'a',
            front: '¿Quién fundó Roma?',
            back: 'Rómulo',
            quote: 'Una frase que el texto no tiene',
          );
      final id = created.getOrElse((f) => fail('$f')).id;
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-review-item-a')), findsOneWidget);
      expect(find.text('¿Quién fundó Roma?'), findsOneWidget);
      expect(find.text(es.aiReviewFlashcardDetail('Rómulo')), findsOneWidget);

      await tester.tap(find.byKey(Key('ai-review-accept-$id')));
      await tester.pumpAndSettle();

      expect(await statusOf(id), SuggestionStatus.accepted);
      final card = await harness.database
          .select(harness.database.flashcards)
          .getSingle();
      expect(card.front, '¿Quién fundó Roma?');
      expect(card.itemId, 'a');
    });

    testWidgets('descartar uno no aplica nada', (tester) async {
      final id = await suggestRelation('a', 'b', 'Cartago');
      await pumpScreen(tester);

      await tester.tap(find.byKey(Key('ai-review-discard-$id')));
      await tester.pumpAndSettle();

      expect(await statusOf(id), SuggestionStatus.rejected);
      expect(await relationCount(), 0);
    });

    testWidgets('aceptar todo espera el «Deshacer» y después aplica', (
      tester,
    ) async {
      final ids = [
        await suggestRelation('a', 'b', 'Cartago'),
        await suggestRelation('b', 'c', 'Grecia'),
      ];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-accept-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(es.aiReviewAcceptedAll(2)), findsOneWidget);
      // Mientras el aviso está a la vista, la base no se tocó.
      for (final id in ids) {
        expect(await statusOf(id), SuggestionStatus.pending);
      }

      await waitOutBatchUndo(tester);

      for (final id in ids) {
        expect(await statusOf(id), SuggestionStatus.accepted);
      }
      expect(await relationCount(), 2);
    });

    testWidgets('descartar todo y «Deshacer» deja todo como estaba', (
      tester,
    ) async {
      final ids = [
        await suggestRelation('a', 'b', 'Cartago'),
        await suggestRelation('b', 'c', 'Grecia'),
      ];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-discard-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(es.aiReviewDiscardedAll(2)), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-review-batch-undo')));
      await tester.pumpAndSettle();

      for (final id in ids) {
        expect(await statusOf(id), SuggestionStatus.pending);
      }
      expect(find.text('Hablan de la misma guerra'), findsNWidgets(2));
    });

    testWidgets('descartar todo sin deshacer los descarta', (tester) async {
      final ids = [
        await suggestRelation('a', 'b', 'Cartago'),
        await suggestRelation('b', 'c', 'Grecia'),
      ];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-discard-all')));
      await waitOutBatchUndo(tester);

      for (final id in ids) {
        expect(await statusOf(id), SuggestionStatus.rejected);
      }
      expect(find.text(es.aiReviewTitle), findsNothing);
      expect(find.byKey(const Key('ai-activity-empty')), findsOneWidget);
    });

    testWidgets('con un elemento elegido, solo lo de ese elemento', (
      tester,
    ) async {
      await suggestRelation('a', 'b', 'Cartago');
      await suggestRelation('b', 'c', 'Grecia');
      await pumpScreen(tester, itemId: 'a');

      expect(find.byKey(const Key('ai-review-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-review-item-b')), findsNothing);
    });
  });
}
