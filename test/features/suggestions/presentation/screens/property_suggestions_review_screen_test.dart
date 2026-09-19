import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/screens/property_suggestions_review_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Un repositorio que delega en el real salvo `acceptMany`, que falla: la
/// atomicidad real se prueba en `suggestion_repository_impl_test`; acá importa
/// qué hace la pantalla cuando aplicar falla.
class _FailingAccept implements SuggestionRepository {
  _FailingAccept(this._real);

  final SuggestionRepository _real;
  int acceptCalls = 0;

  @override
  Stream<List<PropertySuggestionGroup>>
  watchPendingPropertySuggestionGroups() =>
      _real.watchPendingPropertySuggestionGroups();

  @override
  Future<Either<Failure, int>> acceptMany(List<String> ids) async {
    acceptCalls++;
    return left(const Failure.unexpected(message: 'boom'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<Map<String, String>> seedItems(List<String> titles) async {
    for (final title in titles) {
      await harness.capture('Texto de $title', title: title);
    }
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return {for (final item in items) item.title: item.id};
  }

  late String regionId;

  Future<PropertySuggestion> suggest(String itemId, String value) async {
    final repository = harness.container.read(suggestionRepositoryProvider);
    return (await repository.createPropertySuggestion(
          targetItemId: itemId,
          definitionId: regionId,
          definitionName: 'Región',
          value: value,
          isNewValue: true,
        )).getRight().toNullable()!
        as PropertySuggestion;
  }

  Future<void> seedRegion() async {
    regionId =
        (await harness.container
                .read(organizeRepositoryProvider)
                .getOrCreatePropertyDefinition('Región'))
            .getRight()
            .toNullable()!
            .id;
  }

  /// La pantalla dentro de un router mínimo: el botón que abre un elemento
  /// navega, y `context.push` necesita un router arriba.
  Widget wrapWithRouter() => UncontrolledProviderScope(
    container: harness.container,
    child: MaterialApp.router(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PropertySuggestionsReviewScreen(),
          ),
          GoRoute(
            path: RoutePaths.itemDetailPattern,
            builder: (_, state) => Scaffold(
              body: Text('detalle de ${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithRouter());
    await tester.pumpAndSettle();
  }

  Finder group(String title) => find.widgetWithText(ExpansionTile, title);

  /// El casillero del grupo: el primero del árbol, antes que los de sus filas.
  Finder groupCheckbox(String title) =>
      find.descendant(of: group(title), matching: find.byType(Checkbox)).first;

  Finder row(String title) => find.widgetWithText(CheckboxListTile, title);

  Future<Map<String, SuggestionStatus>> statuses() async => {
    for (final s
        in await harness.database.select(harness.database.suggestions).get())
      s.targetItemId: s.status,
  };

  testWidgets('agrupa por valor, con cuántos elementos son, el aviso y nada '
      'marcado', (tester) async {
    final ids = await seedItems(['A', 'B', 'C']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'roma');
    await suggest(ids['C']!, 'Cartago');

    await pumpScreen(tester);

    expect(find.text(es.suggestionReviewTitle), findsOneWidget);
    expect(group('Región: Roma'), findsOneWidget);
    expect(group('Región: Cartago'), findsOneWidget);
    expect(find.text(es.suggestionReviewGroupCount(2)), findsOneWidget);
    expect(find.text(es.suggestionReviewGroupCount(1)), findsOneWidget);
    // Ningún valor existe todavía: los dos grupos lo crearían.
    expect(find.text(es.suggestionsNewValueBadge), findsNWidgets(2));
    expect(find.text(es.suggestionReviewHint), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('el grupo más grande arranca desplegado y cada fila muestra el '
      'elemento con el comienzo de su texto', (tester) async {
    final ids = await seedItems(['A', 'B', 'C']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'Roma');
    await suggest(ids['C']!, 'Cartago');

    await pumpScreen(tester);

    expect(row('A'), findsOneWidget);
    expect(row('B'), findsOneWidget);
    expect(find.text('Texto de A'), findsOneWidget);
    // El otro grupo, cerrado: su elemento no se ve.
    expect(row('C'), findsNothing);
  });

  testWidgets('marcar un elemento muestra la barra y deja el casillero del '
      'grupo a medias', (tester) async {
    final ids = await seedItems(['A', 'B']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'Roma');
    await pumpScreen(tester);

    await tester.tap(row('A'));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, es.suggestionReviewAccept(1)),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, es.suggestionReviewReject(1)),
      findsOneWidget,
    );
    expect(
      tester.widget<Checkbox>(groupCheckbox('Región: Roma')).value,
      isNull,
    );
  });

  testWidgets('el casillero del grupo marca todos sus elementos, y otra vez '
      'los desmarca', (tester) async {
    final ids = await seedItems(['A', 'B']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'Roma');
    await pumpScreen(tester);

    await tester.tap(groupCheckbox('Región: Roma'));
    await tester.pump();
    expect(
      find.widgetWithText(FilledButton, es.suggestionReviewAccept(2)),
      findsOneWidget,
    );
    expect(
      tester.widget<Checkbox>(groupCheckbox('Región: Roma')).value,
      isTrue,
    );

    await tester.tap(groupCheckbox('Región: Roma'));
    await tester.pump();
    expect(find.byType(FilledButton), findsNothing);
    expect(
      tester.widget<Checkbox>(groupCheckbox('Región: Roma')).value,
      isFalse,
    );
  });

  testWidgets('aceptar aplica solo lo marcado, como sugerido aceptado, y deja '
      'el resto pendiente', (tester) async {
    final ids = await seedItems(['A', 'B', 'C']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'Roma');
    await suggest(ids['C']!, 'Roma');
    await pumpScreen(tester);

    await tester.tap(row('A'));
    await tester.tap(row('C'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, es.suggestionReviewAccept(2)),
    );
    await tester.pumpAndSettle();

    final assigned = await harness.database
        .select(harness.database.itemPropertyValues)
        .get();
    expect({for (final a in assigned) a.itemId}, {ids['A'], ids['C']});
    expect(
      assigned.every((a) => a.origin == ItemPropertyOrigin.suggestedAccepted),
      isTrue,
    );
    // El valor del grupo se creó una sola vez.
    expect(
      await harness.database.select(harness.database.propertyValues).get(),
      hasLength(1),
    );
    expect(await statuses(), {
      ids['A']: SuggestionStatus.accepted,
      ids['B']: SuggestionStatus.pending,
      ids['C']: SuggestionStatus.accepted,
    });
    expect(find.text(es.suggestionReviewAccepted(2)), findsOneWidget);
    // Lo aplicado sale de la lista; lo que faltaba sigue, sin marcar.
    expect(row('A'), findsNothing);
    expect(row('B'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('descartar marca rechazadas las marcadas sin aplicar nada', (
    tester,
  ) async {
    final ids = await seedItems(['A', 'B']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await suggest(ids['B']!, 'Roma');
    await pumpScreen(tester);

    await tester.tap(groupCheckbox('Región: Roma'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(OutlinedButton, es.suggestionReviewReject(2)),
    );
    await tester.pumpAndSettle();

    expect(await statuses(), {
      ids['A']: SuggestionStatus.rejected,
      ids['B']: SuggestionStatus.rejected,
    });
    expect(
      await harness.database.select(harness.database.itemPropertyValues).get(),
      isEmpty,
    );
    expect(find.text(es.suggestionReviewRejected(2)), findsOneWidget);
    expect(find.text(es.suggestionReviewEmpty), findsOneWidget);
  });

  testWidgets('si aplicar falla, avisa y conserva la selección para '
      'reintentar', (tester) async {
    final ids = await seedItems(['A']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    final failing = _FailingAccept(
      harness.container.read(suggestionRepositoryProvider),
    );
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            suggestionRepositoryProvider.overrideWithValue(failing),
            // Un `ProviderScope` anidado no reescribe las dependencias
            // transitivas de lo que sobrescribe: el provider de grupos, que
            // lee el repositorio, se sobrescribe aparte o seguiría leyendo el
            // real.
            pendingPropertySuggestionGroupsProvider.overrideWith(
              (ref) => failing.watchPendingPropertySuggestionGroups(),
            ),
          ],
          child: const PropertySuggestionsReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(row('A'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, es.suggestionReviewAccept(1)),
    );
    await tester.pumpAndSettle();

    expect(failing.acceptCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(es.suggestionReviewAccepted(1)), findsNothing);
    // Sigue marcada, lista para reintentar.
    expect(
      find.widgetWithText(FilledButton, es.suggestionReviewAccept(1)),
      findsOneWidget,
    );
    expect(await statuses(), {ids['A']: SuggestionStatus.pending});
  });

  testWidgets('el botón de cada fila abre el detalle del elemento', (
    tester,
  ) async {
    final ids = await seedItems(['A']);
    await seedRegion();
    await suggest(ids['A']!, 'Roma');
    await pumpScreen(tester);

    await tester.tap(find.byTooltip(es.suggestionReviewOpenItem));
    await tester.pumpAndSettle();

    expect(find.text('detalle de ${ids['A']}'), findsOneWidget);
  });

  testWidgets('sin sugerencias muestra el estado vacío', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.suggestionReviewEmpty), findsOneWidget);
  });

  testWidgets('se abre con el router real', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.suggestionReview);
    await tester.pumpAndSettle();

    expect(find.byType(PropertySuggestionsReviewScreen), findsOneWidget);
  });
}
