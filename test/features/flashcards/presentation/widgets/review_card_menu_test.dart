import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El menú de la tarjeta que se ve: editar, pausar, posponer y borrar, sin
/// salir del repaso (F31, ola 2).
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 11, 10);
  late LibraryHarness harness;
  late String itemId;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => now)],
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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('review-card-menu')));
    await tester.pumpAndSettle();
  }

  Future<Flashcard> stored(String front) async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!
          .firstWhere((c) => c.front == front);

  Future<List<Flashcard>> allCards() async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!;

  testWidgets('ofrece editar, pausar, posponer y borrar', (tester) async {
    await addCards(['¿Uno?']);
    await pumpSession(tester);

    await openMenu(tester);

    expect(find.text(es.reviewSessionMenuEdit), findsOneWidget);
    expect(find.text(es.reviewSessionMenuSuspend), findsOneWidget);
    expect(find.text(es.reviewSessionMenuBury), findsOneWidget);
    expect(find.text(es.reviewSessionMenuDelete), findsOneWidget);
  });

  testWidgets('una de opción múltiple no se edita desde acá', (tester) async {
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

    await openMenu(tester);

    expect(find.text(es.reviewSessionMenuEdit), findsNothing);
    expect(find.text(es.reviewSessionMenuSuspend), findsOneWidget);
  });

  testWidgets('no hay menú practicando, ni en el resumen', (tester) async {
    await addCards(['¿Uno?']);
    await pumpSession(tester, practice: true);
    expect(find.byKey(const Key('review-card-menu')), findsNothing);
  });

  testWidgets('sin tarjeta a la vista no hay menú', (tester) async {
    await pumpSession(tester);
    expect(find.byKey(const Key('review-card-menu')), findsNothing);
  });

  group('editar', () {
    testWidgets('cambia el texto sin salir, y con la respuesta a la vista '
        'se queda a la vista', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);
      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuEdit));
      await tester.pumpAndSettle();
      // El diálogo arranca con el texto de la tarjeta.
      expect(find.widgetWithText(TextField, '¿Uno?'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '¿Uno?'),
        '¿Uno, mejor?',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'R de ¿Uno?'),
        'Una respuesta mejor',
      );
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text('¿Uno, mejor?'), findsOneWidget);
      expect(find.text('Una respuesta mejor'), findsOneWidget);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
      final saved = (await allCards()).single;
      expect(saved.front, '¿Uno, mejor?');
      expect(saved.back, 'Una respuesta mejor');
    });

    testWidgets('cancelar no cambia nada', (tester) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuEdit));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '¿Uno?'), 'otra');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect((await allCards()).single.front, '¿Uno?');
    });

    testWidgets('una pregunta en blanco lo avisa y no cambia nada', (
      tester,
    ) async {
      await addCards(['¿Uno?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuEdit));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '¿Uno?'), '  ');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect((await allCards()).single.front, '¿Uno?');
    });

    testWidgets('una tarjeta de huecos se edita sin complemento, con las '
        'pistas de su forma', (tester) async {
      const text = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(
            itemId: itemId,
            front: text,
            back: '',
            kind: FlashcardKind.cloze,
            clozeIndex: 1,
          );
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuEdit));
      await tester.pumpAndSettle();
      expect(find.text(es.reviewSessionClozeExtraHint), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, text),
        'El {{c1::Imperio}} cayó en {{c2::476}}',
      );
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      final saved = (await allCards()).single;
      expect(saved.front, 'El {{c1::Imperio}} cayó en {{c2::476}}');
      expect(saved.back, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('una tarjeta de huecos no puede perder su hueco', (
      tester,
    ) async {
      const text = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(
            itemId: itemId,
            front: text,
            back: '',
            kind: FlashcardKind.cloze,
            clozeIndex: 2,
          );
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuEdit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, text),
        'El {{c1::Imperio romano}} cayó',
      );
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect((await allCards()).single.front, text);
    });
  });

  group('pausar y posponer', () {
    testWidgets('pausar saca la tarjeta y pasa a la siguiente; «Deshacer» la '
        'reactiva', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuSuspend));
      await tester.pumpAndSettle();

      expect(find.text('¿Dos?'), findsOneWidget);
      expect(find.text(es.reviewSessionSuspended), findsOneWidget);
      expect((await stored('¿Uno?')).suspended, isTrue);

      await tester.tap(find.text(es.reviewSessionUndoAction));
      await tester.pumpAndSettle();

      expect((await stored('¿Uno?')).suspended, isFalse);
      // La que se estaba viendo no cambia.
      expect(find.text('¿Dos?'), findsOneWidget);
    });

    testWidgets('posponer la deja para mañana; «Deshacer» la devuelve', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuBury));
      await tester.pumpAndSettle();

      expect(find.text('¿Dos?'), findsOneWidget);
      expect(find.text(es.reviewSessionBuried), findsOneWidget);
      expect((await stored('¿Uno?')).buriedUntil, isNotNull);

      await tester.tap(find.text(es.reviewSessionUndoAction));
      await tester.pumpAndSettle();

      expect((await stored('¿Uno?')).buriedUntil, isNull);
    });
  });

  group('borrar', () {
    testWidgets('pide confirmación, y cancelar la deja', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuDelete));
      await tester.pumpAndSettle();
      expect(find.text(es.reviewSessionDeleteTitle), findsOneWidget);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await allCards(), hasLength(2));
      expect(find.text('¿Uno?'), findsOneWidget);
    });

    testWidgets('confirmar la borra y pasa a la siguiente', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpSession(tester);

      await openMenu(tester);
      await tester.tap(find.text(es.reviewSessionMenuDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-delete-confirm')));
      await tester.pumpAndSettle();

      expect((await allCards()).map((c) => c.front), ['¿Dos?']);
      expect(find.text('¿Dos?'), findsOneWidget);
    });
  });
}
