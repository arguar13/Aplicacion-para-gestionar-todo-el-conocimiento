import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/explorer/presentation/providers/explorer_providers.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Igual que en `item_detail_screen_test.dart`: se identifica por
  /// diferencia de conjuntos, no "el primero de la lista", porque dos
  /// capturas en la misma prueba comparten el mismo instante bajo el reloj
  /// fijo de las pruebas.
  Future<String> captureAndGetId(String input) async {
    Future<Set<String>> currentIds() async =>
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .map((i) => i.id)
            .toSet();

    final before = await currentIds();
    await harness.capture(input);
    final after = await currentIds();

    return after.difference(before).single;
  }

  Future<void> pumpExplorer(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const ExplorerScreen()));
    await tester.pumpAndSettle();
  }

  /// El panel de filtros vive detrás de este botón, igual que en
  /// `library_screen.dart` —ver `openFilters`/`closeFilters` ahí—.
  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
    await tester.pumpAndSettle();
  }

  Future<void> closeFilters(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('sin nada procesado todavía, explica qué va a aparecer acá', (
    tester,
  ) async {
    await pumpExplorer(tester);

    expect(find.text(es.explorerEmptyTitle), findsOneWidget);
  });

  testWidgets('lo ya procesado aparece en una lista, sin ninguna carpeta '
      'que abrir primero', (tester) async {
    await captureAndGetId('una nota cualquiera');

    await pumpExplorer(tester);

    expect(find.text('una nota cualquiera'), findsOneWidget);
  });

  testWidgets('filtrar por etiqueta deja solo lo que la tiene puesta', (
    tester,
  ) async {
    final tagged = await captureAndGetId('sobre epistemología');
    await captureAndGetId('sobre otra cosa');
    final item =
        (await harness.container
                .read(libraryRepositoryProvider)
                .findById(tagged))
            .getRight()
            .toNullable()!;
    final tag =
        (await harness.container
                .read(organizeRepositoryProvider)
                .getOrCreateTag('Filosofía'))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .save(item.copyWith(tags: [tag]));

    await pumpExplorer(tester);
    await openFilters(tester);
    await tester.tap(find.text('Filosofía'));
    await closeFilters(tester);

    expect(find.text('sobre epistemología'), findsOneWidget);
    expect(find.text('sobre otra cosa'), findsNothing);
  });

  testWidgets('las etiquetas no aparecen además como una categoría de '
      'propiedades: Tema ya es "Etiquetas"', (tester) async {
    final tagged = await captureAndGetId('sobre epistemología');
    final item =
        (await harness.container
                .read(libraryRepositoryProvider)
                .findById(tagged))
            .getRight()
            .toNullable()!;
    final tag =
        (await harness.container
                .read(organizeRepositoryProvider)
                .getOrCreateTag('Filosofía'))
            .getRight()
            .toNullable()!;
    await harness.container
        .read(libraryRepositoryProvider)
        .save(item.copyWith(tags: [tag]));

    await pumpExplorer(tester);
    await openFilters(tester);

    // Desde F8 una etiqueta es un valor de la categoría Tema. Las dos
    // secciones filtran por el mismo valor: sin esconder Tema de las
    // categorías, cada etiqueta se vería dos veces.
    expect(find.text('Filosofía'), findsOneWidget);
    expect(find.text('Tema'), findsNothing);
  });

  testWidgets('filtrar por valor de propiedad deja solo lo que lo tiene '
      'asignado', (tester) async {
    final roman = await captureAndGetId('sobre las tácticas de César');
    await captureAndGetId('sobre otra cosa');
    final organize = harness.container.read(organizeRepositoryProvider);
    final definition = (await organize.getOrCreatePropertyDefinition(
      'Región',
    )).getRight().toNullable()!;
    await organize.assignProperty(
      itemId: roman,
      definitionId: definition.id,
      value: 'Roma',
    );

    await pumpExplorer(tester);
    await openFilters(tester);
    await tester.tap(find.text('Roma'));
    await closeFilters(tester);

    expect(find.text('sobre las tácticas de César'), findsOneWidget);
    expect(find.text('sobre otra cosa'), findsNothing);
  });

  testWidgets(
    'unos filtros que no dejan pasar nada ofrecen limpiarlos, sin perder '
    'lo que ya estaba',
    (tester) async {
      await captureAndGetId('una nota cualquiera');

      await pumpExplorer(tester);
      await openFilters(tester);
      await tester.tap(find.text(es.sourceKindDocument));
      await closeFilters(tester);

      expect(find.text(es.explorerEmptyFilteredTitle), findsOneWidget);

      await tester.tap(find.text(es.libraryClearFilters));
      await tester.pumpAndSettle();

      expect(find.text('una nota cualquiera'), findsOneWidget);
    },
  );

  group('el tema, igual que en la Biblioteca', () {
    Future<Space> createSpace(String name) async =>
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!;

    /// El chip del tema [name] adentro del panel —y no el que muestra el
    /// tema elegido debajo del título, que se llama igual—.
    Finder spaceChip(String name) => find.descendant(
      of: find.byKey(SpaceFilterSection.chipsKey),
      matching: find.text(name),
    );

    Badge filtersBadge(WidgetTester tester) => tester.widget<Badge>(
      find.ancestor(
        of: find.byTooltip(es.libraryFiltersTooltip),
        matching: find.byType(Badge),
      ),
    );

    testWidgets('va arriba de «Tipo»', (tester) async {
      await createSpace('Filosofía');
      await pumpExplorer(tester);
      await openFilters(tester);

      final spaceY = tester
          .getTopLeft(find.text(es.libraryFilterSpaceLabel.toUpperCase()))
          .dy;
      final typeY = tester
          .getTopLeft(find.text(es.libraryFilterTypeLabel.toUpperCase()))
          .dy;
      expect(spaceY, lessThan(typeY));
      expect(spaceChip('Filosofía'), findsOneWidget);
    });

    testWidgets('elegir un tema deja solo lo suyo, cuenta en la insignia y '
        'se ve debajo del título', (tester) async {
      final inside = await captureAndGetId('dentro del tema');
      await captureAndGetId('fuera del tema');
      final space = await createSpace('Filosofía');
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: inside, spaceId: space.id);

      await pumpExplorer(tester);
      expect(filtersBadge(tester).isLabelVisible, isFalse);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.text('dentro del tema'), findsOneWidget);
      expect(find.text('fuera del tema'), findsNothing);
      final badge = filtersBadge(tester);
      expect(badge.isLabelVisible, isTrue);
      expect((badge.label! as Text).data, '1');
      expect(find.widgetWithText(InputChip, 'Filosofía'), findsOneWidget);

      // Tocarlo de nuevo lo suelta: es una carpeta en la que se entra y se
      // sale, no un filtro que se suma.
      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.text('fuera del tema'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Filosofía'), findsNothing);
      expect(filtersBadge(tester).isLabelVisible, isFalse);
    });

    testWidgets('la cruz del chip de debajo del título sale del tema', (
      tester,
    ) async {
      await captureAndGetId('fuera del tema');
      await createSpace('Filosofía');
      await pumpExplorer(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      await tester.tap(find.byTooltip(es.libraryLeaveSpaceTooltip));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(explorerQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(find.text('fuera del tema'), findsOneWidget);
    });

    testWidgets('«Limpiar filtros» también suelta el tema', (tester) async {
      await captureAndGetId('fuera del tema');
      await createSpace('Filosofía');
      await pumpExplorer(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryClearFilters).last);
      await tester.pumpAndSettle();
      await closeFilters(tester);

      final query = harness.container.read(explorerQueryNotifierProvider);
      expect(query.spaceId, isNull);
      // Lo procesado sigue siendo lo único que se ve: eso no es un filtro.
      expect(query.processingStates, {ProcessingState.ready});
      expect(filtersBadge(tester).isLabelVisible, isFalse);
      expect(find.text('fuera del tema'), findsOneWidget);
    });

    testWidgets('sin ningún tema creado, la sección está igual y ofrece '
        'crear el primero', (tester) async {
      await pumpExplorer(tester);
      await openFilters(tester);

      expect(
        find.text(es.libraryFilterSpaceLabel.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);

      await tester.tap(find.text(es.spacesNewAction));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Cocina',
      );
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();

      expect(spaceChip('Cocina'), findsOneWidget);
      expect(
        harness.container.read(explorerQueryNotifierProvider).spaceId,
        isNull,
      );
    });

    testWidgets('borrar el tema elegido sale de él', (tester) async {
      await captureAndGetId('fuera del tema');
      await createSpace('Cocina');
      await pumpExplorer(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Cocina'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.librarySpaceManageTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction).last);
      await tester.pumpAndSettle();

      expect(
        harness.container.read(explorerQueryNotifierProvider).spaceId,
        isNull,
      );
      // Sin ningún tema, la sección vuelve a ofrecer crear uno.
      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);
      await closeFilters(tester);
      expect(find.text('fuera del tema'), findsOneWidget);
    });
  });
}
