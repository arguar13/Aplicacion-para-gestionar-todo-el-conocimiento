import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/card_browser_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_browser_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/my_cards_controller.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/my_cards_screen_fixture.dart';

class _MockBrowser extends Mock implements CardBrowserRepository {}

/// «Mis tarjetas» de punta a punta (F31, ola 2, decisión 72): la pantalla, su
/// control y el SQL de verdad, con una base en memoria.
void main() {
  final es = AppLocalizationsEs();
  late MyCardsFixture f;

  setUpAll(() => registerFallbackValue(const CardBrowserQuery()));

  group('la lista', () {
    setUp(() async {
      f = await MyCardsFixture.create();
    });

    testWidgets('muestra la etapa, el intervalo, el vencimiento, la forma y el '
        'elemento de cada tarjeta', (tester) async {
      await f.card('nueva', phase: CardPhase.newCard);
      await f.card(
        'madura',
        interval: 90,
        dueAt: DateTime(2026, 9, 20, 12),
        createdAt: DateTime(2026, 8, 2),
      );
      await f.card(
        'huecos',
        kind: FlashcardKind.cloze,
        front: 'El {{c1::Imperio}} cayó en {{c2::476}}',
        clozeIndex: 2,
        groupId: 'g',
        phase: CardPhase.learning,
        createdAt: DateTime(2026, 8, 3),
      );
      await f.pump(tester);

      expect(find.text('Pregunta nueva'), findsOneWidget);
      expect(find.text('Nueva · Sin programar'), findsOneWidget);
      expect(find.text('Pregunta madura'), findsOneWidget);
      expect(find.text('Madura · 90 días · Vence en 9 días'), findsOneWidget);
      expect(find.text('El Imperio cayó en [...]'), findsOneWidget);
      expect(find.text('Aprendiendo · Vence hoy'), findsOneWidget);
      expect(
        find.text('Huecos, con hermanas · Imperio romano'),
        findsOneWidget,
      );
      expect(find.text('3 tarjetas'), findsOneWidget);
    });

    testWidgets('una pausada se ve pausada y una pospuesta, pospuesta', (
      tester,
    ) async {
      await f.card('pausa', suspended: true);
      await f.card('pospone', buriedUntil: DateTime(2026, 9, 12, 4));
      await f.pump(tester);

      expect(find.text('Pausada · 15 días · Vence hoy'), findsOneWidget);
      expect(
        find.text('Joven · 15 días · Vence hoy · Pospuesta hasta mañana'),
        findsOneWidget,
      );
    });

    testWidgets('sin ninguna tarjeta, lo dice', (tester) async {
      await f.pump(tester);
      expect(find.byKey(const Key('my-cards-empty')), findsOneWidget);
      expect(find.text(es.myCardsEmptyVault), findsOneWidget);
      expect(find.byKey(const Key('my-cards-clear-filters')), findsNothing);
    });

    testWidgets('los elementos en la papelera no aparecen', (tester) async {
      await f.card('viva');
      await insertTrashedItemWithCard(f);
      await f.pump(tester);

      expect(find.text('Pregunta viva'), findsOneWidget);
      expect(find.text('Pregunta muerta'), findsNothing);
      expect(find.text('1 tarjeta'), findsOneWidget);
    });

    testWidgets('una tarjeta nueva en la base aparece sola', (tester) async {
      await f.card('a');
      await f.pump(tester);
      expect(find.text('1 tarjeta'), findsOneWidget);

      await f.card('b');
      await tester.pump(
        kMyCardsRefreshDelay + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 tarjetas'), findsOneWidget);
      expect(find.text('Pregunta b'), findsOneWidget);
    });
  });

  group('buscar y filtrar', () {
    setUp(() async {
      f = await MyCardsFixture.create();
      await f.card('r1', front: 'Caída del Imperio Romano', back: 'Año 476');
      await f.card('r2', front: 'Álvaro de Bazán', back: 'Marqués');
      await f.card(
        'n1',
        front: 'Algo nuevo',
        phase: CardPhase.newCard,
        itemId: 'grecia',
      );
      await f.card('p1', front: 'Una pausada', suspended: true);
    });

    testWidgets('el texto busca sin acentos ni mayúsculas, tras esperar un '
        'poco', (tester) async {
      await f.pump(tester);
      await tester.enterText(
        find.byKey(const Key('my-cards-search')),
        'ALVARO',
      );
      // Antes de la espera no busca todavía.
      await tester.pump(kMyCardsSearchDelay - const Duration(milliseconds: 50));
      expect(find.text('4 tarjetas'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Álvaro de Bazán'), findsOneWidget);
      expect(find.text('Caída del Imperio Romano'), findsNothing);
      expect(find.text('1 tarjeta'), findsOneWidget);
    });

    testWidgets('sin resultados, ofrece quitar los filtros', (tester) async {
      await f.pump(tester);
      await tester.enterText(find.byKey(const Key('my-cards-search')), 'zzzz');
      await tester.pump(kMyCardsSearchDelay + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text(es.myCardsEmptyFilter), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-cards-clear-filters')));
      await tester.pumpAndSettle();

      expect(find.text('4 tarjetas'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('my-cards-search')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('la X de la búsqueda la vacía y vuelve a mostrar todo', (
      tester,
    ) async {
      await f.pump(tester);
      await tester.enterText(find.byKey(const Key('my-cards-search')), 'zzzz');
      await tester.pump(kMyCardsSearchDelay + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text(es.myCardsEmptyFilter), findsOneWidget);

      await tester.tap(find.byKey(const Key('my-cards-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('4 tarjetas'), findsOneWidget);
      expect(find.byKey(const Key('my-cards-search-clear')), findsNothing);
    });

    testWidgets('las pestañas de estado traen su cuenta y filtran', (
      tester,
    ) async {
      await f.pump(tester);

      expect(find.text('Todas (4)'), findsOneWidget);
      expect(find.text('Nuevas (1)'), findsOneWidget);
      expect(find.text('Pausadas (1)'), findsOneWidget);
      expect(find.text('Maduras (0)'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('my-cards-status-suspended')),
      );
      await tester.tap(find.byKey(const Key('my-cards-status-suspended')));
      await tester.pumpAndSettle();
      expect(find.text('Una pausada'), findsOneWidget);
      expect(find.text('Algo nuevo'), findsNothing);
      expect(find.text('1 tarjeta'), findsOneWidget);

      // Tocar la misma pestaña otra vez la quita.
      await tester.tap(find.byKey(const Key('my-cards-status-suspended')));
      await tester.pumpAndSettle();
      expect(find.text('4 tarjetas'), findsOneWidget);
    });

    testWidgets('el recorte por tema', (tester) async {
      await f.db
          .into(f.db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'hist',
              name: 'Historia',
              createdAt: MyCardsFixture.now,
            ),
          );
      await (f.db.update(f.db.knowledgeEntries)
            ..where((e) => e.id.equals('grecia')))
          .write(const KnowledgeEntriesCompanion(spaceId: Value('hist')));
      await f.pump(tester);

      await tester.tap(find.byKey(const Key('my-cards-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my-cards-scope-space-hist')));
      await tester.pumpAndSettle();

      expect(find.text('Algo nuevo'), findsOneWidget);
      expect(find.text('1 tarjeta'), findsOneWidget);
      expect(find.text('Historia'), findsOneWidget); // el recorte, a la vista

      // Quitar el recorte.
      await tester.tap(find.byTooltip(es.myCardsScopeClear));
      await tester.pumpAndSettle();
      expect(find.text('4 tarjetas'), findsOneWidget);
    });

    testWidgets('el recorte por cuaderno', (tester) async {
      final notebooks = f.harness.container.read(notebookRepositoryProvider);
      final book = await notebooks.create(
        name: 'Para el examen',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: book.id, itemId: 'grecia');
      await f.pump(tester);

      await tester.tap(find.byKey(const Key('my-cards-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('my-cards-scope-notebook-${book.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Algo nuevo'), findsOneWidget);
      expect(find.text('1 tarjeta'), findsOneWidget);
    });

    testWidgets('abrir con un elemento ya recorta', (tester) async {
      await f.pump(tester, scope: const StudyScope.item('grecia'));

      expect(find.text('Algo nuevo'), findsOneWidget);
      expect(find.text('1 tarjeta'), findsOneWidget);
      expect(find.text('Grecia clásica'), findsWidgets); // el chip
    });

    testWidgets(
      'el orden: elegir otro cambia la lista; el mismo, la invierte',
      (tester) async {
        await (f.db.update(f.db.flashcards)..where((c) => c.id.equals('r1')))
            .write(const FlashcardsCompanion(easeFactor: Value(1.4)));
        await (f.db.update(f.db.flashcards)..where((c) => c.id.equals('r2')))
            .write(const FlashcardsCompanion(easeFactor: Value(3)));
        await f.pump(tester);

        Future<void> sortBy(CardBrowserSort sort) async {
          await tester.tap(find.byKey(const Key('my-cards-sort')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('my-cards-sort-${sort.name}')));
          await tester.pumpAndSettle();
        }

        double top(String text) => tester.getTopLeft(find.text(text)).dy;

        await sortBy(CardBrowserSort.ease);
        expect(
          top('Caída del Imperio Romano'),
          lessThan(top('Álvaro de Bazán')),
        );

        await sortBy(CardBrowserSort.ease); // el mismo: al revés
        expect(
          top('Álvaro de Bazán'),
          lessThan(top('Caída del Imperio Romano')),
        );
      },
    );
  });

  group('el aspecto', () {
    setUp(() async {
      f = await MyCardsFixture.create();
    });

    testWidgets('en un teléfono angosto y con letra grande no se desborda', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await f.card('a', front: 'Una pregunta bastante larga para ver qué pasa');
      await f.card('b', suspended: true, phase: CardPhase.newCard);
      await f.pump(tester);

      expect(tester.takeException(), isNull);
      await tester.longPress(find.text('Pregunta b'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('cuando la lectura falla', () {
    testWidgets('lo dice y deja reintentar', (tester) async {
      final browser = _MockBrowser();
      when(browser.changes).thenAnswer((_) => const Stream.empty());
      when(
        () => browser.count(any()),
      ).thenAnswer((_) async => left(const Failure.unexpected(message: 'no')));
      when(
        () => browser.statusCounts(any()),
      ).thenAnswer((_) async => right(const {}));
      f = await MyCardsFixture.create(
        extraOverrides: [
          cardBrowserRepositoryProvider.overrideWithValue(browser),
        ],
      );
      await f.pump(tester);

      expect(find.text(es.myCardsLoadError), findsOneWidget);

      when(() => browser.count(any())).thenAnswer((_) async => right(0));
      await tester.tap(find.byKey(const Key('my-cards-retry')));
      await tester.pumpAndSettle();
      expect(find.text(es.myCardsLoadError), findsNothing);
      expect(find.byKey(const Key('my-cards-empty')), findsOneWidget);
    });
  });
}

/// Un elemento en la papelera con una tarjeta.
Future<void> insertTrashedItemWithCard(MyCardsFixture f) async {
  await insertItemRows(f.db, id: 'borrado', title: 'Borrado');
  await f.card('muerta', itemId: 'borrado');
  await (f.db.update(f.db.knowledgeEntries)
        ..where((e) => e.id.equals('borrado')))
      .write(KnowledgeEntriesCompanion(deletedAt: Value(MyCardsFixture.now)));
}
