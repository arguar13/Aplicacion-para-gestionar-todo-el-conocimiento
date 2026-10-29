import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

import '../support/infographic_muestrario.dart';
import '../support/sample_infographics.dart';

/// El muestrario (F43, paso 5): cada estilo con cada composición, en las
/// tres orientaciones, en el ancho de un teléfono (360) y en el de una
/// computadora, con la letra de verdad. Es la red principal del diseño:
///
/// - nada tira una excepción ni desborda (un `RenderFlex` que no entra);
/// - ningún texto se dibuja recortado ni se sale del lienzo;
/// - con una lámina común, nada se corta con «…»: el ajuste lo hace entrar;
/// - con el peor caso —cada campo en su tope, palabras largas—, se puede
///   cortar con «…», pero sigue sin desbordar.
///
/// Con `MUESTRARIO_PNG=carpeta` guarda cada hoja como PNG, para mirarlas.
void main() {
  setUpAll(loadInfographicFonts);

  /// El contenido que mejor muestra cada composición.
  Infographic contentFor(InfographicComposition composition) =>
      switch (composition) {
        InfographicComposition.timeline => timelineInfographic(),
        InfographicComposition.process => processInfographic(),
        InfographicComposition.statPanel => dataInfographic(),
        InfographicComposition.conceptMap ||
        InfographicComposition.radial => conceptsInfographic(),
        InfographicComposition.zigzag => conceptsInfographic().copyWith(
          blocks: [
            for (final b in conceptsInfographic().blocks)
              (b as ConceptBlock).copyWith(illustrationPrompt: 'Un dibujo'),
          ],
        ),
        _ => sampleInfographic(illustrations: true),
      };

  for (final style in InfographicStyleId.values) {
    group('${style.id}:', () {
      for (final orientation in InfographicOrientation.values) {
        List<Muestra> all(Infographic Function(InfographicComposition) of) => [
          for (final composition in InfographicComposition.concrete)
            (
              name: composition.jsonName,
              sheet: of(composition),
              design: InfographicDesign(
                style: style,
                composition: composition,
                orientation: orientation,
              ),
            ),
        ];

        testWidgets('las diez composiciones en ${orientation.id}, sin «…», en '
            'el teléfono y en la computadora', (tester) async {
          final problems = [
            ...await renderSheets(
              tester,
              all(contentFor),
              width: 360,
              allowEllipsis: false,
              name: '${style.id}-${orientation.id}-360',
            ),
            ...await renderSheets(
              tester,
              all(contentFor),
              width: 1280,
              allowEllipsis: false,
              name: '${style.id}-${orientation.id}-1280',
            ),
          ];
          expect(problems, isEmpty, reason: problems.join('\n'));
        });

        testWidgets('el peor caso en ${orientation.id} no desborda', (
          tester,
        ) async {
          final problems = await renderSheets(
            tester,
            all((_) => longInfographic()),
            width: 360,
            name: '${style.id}-${orientation.id}-largo',
          );
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }

      testWidgets('sus seis paletas, un color propio y lo mínimo', (
        tester,
      ) async {
        final problems = await renderSheets(
          tester,
          [
            for (
              var palette = 0;
              palette < InfographicDesign.paletteCount;
              palette++
            )
              (
                name: 'paleta ${palette + 1}',
                sheet: sampleInfographic(),
                design: InfographicDesign(style: style, paletteIndex: palette),
              ),
            (
              name: 'color propio',
              sheet: sampleInfographic(),
              design: InfographicDesign(style: style, customColor: 0xFF2E7D32),
            ),
            (
              name: 'mínimo',
              sheet: minimalInfographic(),
              design: InfographicDesign(style: style),
            ),
          ],
          width: 320,
          allowEllipsis: false,
          name: '${style.id}-paletas',
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    });
  }

  group('cada tipografía con cada detalle, íconos y fondo', () {
    var turn = 0;
    for (final fonts in CreationFontPair.values) {
      for (final detail in InfographicDetail.values) {
        // Cada combinación con otro estilo, otros íconos y otro fondo, para
        // recorrerlos todos.
        final style =
            InfographicStyleId.values[turn % InfographicStyleId.values.length];
        final icons = InfographicIconLook
            .values[turn % InfographicIconLook.values.length];
        final background = InfographicBackground
            .values[turn % InfographicBackground.values.length];
        turn++;
        testWidgets('${fonts.name} · ${detail.id} (${style.id}, ${icons.id}, '
            '${background.id})', (tester) async {
          final problems = await renderSheets(
            tester,
            [
              for (final orientation in InfographicOrientation.values)
                for (final composition in [
                  InfographicComposition.auto,
                  InfographicComposition.bento,
                  InfographicComposition.columns,
                ])
                  (
                    name: '${orientation.id}-${composition.jsonName}',
                    sheet: sampleInfographic(),
                    design: InfographicDesign(
                      style: style,
                      composition: composition,
                      fontPair: fonts.name,
                      detail: detail,
                      orientation: orientation,
                      iconLook: icons,
                      background: background,
                    ),
                  ),
            ],
            width: 480,
            allowEllipsis: false,
            name: '${fonts.name}-${detail.id}',
          );
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    }
  });
}
