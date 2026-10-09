import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/review_entry_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_stats_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La entrada a Repasar (F31, ola 2): cuánto hay para hoy, qué estudiar y el
/// camino a la sesión.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late Map<String, String> items;

  setUp(() async {
    harness = await LibraryHarness.create();
    await harness.capture('Roma\n\nTexto de Roma.', title: 'Roma');
    await harness.capture('Grecia\n\nTexto de Grecia.', title: 'Grecia');
    final all =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    items = {for (final item in all) item.title: item.id};
  });

  Future<void> addCards(String title, List<String> fronts) async {
    for (final front in fronts) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: items[title]!, front: front, back: 'R de $front');
    }
  }

  Future<void> openEntry(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.pushTo(RoutePaths.review);
    await tester.pumpAndSettle();
  }

  String countOf(WidgetTester tester, String key) => tester
      .widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      )
      .data!;

  String scopeName(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('review-entry-scope-name')))
      .data!;

  Future<void> chooseScope(
    WidgetTester tester,
    StudyScopeKind kind,
    String optionId,
  ) async {
    await tester.tap(find.byKey(const Key('review-entry-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('scope-kind-${kind.name}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('scope-option-$optionId')));
    await tester.pumpAndSettle();
  }

  group('lo que hay para hoy', () {
    testWidgets('cuenta nuevas, aprendiendo y por repasar', (tester) async {
      await addCards('Roma', ['¿Uno?', '¿Dos?', '¿Tres?']);
      final cards =
          (await harness.container.read(flashcardRepositoryProvider).getAll())
              .getRight()
              .toNullable()!;
      // Una queda aprendiéndose (vuelve en 1 minuto).
      await harness.container
          .read(flashcardRepositoryProvider)
          .review(id: cards.first.id, grade: ReviewGrade.again);
      await openEntry(tester);

      expect(countOf(tester, 'review-entry-new'), '2');
      expect(countOf(tester, 'review-entry-learning'), '1');
      expect(countOf(tester, 'review-entry-review'), '0');
      expect(find.byKey(const Key('review-entry-start')), findsOneWidget);
      expect(
        find.byKey(const Key('review-entry-next-learning')),
        findsOneWidget,
      );
    });

    testWidgets('si el límite del día deja afuera algunas, lo dice', (
      tester,
    ) async {
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await addCards('Roma', ['¿Uno?', '¿Dos?', '¿Tres?']);
      await openEntry(tester);

      expect(countOf(tester, 'review-entry-new'), '1');
      expect(find.text(es.reviewEntryNewBeyond(2)), findsOneWidget);
    });

    testWidgets('sin nada para estudiar muestra el vacío de siempre, sin '
        '«Empezar»', (tester) async {
      await openEntry(tester);

      expect(find.byKey(const Key('review-entry-start')), findsNothing);
      expect(
        find.byKey(const Key('review-empty-without-cards')),
        findsOneWidget,
      );
    });

    testWidgets('se actualiza solo cuando aparece una tarjeta', (tester) async {
      await openEntry(tester);
      expect(find.byKey(const Key('review-entry-start')), findsNothing);

      await addCards('Roma', ['¿Nueva?']);
      await tester.pumpAndSettle();

      expect(countOf(tester, 'review-entry-new'), '1');
    });
  });

  group('empezar', () {
    testWidgets('abre la sesión con la primera tarjeta, y volver deja la '
        'entrada', (tester) async {
      await addCards('Roma', ['¿Uno?']);
      await openEntry(tester);

      await tester.tap(find.byKey(const Key('review-entry-start')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('¿Uno?'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byKey(const Key('review-entry')), findsOneWidget);
    });

    testWidgets('«Mis tarjetas» y «Estadísticas» llevan a sus rutas', (
      tester,
    ) async {
      await addCards('Roma', ['¿Uno?']);
      await openEntry(tester);

      await tester.tap(find.byKey(const Key('review-entry-cards')));
      await tester.pumpAndSettle();
      expect(find.byType(MyCardsScreen), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-entry-stats')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewStatsScreen), findsOneWidget);
    });
  });

  group('qué estudiar', () {
    testWidgets('un elemento: cuenta y estudia solo sus tarjetas', (
      tester,
    ) async {
      await addCards('Roma', ['¿Roma 1?', '¿Roma 2?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);
      expect(countOf(tester, 'review-entry-new'), '3');

      await chooseScope(tester, StudyScopeKind.item, items['Grecia']!);

      expect(scopeName(tester), 'Grecia');
      expect(countOf(tester, 'review-entry-new'), '1');

      await tester.tap(find.byKey(const Key('review-entry-start')));
      await tester.pumpAndSettle();
      expect(find.text('¿Grecia 1?'), findsOneWidget);
      expect(find.text(es.reviewRemaining(1)), findsOneWidget);
    });

    testWidgets('un tema: los elementos de ese espacio', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?', '¿Grecia 2?']);
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Antigüedad'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: items['Grecia']!, spaceId: space.id);
      await openEntry(tester);

      await chooseScope(tester, StudyScopeKind.space, space.id);

      expect(scopeName(tester), 'Antigüedad');
      expect(countOf(tester, 'review-entry-new'), '2');
    });

    testWidgets('un cuaderno: los elementos que tiene', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      final notebooks = harness.container.read(notebookRepositoryProvider);
      final notebook = await notebooks.create(
        name: 'Para el examen',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: notebook.id, itemId: items['Roma']!);
      await openEntry(tester);

      await chooseScope(tester, StudyScopeKind.notebook, notebook.id);

      expect(countOf(tester, 'review-entry-new'), '1');
      await tester.tap(find.byKey(const Key('review-entry-start')));
      await tester.pumpAndSettle();
      expect(find.text('¿Roma 1?'), findsOneWidget);
    });

    testWidgets('una etiqueta: solo las que se usan, con su categoría', (
      tester,
    ) async {
      final db = harness.database;
      final now = DateTime(2026, 9, 11);
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'cat',
              name: 'Período',
              createdAt: now,
            ),
          );
      for (final (id, name) in [('rom', 'Roma antigua'), ('sin', 'Sin uso')]) {
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: id,
                definitionId: 'cat',
                value: name,
                createdAt: now,
                parentId: const Value(null),
              ),
            );
      }
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: items['Roma']!,
              propertyValueId: 'rom',
            ),
          );
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);

      await tester.tap(find.byKey(const Key('review-entry-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scope-kind-value')));
      await tester.pumpAndSettle();
      expect(find.text('Roma antigua'), findsOneWidget);
      expect(find.text('Período'), findsOneWidget);
      expect(find.text('Sin uso'), findsNothing);
      await tester.tap(find.byKey(const Key('scope-option-rom')));
      await tester.pumpAndSettle();

      expect(countOf(tester, 'review-entry-new'), '1');
    });

    testWidgets('la búsqueda filtra los elementos', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);

      await tester.tap(find.byKey(const Key('review-entry-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scope-kind-item')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('scope-option-${items['Roma']}')), findsOneWidget);
      expect(
        find.byKey(Key('scope-option-${items['Grecia']}')),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('scope-search')), 'Grecia');
      await tester.pumpAndSettle();

      expect(find.byKey(Key('scope-option-${items['Roma']}')), findsNothing);
      expect(
        find.byKey(Key('scope-option-${items['Grecia']}')),
        findsOneWidget,
      );
    });

    testWidgets('«Todo» vuelve a estudiar todo', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);
      await chooseScope(tester, StudyScopeKind.item, items['Roma']!);
      expect(countOf(tester, 'review-entry-new'), '1');

      await tester.tap(find.byKey(const Key('review-entry-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scope-kind-all')));
      await tester.pumpAndSettle();

      expect(harness.container.read(reviewEntryScopeProvider).isAll, isTrue);
      expect(countOf(tester, 'review-entry-new'), '2');
    });

    testWidgets('un recorte que ya no existe lo dice y deja volver a '
        'estudiar todo', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      harness.container.read(reviewEntryScopeProvider.notifier).state =
          const StudyScope.notebook('borrado');
      await openEntry(tester);

      expect(
        find.byKey(const Key('review-entry-count-failed')),
        findsOneWidget,
      );
      expect(find.text(es.reviewEntryScopeMissing), findsOneWidget);

      await tester.tap(find.text(es.reviewEntryScopeReset));
      await tester.pumpAndSettle();

      expect(countOf(tester, 'review-entry-new'), '1');
    });
  });

  group('la dirección de la sesión', () {
    test('se arma con el tipo y el id, y sin tipo es todo', () {
      expect(RoutePaths.reviewSessionFor(), '/review/session');
      expect(
        RoutePaths.reviewSessionFor(kind: 'item', id: 'a b'),
        '/review/session?kind=item&id=a+b',
      );
      expect(
        RoutePaths.reviewSessionFor(practice: true),
        '/review/session?practice=1',
      );
    });

    testWidgets('abrirla con un elemento estudia solo ese', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);

      harness.pushTo(
        RoutePaths.reviewSessionFor(kind: 'item', id: items['Grecia']),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Grecia 1?'), findsOneWidget);
      expect(find.text(es.reviewRemaining(1)), findsOneWidget);
    });

    testWidgets('un tipo desconocido, o sin id, estudia todo', (tester) async {
      await addCards('Roma', ['¿Roma 1?']);
      await addCards('Grecia', ['¿Grecia 1?']);
      await openEntry(tester);

      harness.pushTo('/review/session?kind=algo&id=x');
      await tester.pumpAndSettle();
      expect(find.text(es.reviewRemaining(2)), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      harness.pushTo('/review/session?kind=item');
      await tester.pumpAndSettle();
      expect(find.text(es.reviewRemaining(2)), findsOneWidget);
    });
  });
}
