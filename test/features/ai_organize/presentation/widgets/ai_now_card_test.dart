import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_now_card.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_queue_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// «Ahora» (F39, paso 6): una sola tarjeta con lo que la IA hace en este
/// momento, y «Cómo lo hace» plegado debajo.
void main() {
  final es = AppLocalizationsEs();
  late DateTime now;
  late AiTaskTracker tracker;
  AiQueueView queueView = const AiQueueIdleView();

  setUp(() {
    now = DateTime(2026, 10, 24, 10);
    tracker = AiTaskTracker(clock: () => now);
    queueView = const AiQueueIdleView();
  });

  tearDown(() => tracker.dispose());

  /// Una respuesta del modelo que se pidió desde [task], con lo que contó.
  void meterTokens(
    AiTaskHandle task, {
    required int input,
    required int output,
  }) => task.run(
    () => tracker.recordReply(inputTokens: input, outputTokens: output),
  );

  /// Deja pasar las animaciones: la tarea en curso anima siempre (la rueda del
  /// paso que va), así que `pumpAndSettle` no termina nunca.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiTaskTrackerProvider.overrideWithValue(tracker),
          clockProvider.overrideWithValue(() => now),
          aiQueueViewProvider.overrideWith((ref) => queueView),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: AiNowCard())),
        ),
      ),
    );
  }

  AiTaskHandle study({String title = 'Historia'}) => tracker.begin(
    kind: AiTaskKind.studyAnalysis,
    title: title,
    itemId: 'h',
    model: 'gemini-3.8-flash',
    steps: const [
      AiTaskStepKind.studySplit,
      AiTaskStepKind.studySend,
      AiTaskStepKind.studyJoin,
    ],
  );

  testWidgets('sin nada en curso no ocupa lugar', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('ai-now-card')), findsNothing);
    expect(find.text(es.aiNowLabel), findsNothing);
    expect(tester.getSize(find.byType(AiNowCard)).height, 0);
  });

  testWidgets('dice qué hace, la parte que va, el porcentaje, el modelo, el '
      'tiempo que lleva y los tokens', (tester) async {
    final handle = study()
      ..step(AiTaskStepKind.studySend)
      ..parts(2, 8);
    now = now.add(const Duration(minutes: 2, seconds: 14));
    meterTokens(handle, input: 12000, output: 340);
    await pump(tester);

    expect(find.text(es.aiNowLabel), findsOneWidget);
    expect(find.text(es.aiNowStudy('Historia')), findsOneWidget);
    expect(find.text(es.aiNowPart(3, 8)), findsOneWidget);
    expect(find.text(es.aiNowPercent(25)), findsOneWidget);
    expect(find.text('Gemini 3.8 Flash'), findsOneWidget);
    expect(find.text(es.aiNowElapsed('2 min 14 s')), findsOneWidget);
    expect(find.text(es.aiNowTokens('12.340')), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('ai-now-bar')),
    );
    expect(bar.value, 0.25);
  });

  testWidgets('el tiempo corre solo, cada segundo, sin esperar a que cambie la '
      'tarea', (tester) async {
    study();
    await pump(tester);
    expect(find.text(es.aiNowElapsed('0 s')), findsOneWidget);

    now = now.add(const Duration(seconds: 65));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(es.aiNowElapsed('1 min 5 s')), findsOneWidget);
  });

  testWidgets('los tokens y el avance se mueven con la tarea', (tester) async {
    final handle = study()..parts(0, 4);
    await pump(tester);
    expect(find.text(es.aiNowTokens('0')), findsOneWidget);
    expect(find.text(es.aiNowPercent(0)), findsOneWidget);

    meterTokens(handle, input: 1000, output: 100);
    handle.parts(1, 4);
    await tester.pump();

    expect(find.text(es.aiNowTokens('1.100')), findsOneWidget);
    expect(find.text(es.aiNowPercent(25)), findsOneWidget);
  });

  testWidgets('sin saber cuánto va, la barra es indeterminada y no hay '
      'porcentaje', (tester) async {
    tracker.begin(kind: AiTaskKind.review, title: 'Roma');
    await pump(tester);

    expect(find.byKey(const Key('ai-now-percent')), findsNothing);
    expect(find.byKey(const Key('ai-now-progress')), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byKey(const Key('ai-now-bar')))
          .value,
      isNull,
    );
  });

  testWidgets('sin título del documento, lo dice sin comillas vacías', (
    tester,
  ) async {
    study(title: '');
    await pump(tester);

    expect(find.text(es.aiNowStudyUntitled), findsOneWidget);
  });

  testWidgets('un reintento reemplaza la línea del avance', (tester) async {
    final handle = study()..parts(1, 4);
    await pump(tester);
    expect(find.byKey(const Key('ai-now-progress')), findsOneWidget);

    handle.retry(
      const AiTaskRetry(
        attempt: 2,
        maxAttempts: 4,
        failure: CloudModelFailure.timeout,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('ai-now-retry')), findsOneWidget);
    expect(find.textContaining('Reintentando (2 de 4)'), findsOneWidget);
    expect(find.byKey(const Key('ai-now-progress')), findsNothing);
  });

  group('«Cómo lo hace»', () {
    testWidgets('arranca plegado: se ve el encabezado y ningún paso', (
      tester,
    ) async {
      study().step(AiTaskStepKind.studySend);
      await pump(tester);

      expect(find.text(es.aiNowHow), findsOneWidget);
      expect(find.byKey(const Key('ai-now-step-studySplit')), findsNothing);
      expect(find.text(es.aiStepStudySend), findsNothing);
    });

    testWidgets('desplegado, lista los pasos con el que va marcado y la parte '
        'que manda', (tester) async {
      final handle = study()
        ..step(AiTaskStepKind.studySend)
        ..parts(2, 8);
      meterTokens(handle, input: 900, output: 80);
      await pump(tester);

      await tester.tap(find.byKey(const Key('ai-now-how')));
      await settle(tester);

      expect(find.text(es.aiStepStudySplit), findsOneWidget);
      expect(find.textContaining(es.aiStepStudySend), findsOneWidget);
      expect(find.textContaining(es.aiNowStepInPart(3, 8)), findsOneWidget);
      expect(find.text(es.aiStepStudyJoin), findsOneWidget);
      // Hecho, en curso y por hacer, cada uno con su marca.
      Finder iconIn(String step, IconData icon) => find.descendant(
        of: find.byKey(Key('ai-now-step-$step')),
        matching: find.byIcon(icon),
      );
      expect(iconIn('studySplit', Icons.check_circle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-now-step-studySend')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(iconIn('studyJoin', Icons.radio_button_unchecked), findsOneWidget);
      expect(find.text(es.aiNowTokensSplit('900', '80')), findsOneWidget);
    });

    testWidgets('sigue desplegado al cambiar de paso, y tocar de nuevo lo '
        'pliega', (tester) async {
      final handle = study()..step(AiTaskStepKind.studySend);
      await pump(tester);
      await tester.tap(find.byKey(const Key('ai-now-how')));
      await settle(tester);
      expect(find.byKey(const Key('ai-now-step-studySplit')), findsOneWidget);

      handle.step(AiTaskStepKind.studyJoin);
      await tester.pump();
      expect(find.byKey(const Key('ai-now-step-studySplit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-now-how')));
      await settle(tester);
      expect(find.byKey(const Key('ai-now-step-studySplit')), findsNothing);
    });

    testWidgets('la parte que va se dice solo en el paso que la manda, no en '
        'los demás aunque estén en curso', (tester) async {
      study()
        ..step(AiTaskStepKind.studySplit)
        ..parts(2, 8);
      await pump(tester);

      await tester.tap(find.byKey(const Key('ai-now-how')));
      await settle(tester);

      expect(find.text(es.aiStepStudySplit), findsOneWidget);
      expect(find.textContaining(es.aiNowStepInPart(3, 8)), findsNothing);
    });

    testWidgets('una tarea sin pasos no ofrece el desplegable', (tester) async {
      tracker.begin(kind: AiTaskKind.review, title: 'Roma');
      await pump(tester);

      expect(find.text(es.aiNowHow), findsNothing);
    });
  });

  testWidgets('con varias tareas a la vez, una sola tarjeta: la que pidió la '
      'persona va grande y las otras en una línea', (tester) async {
    tracker
        .begin(kind: AiTaskKind.organize, title: 'Roma')
        .step(AiTaskStepKind.organizeFlashcards);
    study();
    await pump(tester);

    expect(find.byKey(const Key('ai-now-card')), findsOneWidget);
    expect(find.text(es.aiNowStudy('Historia')), findsOneWidget);
    expect(find.text(es.aiNowOrganize('Roma')), findsNothing);
    expect(find.text(es.aiNowOthers(1)), findsOneWidget);
    expect(find.textContaining('Roma'), findsOneWidget);
  });

  testWidgets('cuando la tarea termina, la tarjeta se va', (tester) async {
    final handle = study();
    await pump(tester);
    expect(find.byKey(const Key('ai-now-card')), findsOneWidget);

    handle.end();
    await settle(tester);

    expect(find.byKey(const Key('ai-now-card')), findsNothing);
  });

  group('lo que organiza la cola de fondo', () {
    testWidgets('dice cuántos quedan en la cola, y la tarjeta de la cola no '
        'repite lo mismo', (tester) async {
      tracker
          .begin(
            kind: AiTaskKind.organize,
            title: 'Roma',
            steps: const [
              AiTaskStepKind.organizeProperties,
              AiTaskStepKind.organizeRelations,
            ],
          )
          .finishStep(AiTaskStepKind.organizeProperties);
      queueView = const AiQueueWorkingView(itemTitle: 'Roma', pending: 4);
      await pump(tester);

      expect(find.text(es.aiNowOrganize('Roma')), findsOneWidget);
      expect(find.text(es.aiNowStep(2, 2)), findsOneWidget);
      expect(find.text(es.aiNowPercent(50)), findsOneWidget);
      expect(find.text(es.aiStatusWorkingMessage(4)), findsOneWidget);
    });

    testWidgets('una tarea de estudio no muestra la cola', (tester) async {
      study();
      queueView = const AiQueueWorkingView(itemTitle: 'Roma', pending: 4);
      await pump(tester);

      expect(find.byKey(const Key('ai-now-pending')), findsNothing);
    });
  });

  group('cuál se muestra grande', () {
    AiTask task(String id, AiTaskKind kind, int minute) => AiTask(
      id: id,
      kind: kind,
      title: id,
      startedAt: DateTime(2026, 10, 24, 10, minute),
    );

    test('la que pidió la persona, antes que la de fondo; entre iguales, la '
        'que empezó primero', () {
      expect(primaryAiTask(const []), isNull);
      expect(
        primaryAiTask([
          task('org', AiTaskKind.organize, 0),
          task('tar', AiTaskKind.flashcards, 1),
          task('rev', AiTaskKind.review, 2),
          task('est', AiTaskKind.studyAnalysis, 3),
        ])?.id,
        'est',
      );
      expect(
        primaryAiTask([
          task('org', AiTaskKind.organize, 0),
          task('tar', AiTaskKind.flashcards, 1),
          task('rev', AiTaskKind.review, 2),
        ])?.id,
        'rev',
      );
      expect(
        primaryAiTask([
          task('tar', AiTaskKind.flashcards, 1),
          task('org', AiTaskKind.organize, 0),
        ])?.id,
        'tar',
      );
      // Buscar fechas (F40) lo pidió la persona: va como las tarjetas, antes
      // que lo de fondo y después de revisar.
      expect(
        primaryAiTask([
          task('org', AiTaskKind.organize, 0),
          task('fec', AiTaskKind.dates, 1),
        ])?.id,
        'fec',
      );
      expect(
        primaryAiTask([
          task('fec', AiTaskKind.dates, 0),
          task('rev', AiTaskKind.review, 1),
        ])?.id,
        'rev',
      );
      expect(
        primaryAiTask([
          task('fec', AiTaskKind.dates, 2),
          task('tar', AiTaskKind.flashcards, 1),
        ])?.id,
        'tar',
      );
      expect(
        primaryAiTask([
          task('segunda', AiTaskKind.organize, 5),
          task('primera', AiTaskKind.organize, 1),
        ])?.id,
        'primera',
      );
    });
  });

  testWidgets('la tarjeta de la cola se esconde mientras «Ahora» ya dice lo '
      'mismo, y vuelve si no hay tarea', (tester) async {
    queueView = const AiQueueWorkingView(itemTitle: 'Roma', pending: 4);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiTaskTrackerProvider.overrideWithValue(tracker),
          clockProvider.overrideWithValue(() => now),
          aiQueueViewProvider.overrideWith((ref) => queueView),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AiQueueStatusCard()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-status-card')), findsOneWidget);

    final handle = tracker.begin(kind: AiTaskKind.organize, title: 'Roma');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-status-card')), findsNothing);

    handle.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-status-card')), findsOneWidget);

    // Hacer solo las tarjetas también es de la cola.
    final cards = tracker.begin(kind: AiTaskKind.flashcards, title: 'Roma');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-status-card')), findsNothing);
    cards.end();
    await tester.pump(const Duration(milliseconds: 300));

    // Un análisis para estudiar no es lo que dice la tarjeta de la cola.
    tracker.begin(kind: AiTaskKind.studyAnalysis, title: 'Historia');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-status-card')), findsOneWidget);
  });
}
