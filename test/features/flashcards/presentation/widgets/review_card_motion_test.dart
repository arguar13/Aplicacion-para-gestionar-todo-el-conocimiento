import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La vuelta de la tarjeta, los gestos para calificar y la vibración (F31,
/// ola 2).
void main() {
  final es = AppLocalizationsEs();
  final start = DateTime(2026, 9, 11, 10);
  late LibraryHarness harness;
  late List<String> haptics;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => start)],
    );
    // Lo que el sistema recibe como vibración.
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(
              '${call.arguments}'.replaceAll('HapticFeedbackType.', ''),
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
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

  Future<void> pumpSession(WidgetTester tester, {bool practice = false}) async {
    tester.view.physicalSize = const Size(400 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(ReviewScreen(startInPractice: practice)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('review-show-answer')));
    await tester.pumpAndSettle();
  }

  Future<Flashcard> stored(String front) async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!
          .firstWhere((c) => c.front == front);

  final card = find.byKey(const Key('review-card'));

  group('la vuelta de la tarjeta', () {
    testWidgets('al tocarla gira: a mitad de camino todavía se ve la pregunta, '
        'y al terminar la respuesta', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      expect(find.text('R de ¿Uno?'), findsNothing);

      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Girando: la respuesta todavía no.
      expect(find.text('R de ¿Uno?'), findsNothing);
      expect(find.text('¿Uno?'), findsOneWidget);
      // La caja gira: el coseno del ángulo está entre 0 y 1 (ni quieta ni de
      // canto todavía).
      final flip = tester
          .widgetList<Transform>(
            find.descendant(of: card, matching: find.byType(Transform)),
          )
          .firstWhere((t) => t.transform.entry(3, 2) != 0);
      expect(flip.transform.entry(0, 0), inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(find.text('R de ¿Uno?'), findsOneWidget);
      // La cara de atrás se lee derecha: se vuelve a espejar.
      expect(find.text('¿Uno?'), findsOneWidget);
    });

    testWidgets('con las animaciones del sistema apagadas, la vuelta es '
        'instantánea', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await tester.tap(card);
      await tester.pump();
      await tester.pump();

      expect(find.text('R de ¿Uno?'), findsOneWidget);
    });

    testWidgets('el botón «Mostrar respuesta» también la da vuelta', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await reveal(tester);

      expect(find.text('R de ¿Uno?'), findsOneWidget);
    });
  });

  group('deslizar para calificar', () {
    // Una nueva: «De nuevo» = paso 0 (1 min), «Difícil» = paso 0 (6 min),
    // «Bien» = paso 1 (10 min), «Fácil» = se gradúa (4 días).
    final cases = <String, (Offset, Duration)>{
      'derecha = Bien': (const Offset(260, 0), const Duration(minutes: 10)),
      'izquierda = De nuevo': (
        const Offset(-260, 0),
        const Duration(minutes: 1),
      ),
      'arriba = Fácil': (const Offset(0, -260), const Duration(days: 4)),
      'abajo = Difícil': (const Offset(0, 260), const Duration(minutes: 6)),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        await addCards(['¿Uno?']);
        await pumpSession(tester);
        await reveal(tester);

        await tester.drag(card, entry.value.$1);
        await tester.pumpAndSettle();

        final saved = await stored('¿Uno?');
        expect(saved.dueAt.difference(start), entry.value.$2);
      });
    }

    testWidgets('a medias muestra el color y el nombre de la calificación; '
        'soltar antes del umbral no califica y la tarjeta vuelve', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await reveal(tester);

      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();

      expect(find.byKey(const Key('review-swipe-veil')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('review-swipe-veil')),
          matching: find.text(es.reviewGradeGood),
        ),
        findsOneWidget,
      );
      // Todavía no llegó al umbral: nada vibró.
      expect(haptics, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('review-swipe-veil')), findsNothing);
      expect(haptics, isEmpty);
      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
      // De vuelta en su lugar.
      expect(
        tester.getCenter(card).dx,
        closeTo(tester.view.physicalSize.width / 2 / 2, 1),
      );
    });

    testWidgets('al pasar el umbral vibra una vez, y al soltar otra, más '
        'fuerte', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await reveal(tester);

      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(haptics, isEmpty);
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(haptics, ['selectionClick']);
      // Seguir arrastrando en la misma dirección no repite la vibración.
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(haptics, ['selectionClick']);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(haptics, ['selectionClick', 'mediumImpact']);
    });

    testWidgets('antes de dar vuelta la tarjeta no se puede deslizar', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(160, 0));
      await tester.pump();

      // Ni el velo de color, ni la vibración, ni se mueve la tarjeta.
      expect(find.byKey(const Key('review-swipe-veil')), findsNothing);
      expect(haptics, isEmpty);
      expect(
        tester.getCenter(card).dx,
        closeTo(tester.view.physicalSize.width / 2 / 2, 1),
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(haptics, isEmpty);
      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
      expect(find.byKey(const Key('review-show-answer')), findsOneWidget);
    });

    testWidgets('practicando no se califica, ni se desliza', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester, practice: true);
      await tester.tap(card);
      await tester.pumpAndSettle();

      await tester.drag(card, const Offset(260, 0));
      await tester.pumpAndSettle();

      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
      expect(find.byKey(const Key('practice-next')), findsOneWidget);
    });

    testWidgets('los botones siguen: tocar uno vibra y califica', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await reveal(tester);

      await tester.tap(find.byKey(const Key('grade-easy')));
      await tester.pumpAndSettle();

      expect(haptics, ['selectionClick']);
      expect(
        (await stored('¿Uno?')).dueAt.difference(start),
        const Duration(days: 4),
      );
    });

    testWidgets('dice cómo se desliza una vez dada la vuelta, no antes', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      expect(find.byKey(const Key('review-swipe-hint')), findsNothing);

      await reveal(tester);

      expect(find.text(es.reviewSessionSwipeHint), findsOneWidget);
    });

    testWidgets('para quien no puede arrastrar, cada calificación es una '
        'acción de accesibilidad de la tarjeta', (tester) async {
      await addCards(['¿Uno?']);
      final handle = tester.ensureSemantics();
      await pumpSession(tester);
      await reveal(tester);

      final node = tester.getSemantics(card);
      final actions = node
          .getSemanticsData()
          .customSemanticsActionIds!
          .map(CustomSemanticsAction.getAction)
          .toList();
      expect(actions.map((a) => a!.label), [
        es.reviewGradeAgain,
        es.reviewGradeHard,
        es.reviewGradeGood,
        es.reviewGradeEasy,
      ]);

      final easy = actions.firstWhere((a) => a!.label == es.reviewGradeEasy)!;
      tester.semantics.performAction(
        find.semantics.byPredicate((n) => n.id == node.id),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(easy),
      );
      await tester.pumpAndSettle();

      expect(
        (await stored('¿Uno?')).dueAt.difference(start),
        const Duration(days: 4),
      );
      handle.dispose();
    });
  });
}
