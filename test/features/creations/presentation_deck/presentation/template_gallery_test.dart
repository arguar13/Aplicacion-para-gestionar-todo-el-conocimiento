import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/template_gallery.dart';

import '../support/deck_widget_harness.dart';
import '../support/sample_decks.dart';

/// La galería de plantillas (F43, y las doce de F45): las veintiocho en sus
/// seis familias, cada una con una muestra en vivo del propio mazo, y elegir
/// una cambia el diseño.
void main() {
  final deck = sampleDeck();
  const design = DeckDesign(
    paletteIndex: 2,
    customColor: 0xFF123456,
    fontPair: 'friendly',
    density: DeckDensity.airy,
    aspect: DeckAspect.standard,
  );

  Future<List<DeckDesign>> pumpGallery(
    WidgetTester tester, {
    double width = 1000,
    double height = 5000,
    double textScale = 1,
    bool dark = false,
  }) async {
    final chosen = <DeckDesign>[];
    await pumpDeckScreen(
      tester,
      TemplateGallery(deck: deck, design: design, onChanged: chosen.add),
      width: width,
      height: height,
      textScale: textScale,
      dark: dark,
    );
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('las seis familias y las veintiocho plantillas', (tester) async {
    await pumpGallery(tester);
    for (final family in [
      'Clásicas',
      'Modernas',
      'Gráficas',
      'Oscuras',
      'Cálidas y creativas',
      'Sobrias de trabajo',
    ]) {
      expect(find.text(family), findsOneWidget);
    }
    for (final id in DeckTemplateId.values) {
      expect(find.byKey(ValueKey('template-${id.id}')), findsOneWidget);
    }
    expect(find.text('Papel recortado'), findsOneWidget);
    expect(find.text('Pizarra blanca'), findsOneWidget);
    expect(find.text('Art déco'), findsOneWidget);
  });

  testWidgets('las de F45 elegidas devuelven su plantilla', (tester) async {
    final chosen = await pumpGallery(tester);
    for (final id in [DeckTemplateId.bauhaus, DeckTemplateId.blueprint]) {
      await tester.tap(find.byKey(ValueKey('template-${id.id}')));
      expect(chosen.last.template, id);
      expect(chosen.last.density, DeckDensity.airy);
    }
  });

  testWidgets('cada muestra es el propio mazo, con esa plantilla', (
    tester,
  ) async {
    await pumpGallery(tester);
    for (final id in DeckTemplateId.values) {
      final views = tester
          .widgetList<SlideView>(
            find.descendant(
              of: find.byKey(ValueKey('template-${id.id}')),
              matching: find.byType(SlideView),
            ),
          )
          .toList();
      expect(views.map((v) => v.slide), [deck.slides[0], deck.slides[1]]);
      for (final view in views) {
        expect(view.design.template, id);
        // Con su paleta y su letra de fábrica, y la forma que eligió la
        // persona.
        expect(view.design.paletteIndex, 0);
        expect(view.design.customColor, isNull);
        expect(view.design.fontPair, isNull);
        expect(view.design.aspect, DeckAspect.standard);
      }
    }
  });

  testWidgets('la elegida se marca, y elegir otra devuelve el diseño nuevo', (
    tester,
  ) async {
    final chosen = await pumpGallery(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('template-editorial'))),
      isSemantics(label: 'Editorial, elegida', isSelected: true),
    );
    await tester.tap(find.byKey(const ValueKey('template-neon')));
    expect(chosen.single.template, DeckTemplateId.neon);
    expect(chosen.single.paletteIndex, 0);
    expect(chosen.single.customColor, isNull);
    expect(chosen.single.fontPair, isNull);
    expect(chosen.single.density, DeckDensity.airy);
    expect(chosen.single.aspect, DeckAspect.standard);
  });

  testWidgets('en un teléfono con letra grande, en claro y oscuro', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await pumpGallery(
        tester,
        width: 360,
        height: 760,
        textScale: 2,
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      // Hasta el final, pasando por todas.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const ValueKey('template-blueprint')), findsOneWidget);
    }
  });
}
