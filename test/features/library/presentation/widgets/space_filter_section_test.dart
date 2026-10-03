import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La sección «Tema» de los filtros, sola: la misma en la Biblioteca y en el
/// Explorador —las pruebas de cada pantalla miran que esté y qué filtra; acá,
/// cómo se comporta—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  /// Lo que la sección le fue avisando a quien la usa, en orden.
  late List<String?> changes;

  setUp(() async {
    harness = await LibraryHarness.create();
    changes = [];
  });

  Future<Space> createSpace(String name) async =>
      (await harness.container
              .read(organizeRepositoryProvider)
              .createSpace(name))
          .getRight()
          .toNullable()!;

  Future<List<String>> spaceNames() async => [
    for (final row
        in await harness.database.select(harness.database.spaces).get())
      row.name,
  ];

  /// La sección como la arma un panel de filtros: en una columna que se
  /// desplaza, con el tema elegido guardado afuera de ella.
  Future<void> pumpSection(WidgetTester tester) async {
    String? selected;
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SpaceFilterSection(
                    selectedSpaceId: selected,
                    onChanged: (spaceId) {
                      changes.add(spaceId);
                      setState(() => selected = spaceId);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chips() => find.descendant(
    of: find.byKey(SpaceFilterSection.chipsKey),
    matching: find.byType(FilterChip),
  );

  RawScrollbar scrollbar(WidgetTester tester) => tester.widget<RawScrollbar>(
    find.descendant(
      of: find.byKey(SpaceFilterSection.chipsKey),
      matching: find.byType(RawScrollbar),
    ),
  );

  Future<void> typeNewSpaceName(WidgetTester tester, String name) async {
    await tester.tap(find.text(es.spacesNewAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      name,
    );
  }

  group('con temas', () {
    testWidgets('un chip por tema, sin nada que crear', (tester) async {
      await createSpace('Cocina');
      await createSpace('Filosofía');
      await pumpSection(tester);

      expect(chips(), findsNWidgets(2));
      expect(find.text(es.spacesFilterEmptyMessage), findsNothing);
      expect(find.text(es.spacesNewAction), findsNothing);
    });

    testWidgets('tocar uno lo elige, otro lo reemplaza y el elegido lo '
        'suelta', (tester) async {
      final cocina = await createSpace('Cocina');
      final filosofia = await createSpace('Filosofía');
      await pumpSection(tester);

      await tester.tap(find.text('Cocina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(changes, [cocina.id, filosofia.id, null]);
    });

    testWidgets('con pocos, sin barra de desplazamiento', (tester) async {
      await createSpace('Cocina');
      await createSpace('Filosofía');
      await pumpSection(tester);

      expect(scrollbar(tester).thumbVisibility, isFalse);
    });

    testWidgets('con muchos, un alto tope, la barra a la vista y el último '
        'al alcance', (tester) async {
      // Número adelante y largo parejo: el orden alfabético es el numérico.
      for (var i = 10; i < 50; i++) {
        await createSpace('$i Tema bastante largo');
      }
      await pumpSection(tester);

      final area = find.byKey(SpaceFilterSection.chipsKey);
      // Tres filas y media de chips de 48 con su separación, no cuarenta.
      expect(tester.getSize(area).height, lessThanOrEqualTo(200));
      expect(scrollbar(tester).thumbVisibility, isTrue);

      final last = find.descendant(
        of: area,
        matching: find.text('49 Tema bastante largo'),
      );
      await tester.dragUntilVisible(
        last,
        find.descendant(of: area, matching: find.byType(Scrollable)),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();

      expect(changes, hasLength(1));
      expect(changes.single, isNotNull);
    });

    testWidgets('borrar el elegido lo suelta antes, y sin ninguno vuelve el '
        'estado vacío', (tester) async {
      final cocina = await createSpace('Cocina');
      await pumpSection(tester);

      await tester.tap(find.text('Cocina'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.librarySpaceManageTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction).last);
      await tester.pumpAndSettle();

      expect(changes, [cocina.id, null]);
      expect(await spaceNames(), isEmpty);
      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);
    });
  });

  group('sin temas', () {
    testWidgets('dice para qué sirven y ofrece crear el primero', (
      tester,
    ) async {
      await pumpSection(tester);

      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, es.spacesNewAction),
        findsOneWidget,
      );
      expect(find.byKey(SpaceFilterSection.chipsKey), findsNothing);
    });

    testWidgets('«Nuevo tema» lo crea con el diálogo de siempre y lo muestra '
        'como chip, sin elegirlo', (tester) async {
      await pumpSection(tester);

      await typeNewSpaceName(tester, 'Filosofía');
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();

      expect(await spaceNames(), ['Filosofía']);
      expect(chips(), findsOneWidget);
      expect(tester.widget<FilterChip>(chips()).selected, isFalse);
      expect(changes, isEmpty);
      expect(find.text(es.spacesFilterEmptyMessage), findsNothing);
    });

    testWidgets('cancelar el diálogo no crea nada', (tester) async {
      await pumpSection(tester);

      await typeNewSpaceName(tester, 'Filosofía');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await spaceNames(), isEmpty);
      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);
    });

    testWidgets('el nombre de una etiqueta avisa, igual que al crearlo desde '
        'el selector de temas', (tester) async {
      await harness.container
          .read(organizeRepositoryProvider)
          .getOrCreateTag('Filosofía');
      await pumpSection(tester);

      await typeNewSpaceName(tester, 'filosofia');
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();

      expect(find.text(es.spacesNameIsTagTitle), findsOneWidget);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await spaceNames(), isEmpty);
    });
  });
}
