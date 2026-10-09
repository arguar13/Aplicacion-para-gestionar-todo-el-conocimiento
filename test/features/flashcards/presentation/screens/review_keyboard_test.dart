import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Los atajos de teclado de la sesión (F31, ola 2): espacio da vuelta la
/// tarjeta, 1 a 4 califican y Z deshace.
void main() {
  final es = AppLocalizationsEs();
  final start = DateTime(2026, 9, 11, 10);
  late LibraryHarness harness;
  late String itemId;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => start)],
    );
    await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
    itemId =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single
            .id;
  });

  Future<void> addCards(List<String> fronts) async {
    for (final front in fronts) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: itemId, front: front, back: 'R de $front');
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

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<Flashcard> stored(String front) async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!
          .firstWhere((c) => c.front == front);

  group('espacio', () {
    testWidgets('da vuelta la tarjeta', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      expect(find.text('R de ¿Uno?'), findsNothing);

      await press(tester, LogicalKeyboardKey.space);

      expect(find.text('R de ¿Uno?'), findsOneWidget);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
    });

    testWidgets('una de opción múltiple no se da vuelta con el espacio', (
      tester,
    ) async {
      await harness.container
          .read(flashcardRepositoryProvider)
          .createMultipleChoice(
            itemId: itemId,
            front: '¿Capital?',
            options: const [
              FlashcardOptionDraft(content: 'Roma', isCorrect: true),
              FlashcardOptionDraft(content: 'Milán', isCorrect: false),
            ],
          );
      await pumpSession(tester);

      await press(tester, LogicalKeyboardKey.space);

      expect(find.byKey(const Key('grade-good')), findsNothing);
    });

    testWidgets('practicando, da vuelta y después pasa a la siguiente', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester, practice: true);
      expect(find.text(es.reviewPracticeProgress(1, 2)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.space);
      expect(find.byKey(const Key('practice-next')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.space);

      expect(find.text(es.reviewPracticeProgress(2, 2)), findsOneWidget);
    });
  });

  group('1 a 4', () {
    final cases = {
      LogicalKeyboardKey.digit1: ('De nuevo', const Duration(minutes: 1)),
      LogicalKeyboardKey.digit2: ('Difícil', const Duration(minutes: 6)),
      LogicalKeyboardKey.digit3: ('Bien', const Duration(minutes: 10)),
      LogicalKeyboardKey.digit4: ('Fácil', const Duration(days: 4)),
      LogicalKeyboardKey.numpad3: (
        'Bien, del teclado numérico',
        const Duration(minutes: 10),
      ),
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key.keyLabel}: ${entry.value.$1}', (tester) async {
        await addCards(['¿Uno?']);
        await pumpSession(tester);
        await press(tester, LogicalKeyboardKey.space);

        await press(tester, entry.key);

        expect((await stored('¿Uno?')).dueAt.difference(start), entry.value.$2);
      });
    }

    testWidgets('antes de dar vuelta la tarjeta no califican', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await press(tester, LogicalKeyboardKey.digit4);

      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
      expect(find.byKey(const Key('review-show-answer')), findsOneWidget);
    });

    testWidgets('practicando no califican', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester, practice: true);
      await press(tester, LogicalKeyboardKey.space);

      await press(tester, LogicalKeyboardKey.digit4);

      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
    });

    testWidgets('con Control no hacen nada (es de la compu, no de la '
        'sesión)', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await press(tester, LogicalKeyboardKey.space);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
    });
  });

  testWidgets('siguen andando después de usar los botones con el dedo', (
    tester,
  ) async {
    await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
    await pumpSession(tester);

    // Los botones que se tocan desaparecen: el foco no puede quedar perdido.
    await tester.tap(find.byKey(const Key('review-show-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grade-easy')));
    await tester.pumpAndSettle();
    expect(find.text('¿Dos?'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.space);
    await press(tester, LogicalKeyboardKey.digit4);

    expect(find.text('¿Tres?'), findsOneWidget);
    expect((await stored('¿Dos?')).lastReviewedAt, isNotNull);
  });

  group('Z', () {
    testWidgets('deshace la última respuesta', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.digit4);
      expect(find.text('¿Dos?'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.keyZ);

      expect(find.text('¿Uno?'), findsOneWidget);
      expect((await stored('¿Uno?')).lastReviewedAt, isNull);
    });

    testWidgets('Control+Z también', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.digit4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('¿Uno?'), findsOneWidget);
    });

    testWidgets('sin nada que deshacer no hace nada', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await press(tester, LogicalKeyboardKey.keyZ);

      expect(find.text('¿Uno?'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('desde el resumen vuelve a la última tarjeta', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.digit4);
      expect(find.byKey(const Key('review-summary')), findsOneWidget);

      await press(tester, LogicalKeyboardKey.keyZ);

      expect(find.byKey(const Key('review-summary')), findsNothing);
      expect(find.text('¿Uno?'), findsOneWidget);
    });
  });
}
