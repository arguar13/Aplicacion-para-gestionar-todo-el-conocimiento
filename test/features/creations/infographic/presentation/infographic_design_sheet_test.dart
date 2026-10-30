import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_design_sheet.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';

import '../../presentation_deck/support/deck_widget_harness.dart';
import '../support/infographic_muestrario.dart';
import '../support/sample_infographics.dart';

/// La hoja para personalizar la infografía (F43): cada cambio se ve
/// enseguida en la lámina de muestra y se avisa; nada vuelve a la IA.
void main() {
  setUpAll(loadInfographicFonts);

  final sheet = sampleInfographic();

  Future<({List<InfographicDesign> changes, List<int> styleTaps})> openSheet(
    WidgetTester tester, {
    InfographicDesign design = const InfographicDesign(),
    double width = 412,
    double textScale = 1,
    bool dark = false,
    bool withGallery = true,
  }) async {
    final changes = <InfographicDesign>[];
    final styleTaps = <int>[];
    await pumpDeckScreen(
      tester,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => InfographicDesignSheet(
                sheet: sheet,
                design: design,
                onChanged: changes.add,
                onChangeStyle: withGallery ? () => styleTaps.add(1) : null,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
      width: width,
      textScale: textScale,
      dark: dark,
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return (changes: changes, styleTaps: styleTaps);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  InfographicDesign previewDesign(WidgetTester tester) => tester
      .widget<InfographicView>(
        find.byKey(const Key('infographic-design-preview')),
      )
      .design;

  testWidgets('arriba el título, la ✕ y la lámina', (tester) async {
    await openSheet(tester);
    expect(find.text('Personalizar la infografía'), findsOneWidget);
    expect(
      tester
          .widget<InfographicView>(
            find.byKey(const Key('infographic-design-preview')),
          )
          .sheet,
      sheet,
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Personalizar la infografía'), findsNothing);
  });

  testWidgets('cada opción cambia el diseño y la muestra enseguida', (
    tester,
  ) async {
    final (:changes, :styleTaps) = await openSheet(tester);

    await tapKey(tester, 'infographic-change-style');
    expect(styleTaps, [1]);

    await tapKey(tester, 'infographic-composition-columns');
    expect(changes.last.composition, InfographicComposition.columns);
    expect(previewDesign(tester).composition, InfographicComposition.columns);

    await tapKey(tester, 'infographic-palette-2');
    expect(changes.last.paletteIndex, 2);

    await tapKey(tester, 'infographic-fonts-book');
    expect(changes.last.fontPair, 'book');
    await tapKey(tester, 'infographic-fonts-style');
    expect(changes.last.fontPair, isNull);

    await tapKey(tester, 'infographic-orientation-square');
    expect(changes.last.orientation, InfographicOrientation.square);
    expect(previewDesign(tester).orientation, InfographicOrientation.square);

    await tapKey(tester, 'infographic-detail-concise');
    expect(changes.last.detail, InfographicDetail.concise);

    await tapKey(tester, 'infographic-icons-outline');
    expect(changes.last.iconLook, InfographicIconLook.outline);

    await tapKey(tester, 'infographic-background-gradient');
    expect(changes.last.background, InfographicBackground.gradient);

    // Lo anterior se acumula: cada cambio parte del último.
    expect(
      changes.last,
      const InfographicDesign(
        composition: InfographicComposition.columns,
        paletteIndex: 2,
        orientation: InfographicOrientation.square,
        detail: InfographicDetail.concise,
        iconLook: InfographicIconLook.outline,
        background: InfographicBackground.gradient,
      ),
    );
  });

  testWidgets('el color propio abre el tono, y una paleta lo saca', (
    tester,
  ) async {
    final (:changes, styleTaps: _) = await openSheet(tester);
    expect(find.byKey(const Key('infographic-hue')), findsNothing);
    await tapKey(tester, 'infographic-palette-custom');
    expect(changes.last.customColor, isNotNull);
    expect(find.byKey(const Key('infographic-hue')), findsOneWidget);
    final before = changes.last.customColor;
    await tester.ensureVisible(find.byKey(const Key('infographic-hue')));
    await tester.drag(
      find.byKey(const Key('infographic-hue')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(changes.last.customColor, isNot(before));
    await tapKey(tester, 'infographic-palette-1');
    expect(changes.last.customColor, isNull);
    expect(find.byKey(const Key('infographic-hue')), findsNothing);
  });

  testWidgets('sin galería, los estilos se eligen en la tira de la hoja', (
    tester,
  ) async {
    final (:changes, styleTaps: _) = await openSheet(
      tester,
      withGallery: false,
    );
    expect(find.byKey(const Key('infographic-change-style')), findsNothing);
    await tapKey(tester, 'infographic-style-geometric');
    expect(changes.last.style, InfographicStyleId.geometric);
    expect(previewDesign(tester).style, InfographicStyleId.geometric);
  });

  testWidgets('los íconos y el fondo marcan lo del estilo mientras no se '
      'elija otro', (tester) async {
    await openSheet(
      tester,
      design: const InfographicDesign(style: InfographicStyleId.swiss),
    );
    // Minimal suizo: íconos solos y fondo liso.
    Finder check(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byIcon(Icons.check),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('infographic-background-plain')),
    );
    expect(check('infographic-icons-bare'), findsOneWidget);
    expect(check('infographic-icons-soft'), findsNothing);
    expect(check('infographic-background-plain'), findsOneWidget);
    expect(check('infographic-background-texture'), findsNothing);
  });

  testWidgets('las composiciones y los estilos de F45 se eligen igual, y se '
      'anuncian por su nombre (a 360, letra al doble, en oscuro)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (:changes, styleTaps: _) = await openSheet(
      tester,
      width: 360,
      textScale: 2,
      dark: true,
      withGallery: false,
    );
    for (final composition in [
      InfographicComposition.verticalTimeline,
      InfographicComposition.comparisonTable,
      InfographicComposition.funnel,
      InfographicComposition.cycle,
      InfographicComposition.topicMap,
      InfographicComposition.statMosaic,
    ]) {
      // La tira se desliza de costado y arma sus tarjetas a medida: se
      // corre hasta que aparece la que se busca.
      final strip = find
          .ancestor(
            of: find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'infographic-composition-',
                      ),
                )
                .first,
            matching: find.byType(Scrollable),
          )
          .first;
      final tile = find.byKey(
        ValueKey('infographic-composition-${composition.jsonName}'),
      );
      await tester.scrollUntilVisible(tile, 200, scrollable: strip);
      await tapKey(tester, 'infographic-composition-${composition.jsonName}');
      expect(changes.last.composition, composition);
      expect(tester.takeException(), isNull);
    }
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('infographic-composition-stat_mosaic')),
      ),
      isSemantics(label: 'Estadísticas en mosaico, elegido', isSelected: true),
    );
    handle.dispose();
  });

  for (final (width, scale, dark) in [
    (360.0, 1.0, false),
    (360.0, 2.0, true),
    (900.0, 1.5, false),
  ]) {
    testWidgets('a $width de ancho, letra $scale${dark ? ', oscuro' : ''}: '
        'nada desborda', (tester) async {
      await openSheet(
        tester,
        width: width,
        textScale: scale,
        dark: dark,
        withGallery: false,
      );
      expect(tester.takeException(), isNull);
      // Hasta abajo de la hoja.
      await tester.ensureVisible(
        find.byKey(const ValueKey('infographic-background-gradient')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
