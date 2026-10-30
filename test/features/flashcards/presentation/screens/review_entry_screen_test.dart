import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_scope_picker.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/my_cards_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../creations/presentation/repasar_harness.dart';

/// La entrada a Repasar (F31, ola 2; F43, paso 6): «Para hoy» compacto, el
/// selector de Procesado y el camino a la sesión.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;
  late Map<String, String> items;

  setUp(() async {
    harness = await RepasarHarness.create();
    final library = harness.library;
    await library.capture('Roma\n\nTexto de Roma.', title: 'Roma');
    await library.capture('Grecia\n\nTexto de Grecia.', title: 'Grecia');
    final all =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    items = {for (final item in all) item.title: item.id};
  });

  Future<void> addCards(String id, List<String> fronts) async {
    for (final front in fronts) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: id, front: front, back: 'R de $front');
    }
  }

  Future<void> openEntry(WidgetTester tester) =>
      harness.openRepasar(tester, size: const Size(800, 1600));

  String countOf(WidgetTester tester, String key) => tester
      .widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      )
      .data!;

  String scopeName(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('repasar-scope-name'))).data!;

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('repasar-scope')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseScope(
    WidgetTester tester,
    String tab,
    CreationScope scope,
  ) async {
    await openPicker(tester);
    await tester.tap(find.byKey(Key('creation-scope-tab-$tab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('creation-scope-option-${scope.storageKey}')),
    );
    await tester.pumpAndSettle();
  }

  group('lo que hay para hoy, compacto', () {
    testWidgets('cuenta nuevas, aprendiendo y por repasar en una franja', (
      tester,
    ) async {
      await addCards(items['Roma']!, ['¿Uno?', '¿Dos?', '¿Tres?']);
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
      expect(
        find.descendant(
          of: find.byKey(const Key('review-entry-today')),
          matching: find.text(es.f43StudioTodayTitle),
        ),
        findsOneWidget,
      );
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
      await addCards(items['Roma']!, ['¿Uno?', '¿Dos?', '¿Tres?']);
      await openEntry(tester);

      expect(countOf(tester, 'review-entry-new'), '1');
      expect(find.text(es.reviewEntryNewBeyond(2)), findsOneWidget);
    });

    testWidgets('sin nada para estudiar, el vacío de siempre en la franja, '
        'sin «Empezar»', (tester) async {
      await openEntry(tester);

      expect(find.byKey(const Key('review-entry-start')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('review-entry-today')),
          matching: find.byKey(const Key('review-empty-without-cards')),
        ),
        findsOneWidget,
      );
      expect(find.text(es.reviewEmptyWithoutCards(2)), findsOneWidget);
    });

    testWidgets('se actualiza solo cuando aparece una tarjeta', (tester) async {
      await openEntry(tester);
      expect(find.byKey(const Key('review-entry-start')), findsNothing);

      await addCards(items['Roma']!, ['¿Nueva?']);
      await tester.pumpAndSettle();

      expect(countOf(tester, 'review-entry-new'), '1');
    });
  });

  group('empezar', () {
    testWidgets('abre la sesión con la primera tarjeta, y volver deja la '
        'entrada', (tester) async {
      await addCards(items['Roma']!, ['¿Uno?']);
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

    testWidgets('«Mis tarjetas» va adentro de «Para hoy», al lado de '
        '«Empezar», y lleva a su pantalla (M14)', (tester) async {
      await addCards(items['Roma']!, ['¿Uno?']);
      await openEntry(tester);

      final today = find.byKey(const Key('review-entry-today'));
      final cards = find.byKey(const Key('review-entry-cards'));
      final start = find.byKey(const Key('review-entry-start'));
      expect(find.descendant(of: today, matching: cards), findsOneWidget);
      expect(tester.widget(cards), isA<OutlinedButton>());
      // En una fila, a la izquierda de «Empezar».
      expect(tester.getCenter(cards).dy, tester.getCenter(start).dy);
      expect(tester.getCenter(cards).dx, lessThan(tester.getCenter(start).dx));
      // La fila de abajo, con «Estadísticas», ya no está.
      expect(find.byKey(const Key('review-entry-stats')), findsNothing);

      await tester.ensureVisible(cards);
      await tester.pumpAndSettle();
      await tester.tap(cards);
      await tester.pumpAndSettle();
      expect(find.byType(MyCardsScreen), findsOneWidget);
    });

    testWidgets('sin nada para hoy, «Mis tarjetas» sigue en la franja', (
      tester,
    ) async {
      await openEntry(tester);

      expect(find.byKey(const Key('review-entry-start')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('review-entry-today')),
          matching: find.byKey(const Key('review-entry-cards')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('en 360 dp con la letra al doble, los dos botones bajan uno '
        'debajo del otro, «Empezar» arriba, sin desbordar', (tester) async {
      await addCards(items['Roma']!, ['¿Uno?']);
      await harness.openRepasar(
        tester,
        size: const Size(360, 1600),
        textScale: 2,
      );
      final cards = find.byKey(const Key('review-entry-cards'));
      final start = find.byKey(const Key('review-entry-start'));
      // Con la letra al doble, «Para hoy» queda abajo de todo: se baja hasta
      // verlo entero.
      await tester.scrollUntilVisible(
        cards,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('review-entry')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(start).dy,
        lessThan(tester.getTopLeft(cards).dy),
      );
      final strip = tester.getRect(find.byKey(const Key('review-entry-today')));
      for (final button in [cards, start]) {
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(strip.left));
        expect(rect.right, lessThanOrEqualTo(strip.right));
      }
    });
  });

  group('el selector: todo sale de Procesado', () {
    testWidgets('«Todo lo procesado» por defecto, con sus cifras', (
      tester,
    ) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 2);
      await openEntry(tester);

      expect(scopeName(tester), es.f43StudioScopeAll);
      expect(
        tester.widget<Text>(find.byKey(const Key('repasar-scope-detail'))).data,
        '${es.f43StudioDocuments(1)} · ${es.f43StudioCards(2)}',
      );
    });

    testWidgets('la hoja tiene las cuatro pestañas y la Biblioteca no '
        'aparece', (tester) async {
      await harness.processed('p-roma', 'Roma procesada');
      await openEntry(tester);
      await openPicker(tester);

      for (final tab in ['all', 'document', 'notebook', 'topic']) {
        expect(find.byKey(Key('creation-scope-tab-$tab')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('creation-scope-tab-document')));
      await tester.pumpAndSettle();
      expect(find.text('Roma procesada'), findsOneWidget);
      // Las fuentes de la Biblioteca no son documentos procesados.
      expect(find.text('Roma'), findsNothing);
      expect(find.text('Grecia'), findsNothing);
    });

    testWidgets('un documento: «Para hoy» cuenta sus tarjetas y las de su '
        'fuente', (tester) async {
      await harness.processed(
        'p-roma',
        'Roma procesada',
        cards: 1,
        sourceItemId: items['Roma'],
      );
      await addCards(items['Roma']!, ['¿De la fuente 1?', '¿De la fuente 2?']);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      await openEntry(tester);
      expect(countOf(tester, 'review-entry-new'), '4');

      await chooseScope(
        tester,
        'document',
        const CreationScope.document('p-roma'),
      );

      expect(scopeName(tester), 'Roma procesada');
      expect(countOf(tester, 'review-entry-new'), '3');
      expect(harness.scope, const CreationScope.document('p-roma'));

      await tester.tap(find.byKey(const Key('review-entry-start')));
      await tester.pumpAndSettle();
      expect(find.text(es.reviewRemaining(3)), findsOneWidget);
    });

    testWidgets('la fila de un documento dice cuánto tiene y si ya tiene '
        'resumen', (tester) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 2);
      await openEntry(tester);
      await openPicker(tester);
      await tester.tap(find.byKey(const Key('creation-scope-tab-document')));
      await tester.pumpAndSettle();

      // En la hoja: debajo, «Lo creado» también dice sus tarjetas (M10).
      expect(
        find.descendant(
          of: find.byType(CreationScopePicker),
          matching: find.text(es.f43StudioCards(2)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un cuaderno: lo procesado que tiene', (tester) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 1);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      final notebooks = harness.container.read(notebookRepositoryProvider);
      final notebook = await notebooks.create(
        name: 'Para el examen',
        mode: NotebookMode.manual,
      );
      await notebooks.addItems(notebookId: notebook.id, itemIds: ['p-roma']);
      await openEntry(tester);

      await chooseScope(
        tester,
        'notebook',
        CreationScope.notebook(notebook.id),
      );

      expect(scopeName(tester), 'Para el examen');
      expect(countOf(tester, 'review-entry-new'), '1');
    });

    testWidgets('un tema del Atlas: solo los que tienen algo procesado', (
      tester,
    ) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 1);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      final organize = harness.container.read(organizeRepositoryProvider);
      final antiquity = (await organize.createSpace(
        'Antigüedad',
      )).getRight().toNullable()!;
      final empty = (await organize.createSpace(
        'Vacío',
      )).getRight().toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .setSpaces(itemIds: ['p-roma'], spaceIds: {antiquity.id});
      await openEntry(tester);
      await openPicker(tester);
      await tester.tap(find.byKey(const Key('creation-scope-tab-topic')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey(
            'creation-scope-option-${CreationScope.space(empty.id).storageKey}',
          ),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(
          ValueKey(
            'creation-scope-option-'
            '${CreationScope.space(antiquity.id).storageKey}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scopeName(tester), 'Antigüedad');
      expect(countOf(tester, 'review-entry-new'), '1');
    });

    testWidgets('la búsqueda filtra, también desde «Todo»', (tester) async {
      await harness.processed('p-roma', 'Roma procesada');
      await harness.processed('p-grecia', 'Grecia procesada');
      await openEntry(tester);
      await openPicker(tester);
      // Abre en «Todo», que busca en todo (M11).
      await tester.enterText(
        find.byKey(const Key('creation-scope-search')),
        'Grecia',
      );
      await tester.pumpAndSettle();

      expect(find.text('Grecia procesada'), findsOneWidget);
      expect(find.text('Roma procesada'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('creation-scope-search')),
        'Cartago',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.f43StudioPickerNoMatch('Cartago')), findsOneWidget);
    });

    testWidgets('los recientes: los últimos tres que se eligieron, el más '
        'nuevo primero (M11)', (tester) async {
      for (var i = 1; i <= 5; i++) {
        await harness.processed('p-$i', 'Doc $i');
      }
      final recents = harness.container.read(
        recentCreationScopesProvider.notifier,
      );
      for (var i = 1; i <= 5; i++) {
        recents.remember(CreationScope.document('p-$i'));
      }
      recents.remember(const CreationScope.allProcessed());
      await openEntry(tester);
      await openPicker(tester);

      final shown = [
        for (var i = 5; i >= 1; i--)
          find
              .byKey(ValueKey('creation-scope-recent-document:p-$i'))
              .evaluate()
              .isNotEmpty,
      ];
      expect(shown, [true, true, true, false, false]);
      final top = tester.getTopLeft(
        find.byKey(const ValueKey('creation-scope-recent-document:p-5')),
      );
      final next = tester.getTopLeft(
        find.byKey(const ValueKey('creation-scope-recent-document:p-4')),
      );
      expect(top.dy, lessThan(next.dy));

      // El cuarto ya no es reciente: está abajo, en «Todos».
      await tester.tap(
        find.byKey(const ValueKey('creation-scope-option-document:p-2')),
      );
      await tester.pumpAndSettle();
      expect(scopeName(tester), 'Doc 2');
      expect(
        harness.container.read(recentCreationScopesProvider).first,
        const CreationScope.document('p-2'),
      );
    });

    testWidgets('«Todo lo procesado» vuelve a todo', (tester) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 1);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      await openEntry(tester);
      await chooseScope(
        tester,
        'document',
        const CreationScope.document('p-roma'),
      );
      expect(countOf(tester, 'review-entry-new'), '1');

      await chooseScope(tester, 'all', const CreationScope.allProcessed());

      expect(harness.scope.isAll, isTrue);
      expect(scopeName(tester), es.f43StudioScopeAll);
      expect(countOf(tester, 'review-entry-new'), '2');
    });

    testWidgets('un recorte que ya no existe lo dice y deja volver a '
        'estudiar todo', (tester) async {
      await addCards(items['Roma']!, ['¿Roma 1?']);
      harness.container.read(repasarScopeProvider.notifier).state =
          const CreationScope.notebook('borrado');
      await openEntry(tester);

      expect(scopeName(tester), es.f43StudioScopeMissing);
      expect(find.text(es.f43StudioScopeMissingHint), findsOneWidget);
      expect(
        find.byKey(const Key('review-entry-count-failed')),
        findsOneWidget,
      );

      await tester.tap(find.text(es.reviewEntryScopeReset));
      await tester.pumpAndSettle();

      expect(harness.scope.isAll, isTrue);
      expect(countOf(tester, 'review-entry-new'), '1');
    });
  });

  group('con un recorte ya elegido (M6)', () {
    testWidgets('la dirección `/review?scope=` lo elige y lo suma a los '
        'recientes', (tester) async {
      await harness.processed('p-roma', 'Roma procesada', cards: 1);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);

      await harness.openRepasar(
        tester,
        location: RoutePaths.reviewFor('document:p-roma'),
      );

      expect(harness.scope, const CreationScope.document('p-roma'));
      expect(scopeName(tester), 'Roma procesada');
      expect(countOf(tester, 'review-entry-new'), '1');
      expect(harness.container.read(recentCreationScopesProvider), [
        const CreationScope.document('p-roma'),
      ]);
    });

    testWidgets('una clave que no se entiende deja el recorte que había', (
      tester,
    ) async {
      await harness.openRepasar(tester, location: '/review?scope=algo:');

      expect(harness.scope.isAll, isTrue);
    });

    test('la dirección se arma con la clave del recorte', () {
      expect(
        RoutePaths.reviewFor(const CreationScope.notebook('c 1').storageKey),
        '/review?scope=notebook%3Ac+1',
      );
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
      expect(
        RoutePaths.reviewSessionFor(
          kind: StudyScopeKind.processed.name,
          id: 'document:p',
        ),
        '/review/session?kind=processed&id=document%3Ap',
      );
    });

    testWidgets('abrirla con un elemento estudia solo ese', (tester) async {
      await addCards(items['Roma']!, ['¿Roma 1?']);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      await openEntry(tester);

      harness.library.pushTo(
        RoutePaths.reviewSessionFor(kind: 'item', id: items['Grecia']),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Grecia 1?'), findsOneWidget);
      expect(find.text(es.reviewRemaining(1)), findsOneWidget);
    });

    testWidgets('un tipo desconocido, o sin id, estudia todo', (tester) async {
      await addCards(items['Roma']!, ['¿Roma 1?']);
      await addCards(items['Grecia']!, ['¿Grecia 1?']);
      await openEntry(tester);

      harness.library.pushTo('/review/session?kind=algo&id=x');
      await tester.pumpAndSettle();
      expect(find.text(es.reviewRemaining(2)), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      harness.library.pushTo('/review/session?kind=item');
      await tester.pumpAndSettle();
      expect(find.text(es.reviewRemaining(2)), findsOneWidget);
    });
  });
}
