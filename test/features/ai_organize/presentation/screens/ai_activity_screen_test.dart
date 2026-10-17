import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/language_model_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_account_switcher.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_organize/presentation/screens/ai_activity_screen.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_review_queue.dart';
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

    group('con la IA en la nube (F32)', () {
      testWidgets('sin clave: pide cargar una, no bajar un modelo', (
        tester,
      ) async {
        await pumpScreen(tester);
        setStatus(
          const AiOrganizeModelMissing(
            chatModelMissing: true,
            embeddingModelMissing: false,
            keyFor: AiProvider.gemini,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(es.aiStatusModelTitle), findsOneWidget);
        expect(
          find.text(es.aiStatusModelChatKey(es.lmProviderGemini)),
          findsOneWidget,
        );
        expect(find.text(es.aiStatusModelChat), findsNothing);
        expect(find.byKey(const Key('ai-status-add-key')), findsOneWidget);
        expect(find.byKey(const Key('ai-status-download-chat')), findsNothing);
      });

      testWidgets('«Cargar una clave» lleva a «Modelo de lenguaje», con el '
          'router real', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setStatus(
          const AiOrganizeModelMissing(
            chatModelMissing: true,
            embeddingModelMissing: false,
            keyFor: AiProvider.gemini,
          ),
        );
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo(RoutePaths.aiActivity);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('ai-status-add-key')));
        await tester.pumpAndSettle();

        expect(find.byType(LanguageModelScreen), findsOneWidget);
      });

      testWidgets('sin cuota: hasta cuándo, cuántos esperan, que nada se '
          'pierde, y a las cuentas', (tester) async {
        await pumpScreen(tester);
        final at = DateTime.now().add(const Duration(hours: 1));
        setStatus(
          AiOrganizeWaitingForModel(
            reason: AiModelWait.quota,
            pending: 5,
            resumesAt: at,
          ),
        );
        await tester.pumpAndSettle();

        final time = aiResetTime(
          tester.element(find.byType(AiActivityScreen)),
          at,
        );
        expect(find.text(es.aiStatusWaitingTitle), findsOneWidget);
        expect(
          find.text(
            '${es.aiStatusWaitingQuota(time)} ${es.aiStatusWaitingPending(5)}',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ai-status-accounts')), findsOneWidget);
        // Esperar la cuota no es algo que la persona tenga que arreglar.
        expect(find.byKey(const Key('ai-status-add-key')), findsNothing);
      });

      testWidgets('con el tope de fondo: cuántos pedidos usó y cuándo sigue', (
        tester,
      ) async {
        await pumpScreen(tester);
        final at = DateTime.now().add(const Duration(hours: 2));
        setStatus(
          AiOrganizeWaitingForModel(
            reason: AiModelWait.backgroundCap,
            pending: 1,
            resumesAt: at,
            cap: 200,
          ),
        );
        await tester.pumpAndSettle();

        final time = aiResetTime(
          tester.element(find.byType(AiActivityScreen)),
          at,
        );
        expect(
          find.text(
            '${es.aiStatusWaitingCap(200, time)} '
            '${es.aiStatusWaitingPending(1)}',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ai-status-accounts')), findsOneWidget);
      });

      testWidgets(
        'sin conexión: vuelve sola, sin nada que ver en las cuentas',
        (tester) async {
          await pumpScreen(tester);
          setStatus(
            const AiOrganizeWaitingForModel(
              reason: AiModelWait.offline,
              pending: 2,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(
              '${es.aiStatusWaitingOffline} ${es.aiStatusWaitingPending(2)}',
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('ai-status-accounts')), findsNothing);
        },
      );

      testWidgets('las claves rechazadas: lo dice y lleva a las cuentas', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setStatus(
          const AiOrganizeWaitingForModel(
            reason: AiModelWait.keysRejected,
            pending: 0,
          ),
        );
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo(RoutePaths.aiActivity);
        await tester.pumpAndSettle();

        expect(
          find.text(
            '${es.aiStatusWaitingKeys} ${es.aiStatusWaitingPending(0)}',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('ai-status-accounts')));
        await tester.pumpAndSettle();
        expect(find.byType(LanguageModelScreen), findsOneWidget);
      });
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

  group('revisión (F33)', () {
    setUp(() async {
      await setUpWith(const []);
      for (final (id, title) in [('a', 'Roma'), ('b', 'Cartago')]) {
        await insertItemRows(harness.database, id: id, title: title);
        await harness.database
            .into(harness.database.aiRuns)
            .insert(
              AiRunsCompanion.insert(
                id: 'run-$id',
                itemId: id,
                startedAt: DateTime(2026, 10, 17),
              ),
            );
      }
    });

    /// Una tarjeta de la IA en [itemId] y una corrección pendiente sobre
    /// ella; devuelve la corrección y la tarjeta.
    Future<({String id, String card})> propose(
      String itemId, {
      String front = '¿Quién escribió el Quijote?',
      String back = 'Lope de Vega.',
      String? fixedBack = 'Miguel de Cervantes.',
    }) async {
      final card =
          (await harness.container
                  .read(flashcardRepositoryProvider)
                  .create(
                    itemId: itemId,
                    front: front,
                    back: back,
                    ai: AiProvenance(runId: 'run-$itemId'),
                  ))
              .getOrElse((f) => fail('$f'));
      final created = await harness.container
          .read(suggestionRepositoryProvider)
          .createCorrectionSuggestion(
            targetItemId: itemId,
            subject: CorrectionSubject.flashcard,
            subjectId: card.id,
            before: {
              FlashcardCorrectionField.front: front,
              FlashcardCorrectionField.back: back,
            },
            after: fixedBack == null
                ? null
                : {
                    FlashcardCorrectionField.front: front,
                    FlashcardCorrectionField.back: fixedBack,
                  },
            reason: 'El pasaje dice otra cosa.',
            aiRunId: 'run-review',
            model: 'gemini-3.8-flash',
          );
      return (id: created.getOrElse((f) => fail('$f')).id, card: card.id);
    }

    Future<SuggestionStatus> statusOf(String id) async {
      final row = await (harness.database.select(
        harness.database.suggestions,
      )..where((s) => s.id.equals(id))).getSingle();
      return row.status;
    }

    Future<FlashcardRow?> cardOf(String id) => (harness.database.select(
      harness.database.flashcards,
    )..where((f) => f.id.equals(id))).getSingleOrNull();

    Future<void> waitOutBatchUndo(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    }

    testWidgets('el antes y el después, quién lo propone y por qué', (
      tester,
    ) async {
      final fix = await propose('a');
      final drop = await propose(
        'b',
        front: '¿Relleno?',
        back: 'Sí.',
        fixedBack: null,
      );
      await pumpScreen(tester);

      expect(find.text(es.aiCorrectionsTitle), findsOneWidget);
      expect(find.text(es.aiCorrectionsHint), findsOneWidget);
      expect(find.byKey(const Key('ai-corrections-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-corrections-item-b')), findsOneWidget);
      expect(find.text(es.aiCorrectionFixCard), findsOneWidget);
      expect(find.text(es.aiCorrectionRemoveCard), findsOneWidget);
      expect(find.text('Gemini 3.8 Flash'), findsNWidgets(2));
      expect(find.text('El pasaje dice otra cosa.'), findsNWidgets(2));
      // La pregunta no cambió: una sola vez. La respuesta, antes y después.
      final row = find.byKey(Key('ai-correction-${fix.id}'));
      expect(
        find.descendant(
          of: row,
          matching: find.text('¿Quién escribió el Quijote?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Lope de Vega.', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Miguel de Cervantes.', findRichText: true),
        ),
        findsOneWidget,
      );
      // Lo que se saca se muestra tachado, sin después.
      expect(
        find.descendant(
          of: find.byKey(Key('ai-correction-${drop.id}')),
          matching: find.text('¿Relleno?'),
        ),
        findsOneWidget,
      );
      // No es «Para revisar», ni el vacío.
      expect(find.text(es.aiReviewTitle), findsNothing);
      expect(find.byKey(const Key('ai-activity-empty')), findsNothing);
    });

    testWidgets('aceptar una corrige la tarjeta y se va', (tester) async {
      final fix = await propose('a');
      await pumpScreen(tester);

      await tester.tap(find.byKey(Key('ai-correction-accept-${fix.id}')));
      await tester.pumpAndSettle();

      expect(await statusOf(fix.id), SuggestionStatus.accepted);
      expect((await cardOf(fix.card))!.back, 'Miguel de Cervantes.');
      expect(find.text(es.aiCorrectionsTitle), findsNothing);
      expect(find.byKey(const Key('ai-activity-empty')), findsOneWidget);
    });

    testWidgets('descartar una no cambia nada', (tester) async {
      final fix = await propose('a');
      await pumpScreen(tester);

      await tester.tap(find.byKey(Key('ai-correction-discard-${fix.id}')));
      await tester.pumpAndSettle();

      expect(await statusOf(fix.id), SuggestionStatus.rejected);
      expect((await cardOf(fix.card))!.back, 'Lope de Vega.');
    });

    testWidgets('si la tarjeta cambió después, la corrección ya no se '
        'ofrece', (tester) async {
      final fix = await propose('a');
      await harness.container
          .read(flashcardRepositoryProvider)
          .update(
            id: fix.card,
            front: '¿Quién escribió el Quijote?',
            back: 'Cervantes.',
          );
      await pumpScreen(tester);

      expect(find.text(es.aiCorrectionsTitle), findsNothing);
    });

    testWidgets('aceptar todo espera el «Deshacer» y después aplica', (
      tester,
    ) async {
      final fix = await propose('a');
      final drop = await propose(
        'b',
        front: '¿Relleno?',
        back: 'Sí.',
        fixedBack: null,
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-corrections-accept-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(es.aiReviewAcceptedAll(2)), findsOneWidget);
      expect(await statusOf(fix.id), SuggestionStatus.pending);
      expect(await cardOf(drop.card), isNotNull);

      await waitOutBatchUndo(tester);

      expect(await statusOf(fix.id), SuggestionStatus.accepted);
      expect((await cardOf(fix.card))!.back, 'Miguel de Cervantes.');
      expect(await cardOf(drop.card), isNull);
    });

    testWidgets('descartar todo y «Deshacer» deja todo como estaba', (
      tester,
    ) async {
      final fix = await propose('a');
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-corrections-discard-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('ai-review-batch-undo')));
      await tester.pumpAndSettle();

      expect(await statusOf(fix.id), SuggestionStatus.pending);
      expect(find.byKey(Key('ai-correction-${fix.id}')), findsOneWidget);
    });

    testWidgets('las de un elemento se aceptan juntas', (tester) async {
      final first = await propose('a');
      final second = await propose(
        'a',
        front: '¿Cuándo cayó Roma?',
        back: 'En 1453.',
        fixedBack: 'En 476.',
      );
      final other = await propose('b');
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('ai-corrections-accept-item-b')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('ai-corrections-accept-item-a')));
      await waitOutBatchUndo(tester);

      expect(await statusOf(first.id), SuggestionStatus.accepted);
      expect(await statusOf(second.id), SuggestionStatus.accepted);
      expect(await statusOf(other.id), SuggestionStatus.pending);
    });

    testWidgets('con un elemento elegido, solo las de ese elemento', (
      tester,
    ) async {
      await propose('a');
      await propose('b');
      await pumpScreen(tester, itemId: 'a');

      expect(find.byKey(const Key('ai-corrections-item-a')), findsOneWidget);
      expect(find.byKey(const Key('ai-corrections-item-b')), findsNothing);
    });

    test('el número de Ajustes suma «Para revisar» y «Revisión»', () async {
      await propose('a');
      await harness.container
          .read(suggestionRepositoryProvider)
          .createRelationSuggestion(
            targetItemId: 'a',
            relatedItemId: 'b',
            relatedItemTitle: 'Cartago',
            kind: RelationKind.relatedTo,
            reason: 'r',
          );
      final sub = harness.container.listen(
        pendingDecisionsCountProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await harness.container.read(pendingCorrectionsProvider.future);
      await harness.container.read(pendingReviewCountProvider.future);

      expect(sub.read(), 2);
    });
  });

  group('revisar con otro modelo (F33)', () {
    late FakeAiReviewQueue queue;
    late AiAccountsView accounts;
    final today = DateTime(2026, 10, 17, 12);

    setUp(() async {
      runs = FakeAiRunRepository();
      queue = FakeAiReviewQueue();
      accounts = (
        accounts: const [],
        activeId: null,
        usage: const {},
        now: today,
      );
      harness = await LibraryHarness.create(
        extraOverrides: [
          aiRunRepositoryProvider.overrideWithValue(runs),
          aiReviewQueueProvider.overrideWithValue(queue),
          aiReviewerNameProvider.overrideWithValue('gemini-3.8-flash'),
          languageModelTextBudgetProvider.overrideWithValue(
            () => kSmallWindowTextBudget,
          ),
          aiAccountsViewProvider.overrideWith((ref) => accounts),
        ],
      );
      await insertItemRows(harness.database, id: 'a', title: 'Roma');
    });

    void setBatch(AiReviewBatch? batch) =>
        harness.container.read(aiReviewBatchProvider.notifier).state = batch;

    String work(int cards, String model, int items) => es.aiRecheckOfferWork(
      es.aiRecheckCards(cards),
      model,
      es.aiRecheckItems(items),
    );

    testWidgets('ofrece revisar lo que el modelo elegido todavía no revisó, '
        'por el modelo que lo hizo', (tester) async {
      runs.work = const [
        AiModelWork(model: 'Gemma 4 E4B', cards: 12, items: 5),
        AiModelWork(model: null, cards: 1, items: 1),
      ];
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-review-offer')), findsOneWidget);
      expect(runs.workQueries, everyElement('gemini-3.8-flash'));
      expect(find.text(work(12, 'Gemma 4 E4B', 5)), findsOneWidget);
      expect(find.text(work(1, es.aiRecheckEarlierModel, 1)), findsOneWidget);
      expect(find.text(es.aiRecheckWith('Gemini 3.8 Flash')), findsOneWidget);
      // De más de un modelo: también lo de uno solo, si se sabe cuál.
      expect(
        find.byKey(const Key('ai-review-offer-only-Gemma 4 E4B')),
        findsOneWidget,
      );
      expect(find.text(es.aiRecheckOnlyModel('Gemma 4 E4B')), findsOneWidget);
    });

    testWidgets('de un solo modelo, un solo botón', (tester) async {
      runs.work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 2, items: 1)];
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-review-offer-all')), findsOneWidget);
      expect(
        find.byKey(const Key('ai-review-offer-only-Gemma 4 E4B')),
        findsNothing,
      );
    });

    testWidgets('sin nada para revisar, no ofrece', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-review-offer')), findsNothing);
    });

    testWidgets('mirando un elemento, no ofrece la biblioteca: ahí está el '
        'botón de su línea', (tester) async {
      runs.work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 2, items: 1)];
      await pumpScreen(tester, itemId: 'a');

      expect(find.byKey(const Key('ai-review-offer')), findsNothing);
    });

    testWidgets('antes de empezar dice cuánto cuesta, y empieza solo si se '
        'confirma', (tester) async {
      runs
        ..work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 9, items: 2)]
        ..candidates = const [
          AiReviewCandidate(itemId: 'a', cards: 5),
          AiReviewCandidate(itemId: 'b', cards: 4),
        ];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-offer-all')));
      await tester.pumpAndSettle();

      expect(runs.candidateQueries.single, (
        reviewer: 'gemini-3.8-flash',
        madeBy: null,
        itemId: null,
      ));
      expect(find.byKey(const Key('ai-review-cost-dialog')), findsOneWidget);
      // De a 4 tarjetas por pedido: 2 para las 5 de «a» y 1 para las 4 de «b».
      expect(
        find.text(
          es.aiRecheckCostScope(es.aiRecheckCards(9), es.aiRecheckItems(2), 3),
        ),
        findsOneWidget,
      );
      // Con Gemma, en el teléfono: no hay cuota que gastar.
      expect(find.text(es.aiRecheckCostLocal), findsOneWidget);
      expect(find.text(es.aiRecheckCostNothingChanges), findsOneWidget);

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();
      expect(queue.requests, isEmpty);

      await tester.tap(find.byKey(const Key('ai-review-offer-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-review-cost-start')));
      await tester.pumpAndSettle();

      expect(queue.requests.single.itemIds, ['a', 'b']);
      expect(queue.requests.single.skipOwnWork, isTrue);
    });

    testWidgets('«Solo lo de» pide lo de ese modelo', (tester) async {
      runs
        ..work = const [
          AiModelWork(model: 'Gemma 4 E4B', cards: 3, items: 1),
          AiModelWork(model: 'gemini-2.5-flash', cards: 1, items: 1),
        ]
        ..candidates = const [AiReviewCandidate(itemId: 'a', cards: 3)];
      await pumpScreen(tester);

      await tester.tap(
        find.byKey(const Key('ai-review-offer-only-Gemma 4 E4B')),
      );
      await tester.pumpAndSettle();

      expect(runs.candidateQueries.single.madeBy, 'Gemma 4 E4B');
    });

    testWidgets('si ya no queda nada para revisar, lo dice y no pregunta', (
      tester,
    ) async {
      runs.work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 2, items: 1)];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-offer-all')));
      await tester.pumpAndSettle();

      expect(find.text(es.aiRecheckNothing), findsOneWidget);
      expect(find.byKey(const Key('ai-review-cost-dialog')), findsNothing);
    });

    testWidgets('en la nube: sale de la cuota de la persona, con lo gastado '
        'hoy y si las cuentas están sin cuota', (tester) async {
      await harness.container
          .read(aiModelSettingsProvider.notifier)
          .chooseProvider(AiProvider.gemini);
      final account = AiAccount(
        id: 'k1',
        provider: AiProvider.gemini,
        label: 'Personal',
        addedAt: DateTime(2026),
      );
      accounts = (
        accounts: [account],
        activeId: 'k1',
        usage: {
          'k1': const AccountUsage(
            accountId: 'k1',
            day: '2026-10-17',
            requests: 37,
          ),
        },
        now: today,
      );
      runs
        ..work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 2, items: 1)]
        ..candidates = const [AiReviewCandidate(itemId: 'a', cards: 2)];
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('ai-review-offer-all')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          [
            es.aiRecheckCostQuota,
            es.aiRecheckCostToday(37),
            es.aiRecheckCostUnknownLeft,
          ].join(' '),
        ),
        findsOneWidget,
      );
      expect(find.text(es.aiRecheckCostLocal), findsNothing);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      // Todas sin cuota: dice desde cuándo empieza.
      accounts = (
        accounts: [account],
        activeId: 'k1',
        usage: {
          'k1': AccountUsage(
            accountId: 'k1',
            day: '2026-10-17',
            requests: 250,
            exhaustedUntil: today.add(const Duration(hours: 3)),
          ),
        },
        now: today,
      );
      harness.container.invalidate(aiAccountsViewProvider);
      await tester.tap(find.byKey(const Key('ai-review-offer-all')));
      await tester.pumpAndSettle();

      final exhausted = es.aiRecheckCostExhausted('');
      expect(
        find.textContaining(exhausted.substring(0, exhausted.indexOf(':'))),
        findsOneWidget,
      );
      expect(find.textContaining(es.aiRecheckCostUnknownLeft), findsNothing);
    });

    testWidgets('mientras revisa: cuántos van, cuántas propuestas, qué lee, '
        'con pausar y cancelar; no ofrece otra', (tester) async {
      runs.work = const [AiModelWork(model: 'Gemma 4 E4B', cards: 2, items: 1)];
      await pumpScreen(tester);
      setBatch(
        const AiReviewBatch(
          total: 5,
          done: 2,
          proposed: 3,
          currentTitle: 'Roma',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-review-progress')), findsOneWidget);
      expect(
        find.text(es.aiRecheckWorking('Gemini 3.8 Flash')),
        findsOneWidget,
      );
      expect(
        find.text('${es.aiRecheckProgress(2, 5)} · ${es.aiRecheckProposed(3)}'),
        findsOneWidget,
      );
      expect(find.text(es.reviewAiBatchCurrent('Roma')), findsOneWidget);
      expect(find.byKey(const Key('ai-review-offer')), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('ai-review-progress')),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, 2 / 5);

      await tester.tap(find.byKey(const Key('ai-review-pause')));
      await tester.tap(find.byKey(const Key('ai-review-cancel')));
      expect(queue.actions, ['pause', 'cancel']);
    });

    testWidgets('en pausa, «Seguir»', (tester) async {
      await pumpScreen(tester);
      setBatch(const AiReviewBatch(total: 5, done: 1, paused: true));
      await tester.pumpAndSettle();

      expect(find.text(es.aiRecheckPaused), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-review-resume')));
      expect(queue.actions, ['resume']);
    });

    testWidgets('esperando al modelo dice por qué, y sin modelo lleva a '
        'elegirlo', (tester) async {
      await pumpScreen(tester);
      setBatch(
        AiReviewBatch(
          total: 5,
          done: 1,
          waiting: AiModelWait.quota,
          resumesAt: today.add(const Duration(hours: 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.aiRecheckWaiting), findsOneWidget);
      final quota = es.aiStatusWaitingQuota('');
      expect(
        find.textContaining(quota.substring(0, quota.indexOf(':'))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-review-open-model')), findsOneWidget);

      setBatch(const AiReviewBatch(total: 5, done: 1, modelMissing: true));
      await tester.pumpAndSettle();
      expect(find.text(es.aiRecheckModelMissing), findsOneWidget);
      expect(find.byKey(const Key('ai-review-open-model')), findsOneWidget);

      // Sin conexión no hay nada que ver en el modelo: vuelve sola.
      setBatch(
        const AiReviewBatch(total: 5, done: 1, waiting: AiModelWait.offline),
      );
      await tester.pumpAndSettle();
      expect(find.text(es.aiStatusWaitingOffline), findsOneWidget);
      expect(find.byKey(const Key('ai-review-open-model')), findsNothing);
    });

    testWidgets('al terminar, el resultado y «Cerrar»', (tester) async {
      await pumpScreen(tester);
      setBatch(const AiReviewBatch(total: 3, done: 3, proposed: 4));
      await tester.pumpAndSettle();

      expect(find.text(es.aiRecheckDone), findsOneWidget);
      expect(find.text(es.aiRecheckProposed(4)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const Key('ai-review-dismiss')));
      expect(queue.actions, ['dismiss']);
    });
  });
}
