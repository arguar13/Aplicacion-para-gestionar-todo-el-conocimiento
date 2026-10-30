import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_design_sheet.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';

import '../support/deck_widget_harness.dart';
import '../support/sample_decks.dart';

/// La hoja para personalizar el diseño (F43): cada cambio se ve enseguida en
/// la diapositiva de muestra y se avisa; nada vuelve a la IA.
void main() {
  final deck = sampleDeck();

  Future<({List<DeckDesign> changes, List<int> templateTaps})> openSheet(
    WidgetTester tester, {
    DeckDesign design = const DeckDesign(),
    double width = 412,
    double textScale = 1,
    bool dark = false,
  }) async {
    final changes = <DeckDesign>[];
    final templateTaps = <int>[];
    await pumpDeckScreen(
      tester,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => DeckDesignSheet(
                deck: deck,
                design: design,
                slideIndex: 2,
                onChanged: changes.add,
                onChangeTemplate: () => templateTaps.add(1),
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
    return (changes: changes, templateTaps: templateTaps);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  DeckDesign previewDesign(WidgetTester tester) => tester
      .widget<SlideView>(find.byKey(const Key('deck-design-preview')))
      .design;

  testWidgets('arriba el título, la ✕ y la diapositiva que se estaba viendo', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Personalizar diseño'), findsOneWidget);
    final preview = tester.widget<SlideView>(
      find.byKey(const Key('deck-design-preview')),
    );
    expect(preview.slide, deck.slides[2]);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Personalizar diseño'), findsNothing);
  });

  testWidgets('cada opción cambia el diseño y la muestra enseguida', (
    tester,
  ) async {
    final (:changes, :templateTaps) = await openSheet(tester);

    await tapKey(tester, 'deck-palette-3');
    expect(changes.last.paletteIndex, 3);
    expect(previewDesign(tester).paletteIndex, 3);

    await tapKey(tester, 'deck-fonts-handwritten');
    expect(changes.last.fontPair, 'handwritten');
    await tapKey(tester, 'deck-fonts-template');
    expect(changes.last.fontPair, isNull);

    await tapKey(tester, 'deck-density-airy');
    expect(changes.last.density, DeckDensity.airy);

    await tapKey(tester, 'deck-background-gradient');
    expect(changes.last.background, DeckBackground.gradient);
    expect(previewDesign(tester).background, DeckBackground.gradient);

    await tapKey(tester, 'deck-transition-zoom');
    expect(changes.last.transition, DeckTransition.zoom);

    await tapKey(tester, 'deck-aspect-4:3');
    expect(changes.last.aspect, DeckAspect.standard);
    expect(previewDesign(tester).aspect, DeckAspect.standard);

    await tapKey(tester, 'deck-numbering');
    expect(changes.last.numbering, isFalse);
    await tapKey(tester, 'deck-footer');
    expect(changes.last.footer, isTrue);

    // Lo anterior se acumula: cada cambio parte del último.
    expect(
      changes.last,
      const DeckDesign(
        paletteIndex: 3,
        density: DeckDensity.airy,
        transition: DeckTransition.zoom,
        aspect: DeckAspect.standard,
        numbering: false,
        footer: true,
        background: DeckBackground.gradient,
      ),
    );

    await tapKey(tester, 'deck-change-template');
    expect(templateTaps, [1]);
  });

  testWidgets('el color propio tiñe la paleta y se elige con el tono', (
    tester,
  ) async {
    final (:changes, templateTaps: _) = await openSheet(tester);
    expect(find.byKey(const Key('deck-hue')), findsNothing);

    await tapKey(tester, 'deck-palette-custom');
    final first = changes.last.customColor;
    expect(first, isNotNull);
    expect(find.byKey(const Key('deck-hue')), findsOneWidget);

    await tester.drag(find.byKey(const Key('deck-hue')), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(changes.last.customColor, isNot(first));
    expect(previewDesign(tester).customColor, changes.last.customColor);

    // Volver a una paleta quita el color propio.
    await tapKey(tester, 'deck-palette-0');
    expect(changes.last.customColor, isNull);
    expect(find.byKey(const Key('deck-hue')), findsNothing);
  });

  testWidgets('el fondo (F45): de entrada el de la plantilla, y se elige '
      'liso, con su textura o en degradé', (tester) async {
    final (:changes, templateTaps: _) = await openSheet(tester);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('deck-background-texture')),
      ),
      isSemantics(isSelected: true),
    );
    await tapKey(tester, 'deck-background-plain');
    expect(changes.last.background, DeckBackground.plain);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('deck-background-plain'))),
      isSemantics(isSelected: true),
    );
    await tapKey(tester, 'deck-background-texture');
    expect(changes.last.background, DeckBackground.texture);
  });

  testWidgets('la elegida de cada grupo se marca', (tester) async {
    await openSheet(
      tester,
      design: const DeckDesign(paletteIndex: 4, fontPair: 'book'),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('deck-palette-4'))),
      isSemantics(isSelected: true, label: 'Paleta 5'),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('deck-fonts-book'))),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('en un teléfono con letra grande, en claro y oscuro', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await openSheet(tester, width: 360, textScale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      // Se llega hasta abajo sin que nada desborde.
      await tester.ensureVisible(find.byKey(const Key('deck-footer')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'deck-transition-none');
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'deck-background-gradient');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
    }
  });
}
