import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_pager.dart';

import '../support/deck_widget_harness.dart';
import '../support/sample_decks.dart';

/// El visor de diapositivas (F43, punto 5): de a una, con la transición del
/// diseño, o de golpe sin animaciones; con flechas, botones y la tira de
/// miniaturas, todos de acuerdo en cuál se ve.
void main() {
  final deck = sampleDeck();

  Future<DeckPagerController> pumpPager(
    WidgetTester tester, {
    DeckTransition transition = DeckTransition.slide,
    bool disableAnimations = false,
    double width = 412,
    double textScale = 1,
    bool dark = false,
  }) async {
    final controller = DeckPagerController();
    addTearDown(controller.dispose);
    await pumpDeckScreen(
      tester,
      Column(
        children: [
          Expanded(
            child: DeckPager(
              deck: deck,
              design: DeckDesign(transition: transition),
              controller: controller,
              autofocus: true,
            ),
          ),
          DeckThumbnails(
            deck: deck,
            design: DeckDesign(transition: transition),
            controller: controller,
          ),
        ],
      ),
      width: width,
      textScale: textScale,
      dark: dark,
      disableAnimations: disableAnimations,
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Finder slide(int index) => find.byKey(ValueKey('deck-pager-slide-$index'));

  String counter(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('deck-pager-counter'))).data!;

  testWidgets('muestra la primera y cuántas hay', (tester) async {
    await pumpPager(tester);
    expect(counter(tester), '1 / 12');
    expect(slide(0), findsOneWidget);
    final previous = tester.widget<IconButton>(
      find.byKey(const Key('deck-pager-previous')),
    );
    expect(previous.onPressed, isNull);
  });

  testWidgets('deslizar: la siguiente entra corriéndose', (tester) async {
    await pumpPager(tester);
    await tester.tap(find.byKey(const Key('deck-pager-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // A mitad de camino se ven las dos.
    expect(slide(0), findsOneWidget);
    expect(slide(1), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    await tester.pumpAndSettle();
    expect(counter(tester), '2 / 12');
  });

  testWidgets('fundido: las dos quedan en su lugar y una se funde en otra', (
    tester,
  ) async {
    await pumpPager(tester, transition: DeckTransition.fade);
    await tester.tap(find.byKey(const Key('deck-pager-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .where((o) => o > 0 && o < 1);
    expect(opacities, isNotEmpty);
    // La que entra está en el mismo lugar que la que sale.
    expect(
      tester.getTopLeft(slide(1)).dx,
      closeTo(tester.getTopLeft(slide(0)).dx, 1),
    );
    await tester.pumpAndSettle();
    expect(counter(tester), '2 / 12');
  });

  testWidgets('zoom suave: la que entra crece mientras aparece', (
    tester,
  ) async {
    await pumpPager(tester, transition: DeckTransition.zoom);
    await tester.tap(find.byKey(const Key('deck-pager-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final transforms = tester.widgetList<Transform>(
      find.ancestor(of: slide(1), matching: find.byType(Transform)),
    );
    // La escala horizontal de cada transformación.
    final scales = transforms
        .map((t) => t.transform.storage[0])
        .where((s) => (s - 1).abs() > 0.001);
    expect(scales, isNotEmpty);
    await tester.pumpAndSettle();
    expect(counter(tester), '2 / 12');
  });

  testWidgets('sin animaciones del sistema, el cambio es de golpe', (
    tester,
  ) async {
    await pumpPager(
      tester,
      transition: DeckTransition.fade,
      disableAnimations: true,
    );
    expect(find.byType(PageView), findsNothing);
    await tester.tap(find.byKey(const Key('deck-pager-next')));
    await tester.pump();
    expect(slide(1), findsOneWidget);
    expect(slide(0), findsNothing);
    expect(counter(tester), '2 / 12');
  });

  testWidgets('con la transición «Ninguna», deslizar el dedo cambia de golpe', (
    tester,
  ) async {
    await pumpPager(tester, transition: DeckTransition.none);
    expect(find.byType(PageView), findsNothing);
    await tester.drag(slide(0), const Offset(-200, 0));
    await tester.pump();
    expect(slide(1), findsOneWidget);
    await tester.drag(slide(1), const Offset(200, 0));
    await tester.pump();
    expect(slide(0), findsOneWidget);
    expect(counter(tester), '1 / 12');
  });

  testWidgets('deslizar con el dedo también mueve el contador', (tester) async {
    await pumpPager(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(counter(tester), '2 / 12');
  });

  testWidgets('en la computadora, con el teclado', (tester) async {
    await pumpPager(tester, disableAnimations: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(counter(tester), '2 / 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(counter(tester), '12 / 12');
    final next = tester.widget<IconButton>(
      find.byKey(const Key('deck-pager-next')),
    );
    expect(next.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(counter(tester), '12 / 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(counter(tester), '11 / 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(counter(tester), '1 / 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(counter(tester), '1 / 12');
  });

  testWidgets('la tira y el visor van juntos', (tester) async {
    final controller = await pumpPager(tester);
    await tester.tap(find.byKey(const ValueKey('deck-thumbnail-2')));
    await tester.pumpAndSettle();
    expect(counter(tester), '3 / 12');
    expect(slide(2), findsOneWidget);
    expect(controller.index, 2);

    await tester.tap(find.byKey(const Key('deck-pager-next')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('deck-thumbnail-3'))),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('en un teléfono angosto con letra grande, en claro y oscuro', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await pumpPager(tester, width: 360, textScale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('deck-pager-next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 / 12'), findsOneWidget);
    }
  });
}
