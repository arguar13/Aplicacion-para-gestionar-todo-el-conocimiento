import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';

import 'slide_test_support.dart';

/// Dibuja todas las diapositivas de [deck] con [design], una debajo de otra,
/// cada una de [width] de ancho, y devuelve los problemas de texto que haya
/// en cada una (vacío si nada desborda ni se sale del lienzo). Las
/// excepciones de dibujo —un `RenderFlex` que desborda, un error de
/// diseño— hacen fallar la prueba enseguida.
///
/// Con `MUESTRARIO_PNG=carpeta`, además guarda la hoja como [name].png.
Future<List<String>> renderDeck(
  WidgetTester tester,
  SlideDeck deck,
  DeckDesign design, {
  required double width,
  String name = 'muestrario',
  bool allowEllipsis = true,
}) async {
  final height = width / design.aspect.ratio;
  const spacing = 8.0;
  tester.view
    ..physicalSize = Size(
      width + spacing * 2,
      (height + spacing) * deck.slides.length + spacing * 2,
    )
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: const Key('muestrario'),
        child: ColoredBox(
          color: const Color(0xFF808080),
          child: Padding(
            padding: const EdgeInsets.all(spacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < deck.slides.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: spacing),
                    child: SizedBox(
                      key: ValueKey('muestra-$i'),
                      width: width,
                      height: height,
                      child: SlideView(
                        slide: deck.slides[i],
                        design: design,
                        deck: deck,
                        index: i,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final error = tester.takeException();
  expect(error, isNull, reason: '$name: $error');
  final problems = <String>[];
  for (var i = 0; i < deck.slides.length; i++) {
    for (final problem in textProblems(
      tester,
      find.byKey(ValueKey('muestra-$i')),
      allowEllipsis: allowEllipsis,
    )) {
      final layout = deck.slides[i].layout.jsonName;
      problems.add('$name · diapositiva ${i + 1} ($layout): $problem');
    }
  }
  await maybeDumpPng(tester, find.byKey(const Key('muestrario')), name);
  return problems;
}
