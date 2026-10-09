import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/my_cards_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/my_cards_screen_fixture.dart';

class _MockFlashcards extends Mock implements FlashcardRepository {}

/// Elegir varias tarjetas y actuar sobre ellas (F31, ola 2, decisión 72):
/// contra la base de verdad, para ver que el cambio llega a las tablas.
void main() {
  final es = AppLocalizationsEs();
  late MyCardsFixture f;

  /// La base con tres tarjetas, para casi todas las pruebas.
  Future<void> seed() async {
    f = await MyCardsFixture.create();
    await f.card('a', front: 'Alfa');
    await f.card('b', front: 'Beta');
    await f.card('c', front: 'Gamma');
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  group('elegir', () {
    setUp(seed);

    testWidgets('mantener apretada una tarjeta empieza a elegir; tocar suma y '
        'quita', (tester) async {
      await f.pump(tester);

      await longPress(tester, 'Alfa');
      expect(find.text('1 elegida'), findsOneWidget);
      expect(find.byKey(const Key('my-cards-check-a')), findsOneWidget);

      await tapText(tester, 'Beta');
      expect(find.text('2 elegidas'), findsOneWidget);

      await tapText(tester, 'Alfa'); // la quita
      expect(find.text('1 elegida'), findsOneWidget);
    });

    testWidgets('elegir todas elige las que cumplen el filtro, no solo las '
        'que se ven', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');

      await tester.tap(find.byKey(const Key('my-cards-select-all')));
      await tester.pumpAndSettle();

      expect(find.text('3 elegidas'), findsOneWidget);
      expect(container(tester).read(myCardsControllerProvider).selected, {
        'a',
        'b',
        'c',
      });
    });

    testWidgets('la X sale de la selección sin tocar nada', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tester.tap(find.byKey(const Key('my-cards-selection-close')));
      await tester.pumpAndSettle();

      expect(find.text('1 elegida'), findsNothing);
      expect(find.byKey(const Key('my-cards-check-a')), findsNothing);
      expect(find.text('Mis tarjetas'), findsOneWidget);
    });

    testWidgets('el botón de atrás sale de la selección y no de la pantalla', (
      tester,
    ) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('1 elegida'), findsNothing);
      expect(find.byType(Scaffold), findsWidgets);
      expect(find.text('Alfa'), findsOneWidget);
    });
  });

  group('pausar, reanudar y posponer', () {
    setUp(seed);

    testWidgets('pausar las elegidas', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tapText(tester, 'Beta');

      await tester.tap(find.byKey(const Key('my-cards-action-suspend')));
      await tester.pumpAndSettle();

      expect((await f.row('a')).suspended, isTrue);
      expect((await f.row('b')).suspended, isTrue);
      expect((await f.row('c')).suspended, isFalse);
      expect(find.text('2 tarjetas pausadas'), findsOneWidget);
      // Salió de la selección.
      expect(find.text('2 elegidas'), findsNothing);
    });

    testWidgets('reanudar las pausadas', (tester) async {
      await f.db.customStatement('UPDATE flashcards SET suspended = 1');
      await f.pump(tester);
      await longPress(tester, 'Alfa');

      await tester.tap(find.byKey(const Key('my-cards-action-unsuspend')));
      await tester.pumpAndSettle();

      expect((await f.row('a')).suspended, isFalse);
      expect((await f.row('b')).suspended, isTrue);
      expect(find.text('1 tarjeta reanudada'), findsOneWidget);
    });

    testWidgets(
      'posponer hasta mañana: a las 4:00 del próximo día de estudio',
      (tester) async {
        await f.pump(tester);
        await longPress(tester, 'Alfa');

        await tester.tap(find.byKey(const Key('my-cards-action-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('my-cards-action-bury')));
        await tester.pumpAndSettle();

        expect((await f.row('a')).buriedUntil, DateTime(2026, 9, 12, 4));
        expect((await f.row('b')).buriedUntil, isNull);
        expect(find.text('1 tarjeta pospuesta hasta mañana'), findsOneWidget);
      },
    );
  });

  group('volver a nueva', () {
    setUp(seed);

    setUp(() async {
      await f.db.customStatement(
        'UPDATE flashcards SET interval_days = 40, repetitions = 5, '
        'ease_factor = 1.8',
      );
    });

    testWidgets('pide confirmar; cancelar no cambia nada', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tester.tap(find.byKey(const Key('my-cards-action-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-reset')));
      await tester.pumpAndSettle();

      expect(find.text(es.myCardsResetTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-cards-confirm-cancel')));
      await tester.pumpAndSettle();

      expect((await f.row('a')).intervalDays, 40);
      expect(find.text('1 elegida'), findsOneWidget);
    });

    testWidgets('confirmar deja la tarjeta como nueva', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tapText(tester, 'Beta');
      await tester.tap(find.byKey(const Key('my-cards-action-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-confirm-reset')));
      await tester.pumpAndSettle();

      for (final id in ['a', 'b']) {
        final row = await f.row(id);
        expect(row.intervalDays, 0, reason: id);
        expect(row.repetitions, 0, reason: id);
        expect(row.easeFactor, 2.5, reason: id);
        expect(row.lastReviewedAt, isNull, reason: id);
      }
      expect((await f.row('c')).intervalDays, 40);
      expect(find.text('2 tarjetas volvieron a ser nuevas'), findsOneWidget);
    });
  });

  group('borrar', () {
    setUp(seed);

    testWidgets('pide confirmar con la cuenta; cancelar no borra', (
      tester,
    ) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tapText(tester, 'Beta');
      await tester.tap(find.byKey(const Key('my-cards-action-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-delete')));
      await tester.pumpAndSettle();

      expect(find.text('¿Borrar 2 tarjetas?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-cards-confirm-cancel')));
      await tester.pumpAndSettle();

      expect(await f.maybeRow('a'), isNotNull);
      expect(await f.maybeRow('b'), isNotNull);
    });

    testWidgets('confirmar las borra, con su historial; las demás quedan', (
      tester,
    ) async {
      await f.db
          .into(f.db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: 'log-a',
              flashcardId: 'a',
              reviewedAt: MyCardsFixture.now,
              grade: 'good',
              quality: 4,
              intervalBefore: 0,
              intervalAfter: 1,
              easeBefore: 2.5,
              easeAfter: 2.5,
              deviceId: 'dispositivo',
            ),
          );
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tester.tap(find.byKey(const Key('my-cards-action-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-confirm-delete')));
      await tester.pumpAndSettle();

      expect(await f.maybeRow('a'), isNull);
      expect(await f.maybeRow('b'), isNotNull);
      expect(await f.db.select(f.db.reviewLogs).get(), isEmpty);
      expect(find.text('1 tarjeta borrada'), findsOneWidget);
      expect(find.text('Alfa'), findsNothing);
      expect(find.text('2 tarjetas'), findsOneWidget);
    });

    testWidgets('borrar todas las que cumplen el filtro', (tester) async {
      await f.pump(tester);
      await longPress(tester, 'Alfa');
      await tester.tap(find.byKey(const Key('my-cards-select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-confirm-delete')));
      await tester.pumpAndSettle();

      expect(await f.db.select(f.db.flashcards).get(), isEmpty);
      expect(find.byKey(const Key('my-cards-empty')), findsOneWidget);
    });
  });

  group('tocar una tarjeta', () {
    setUp(seed);

    testWidgets('abre el editor de siempre y guardar cambia el texto', (
      tester,
    ) async {
      await f.pump(tester);

      await tapText(tester, 'Alfa');
      expect(find.text(es.flashcardsEditAction), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Alfa'), 'Alfa 2');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect((await f.row('a')).front, 'Alfa 2');
      expect(find.text('Alfa 2'), findsOneWidget);
    });

    testWidgets('cancelar el editor no cambia nada', (tester) async {
      await f.pump(tester);
      await tapText(tester, 'Alfa');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect((await f.row('a')).front, 'Alfa');
    });
  });

  group('con 10.000 tarjetas', () {
    setUp(seed);

    testWidgets('la lista no las carga todas', (tester) async {
      await f.db.customStatement('DELETE FROM flashcards');
      await f.db.batch((b) {
        b.insertAll(f.db.flashcards, [
          for (var n = 0; n < 10000; n++)
            FlashcardsCompanion.insert(
              id: 'k${n.toString().padLeft(5, '0')}',
              itemId: 'roma',
              front: 'Pregunta k${n.toString().padLeft(5, '0')}',
              back: 'respuesta',
              dueAt: MyCardsFixture.now.add(Duration(minutes: n)),
              createdAt: DateTime(2026).add(Duration(minutes: n)),
            ),
        ]);
      });
      await f.pump(tester);

      expect(find.text('10000 tarjetas'), findsOneWidget);
      final controller = container(
        tester,
      ).read(myCardsControllerProvider.notifier);

      // Saltos por toda la lista, de punta a punta.
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('my-cards-list')),
          matching: find.byType(Scrollable),
        ),
      );
      var peak = 0;
      for (var step = 0; step <= 20; step++) {
        scrollable.position.jumpTo(
          scrollable.position.maxScrollExtent * step / 20,
        );
        await tester.pumpAndSettle();
        if (controller.cachedRows > peak) peak = controller.cachedRows;
      }

      expect(peak, greaterThan(0));
      expect(peak, lessThanOrEqualTo(300));
      // Al final se ve la última, que no estaba cargada al principio.
      expect(find.text('Pregunta k09999'), findsOneWidget);
      // Solo se construyeron los renglones que se ven.
      expect(
        find.byType(ListTile).evaluate().length +
            find.textContaining('Pregunta k').evaluate().length,
        lessThan(40),
      );
    });
  });

  group('cuando una acción falla', () {
    testWidgets('lo dice y deja elegidas las tarjetas', (tester) async {
      final flashcards = _MockFlashcards();
      when(
        () => flashcards.suspend(any()),
      ).thenAnswer((_) async => left(const Failure.unexpected(message: 'no')));
      f = await MyCardsFixture.create(
        extraOverrides: [
          flashcardRepositoryProvider.overrideWithValue(flashcards),
        ],
      );
      await f.card('a', front: 'Alfa');
      await f.pump(tester);
      await longPress(tester, 'Alfa');

      await tester.tap(find.byKey(const Key('my-cards-action-suspend')));
      await tester.pumpAndSettle();

      expect(find.text(es.globalErrorUnexpected), findsOneWidget);
      expect(find.text('1 elegida'), findsOneWidget);
    });
  });
}
