import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Una cola que siempre falla.
class _FailingStudyRepository implements StudyRepository {
  @override
  Future<Either<Failure, StudyNext>> next(
    StudyScope scope, {
    required StudyLimits limits,
    Duration learnAhead = Duration.zero,
  }) async => left(const Failure.unexpected(message: 'se rompió la cola'));

  @override
  Future<Either<Failure, StudyCounts>> counts(
    StudyScope scope, {
    required StudyLimits limits,
  }) async => left(const Failure.unexpected(message: 'se rompió la cola'));

  @override
  Stream<StudyCounts> watchCounts(
    StudyScope scope, {
    required StudyLimits limits,
  }) => const Stream.empty();
}

/// La sesión de repaso tal como se ve (F31, ola 2): avance, resumen y deshacer.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var now = DateTime(2026, 9, 11, 10);

  setUp(() async {
    now = DateTime(2026, 9, 11, 10);
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => now)],
    );
  });

  Future<void> addCards(List<String> fronts) async {
    await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    for (final front in fronts) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: items.single.id, front: front, back: 'R de $front');
    }
  }

  Future<void> pumpSession(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const ReviewScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> grade(WidgetTester tester, String grade) async {
    await tester.tap(find.byKey(const Key('review-show-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('grade-$grade')));
    await tester.pumpAndSettle();
  }

  double barValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(
        find.byKey(const Key('review-progress-bar')),
      )
      .value!;

  /// El primer texto de la pieza con esa clave: el número del contador o el
  /// valor de la estadística.
  Text firstText(WidgetTester tester, String key) => tester.widget<Text>(
    find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
        .first,
  );

  TextStyle counterStyle(WidgetTester tester, String key) =>
      firstText(tester, key).style!;

  group('la barra de avance y los contadores', () {
    testWidgets('empieza vacía, dice cuántas quedan y cuenta por cola', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      await pumpSession(tester);

      expect(barValue(tester), 0);
      expect(find.text(es.reviewRemaining(3)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('review-counter-new')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.text(es.reviewSessionQueueNew), findsOneWidget);
      expect(find.text(es.reviewSessionQueueLearning), findsOneWidget);
      expect(find.text(es.reviewSessionQueueReview), findsOneWidget);
    });

    testWidgets('con cada respuesta avanza lo que se contestó sobre el total', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?', '¿Cuatro?']);
      await pumpSession(tester);

      await grade(tester, 'easy');
      expect(barValue(tester), closeTo(1 / 4, 1e-6));
      await grade(tester, 'easy');
      expect(barValue(tester), closeTo(2 / 4, 1e-6));
    });

    testWidgets('el contador de la cola de la tarjeta que se ve va subrayado', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      expect(
        counterStyle(tester, 'review-counter-new').decoration,
        TextDecoration.underline,
      );
      expect(
        counterStyle(tester, 'review-counter-learning').decoration,
        isNot(TextDecoration.underline),
      );
      expect(
        counterStyle(tester, 'review-counter-review').decoration,
        isNot(TextDecoration.underline),
      );
    });

    testWidgets('lo que se está aprendiendo se cuenta aparte', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await grade(tester, 'again');

      expect(
        find.descendant(
          of: find.byKey(const Key('review-counter-learning')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('review-counter-new')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('el resumen al terminar', () {
    testWidgets('dice cuántas tarjetas, cuánto tardaste y cuántas '
        'acertaste', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      now = now.add(const Duration(seconds: 25));
      await grade(tester, 'easy');
      now = now.add(const Duration(seconds: 95));
      await grade(tester, 'easy');

      expect(find.byKey(const Key('review-summary')), findsOneWidget);
      expect(find.text(es.reviewSessionSummaryTitle), findsOneWidget);
      String valueOf(String key) => firstText(tester, key).data!;
      expect(valueOf('review-stat-cards'), '2');
      // 25 s + 95 s (< 2 min, no se recorta) = 2 min.
      expect(
        valueOf('review-stat-time'),
        es.reviewSessionDurationMinutes(2, 0),
      );
      expect(valueOf('review-stat-correct'), es.reviewSessionPercent(100));
    });

    testWidgets('«De nuevo» baja los aciertos, y lo que vuelve en un rato '
        'ofrece «Seguir ahora»', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await grade(tester, 'again');
      await grade(tester, 'easy');

      expect(find.byKey(const Key('review-waiting')), findsOneWidget);
      expect(find.text(es.reviewWaitMessage(1, 1)), findsOneWidget);
      expect(
        firstText(tester, 'review-stat-correct').data,
        es.reviewSessionPercent(50),
      );

      await tester.tap(find.byKey(const Key('review-summary-continue')));
      await tester.pumpAndSettle();

      // La tarjeta que vuelve se ve otra vez, y el resumen se va.
      expect(find.byKey(const Key('review-summary')), findsNothing);
      expect(find.text('¿Uno?'), findsOneWidget);
    });

    testWidgets('al llegar al límite del día lo dice, con «Estudiar más '
        'hoy»', (tester) async {
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      await pumpSession(tester);

      await grade(tester, 'easy');

      expect(find.byKey(const Key('review-limit-reached')), findsOneWidget);
      expect(find.text(es.reviewLimitMessage(2, 0)), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-summary-more')));
      await tester.pumpAndSettle();

      expect(find.text('¿Dos?'), findsOneWidget);
    });

    testWidgets('muestra la racha del hábito, y no la muestra si el hábito '
        'está apagado', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await grade(tester, 'easy');

      // Contestar una tarjeta es actividad de hoy: racha de 1 día.
      expect(find.byKey(const Key('review-stat-streak')), findsOneWidget);
      expect(find.text(es.reviewSessionStreakDays(1)), findsOneWidget);

      await harness.container
          .read(habitFeaturesEnabledProvider.notifier)
          .setEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-stat-streak')), findsNothing);
    });

    testWidgets('sin haber contestado nada, no hay resumen: está el vacío de '
        'siempre', (tester) async {
      await pumpSession(tester);

      expect(find.byKey(const Key('review-summary')), findsNothing);
    });

    testWidgets('«Terminar» cierra la pantalla', (tester) async {
      await addCards(['¿Uno?']);
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness.wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ReviewScreen()),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await grade(tester, 'easy');

      await tester.tap(find.byKey(const Key('review-summary-finish')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });
  });

  group('deshacer', () {
    testWidgets('el botón empieza apagado y se prende al contestar', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);
      IconButton undo() =>
          tester.widget<IconButton>(find.byKey(const Key('review-undo')));

      expect(undo().onPressed, isNull);

      await grade(tester, 'easy');

      expect(undo().onPressed, isNotNull);
    });

    testWidgets('devuelve la tarjeta, sin la respuesta a la vista, y deja el '
        'calendario como estaba', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);
      final before =
          (await harness.container.read(flashcardRepositoryProvider).getAll())
              .getRight()
              .toNullable()!
              .firstWhere((c) => c.front == '¿Uno?');
      await grade(tester, 'easy');
      expect(find.text('¿Dos?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-undo')));
      await tester.pumpAndSettle();

      expect(find.text('¿Uno?'), findsOneWidget);
      expect(find.byKey(const Key('review-show-answer')), findsOneWidget);
      expect(barValue(tester), 0);
      final after =
          (await harness.container.read(flashcardRepositoryProvider).getAll())
              .getRight()
              .toNullable()!
              .firstWhere((c) => c.front == '¿Uno?');
      expect(after.dueAt, before.dueAt);
      expect(after.repetitions, before.repetitions);
    });

    testWidgets('también se puede desde el resumen: vuelve a la última '
        'tarjeta', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await grade(tester, 'easy');
      expect(find.byKey(const Key('review-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-summary-undo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-summary')), findsNothing);
      expect(find.text('¿Uno?'), findsOneWidget);
    });

    testWidgets('si no se puede deshacer, lo dice y no cambia nada', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);
      await grade(tester, 'easy');
      await harness.database.delete(harness.database.reviewLogs).go();

      await tester.tap(find.byKey(const Key('review-undo')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('¿Dos?'), findsOneWidget);
    });
  });

  testWidgets('si la cola no se puede leer, lo dice y deja reintentar', (
    tester,
  ) async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        studyRepositoryProvider.overrideWithValue(_FailingStudyRepository()),
      ],
    );
    await pumpSession(tester);

    expect(find.byKey(const Key('review-load-failed')), findsOneWidget);
    expect(find.text(es.reviewSessionLoadFailed), findsOneWidget);
    expect(find.text(es.reviewAllDone), findsNothing);

    await tester.tap(find.text(es.reviewSessionRetry));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-load-failed')), findsOneWidget);
  });
}
