import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_rasterizer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';

import '../../presentation_deck/support/slide_test_support.dart';

/// Las letras de lo creado y, además, la de los íconos de Material: las
/// láminas dibujan íconos sueltos y en el pictograma, y con la letra de las
/// pruebas saldrían como cuadrados en los PNG del muestrario.
Future<void> loadInfographicFonts() async {
  await loadCreationFonts();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Un PNG chico de un solo color: una «ilustración ya hecha» de prueba.
Future<Uint8List> solidPng(Color color) async {
  final image = await CreationRasterizer.render(
    ColoredBox(color: color),
    logicalSize: const Size(32, 32),
  );
  try {
    return await CreationRasterizer.toPng(image);
  } finally {
    image.dispose();
  }
}

/// Una lámina del muestrario: su nombre, su contenido y su diseño.
typedef Muestra = ({String name, Infographic sheet, InfographicDesign design});

/// Dibuja [muestras] una debajo de otra, cada una de [width] de ancho, y
/// devuelve los problemas de texto que haya en cada una (vacío si nada
/// desborda ni se sale del lienzo). Las excepciones de dibujo —un
/// `RenderFlex` que desborda, un error de diseño— hacen fallar la prueba
/// enseguida.
///
/// Con `MUESTRARIO_PNG=carpeta`, además guarda la hoja como [name].png.
Future<List<String>> renderSheets(
  WidgetTester tester,
  List<Muestra> muestras, {
  required double width,
  required String name,
  bool allowEllipsis = true,
}) async {
  const spacing = 8.0;
  final heights = [
    for (final m in muestras) width / m.design.orientation.ratio,
  ];
  tester.view
    ..physicalSize = Size(
      width + spacing * 2,
      heights.fold<double>(0, (a, h) => a + h + spacing) + spacing * 2,
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
                for (var i = 0; i < muestras.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: spacing),
                    child: SizedBox(
                      key: ValueKey('muestra-$i'),
                      width: width,
                      height: heights[i],
                      child: InfographicView(
                        sheet: muestras[i].sheet,
                        design: muestras[i].design,
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
  for (var i = 0; i < muestras.length; i++) {
    for (final problem in textProblems(
      tester,
      find.byKey(ValueKey('muestra-$i')),
      allowEllipsis: allowEllipsis,
    )) {
      problems.add('$name · ${muestras[i].name}: $problem');
    }
  }
  await maybeDumpPng(tester, find.byKey(const Key('muestrario')), name);
  return problems;
}
