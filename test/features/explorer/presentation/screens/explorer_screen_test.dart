import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
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
}
