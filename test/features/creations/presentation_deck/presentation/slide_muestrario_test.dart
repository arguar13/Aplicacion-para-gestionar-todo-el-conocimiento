import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';

import '../support/muestrario.dart';
import '../support/sample_decks.dart';
import '../support/slide_test_support.dart';

/// El muestrario (F43, paso 4): cada plantilla con cada diseño de
/// diapositiva, en 16:9 y 4:3, en el ancho de un teléfono (360) y en el de
/// una computadora, con la letra de verdad. Es la red principal del diseño:
///
/// - nada tira una excepción ni desborda (un `RenderFlex` que no entra);
/// - ningún texto se dibuja recortado ni se sale del lienzo;
/// - con un mazo común, nada se corta con «…»: el ajuste lo hace entrar;
/// - con el peor caso —cada campo en su tope, palabras largas—, se puede
///   cortar con «…», pero sigue sin desbordar.
///
/// Con `MUESTRARIO_PNG=carpeta` guarda cada hoja como PNG, para mirarlas.
void main() {
  setUpAll(loadCreationFonts);

  String tagOf(DeckAspect aspect) =>
      aspect == DeckAspect.widescreen ? '16x9' : '4x3';

  for (final template in DeckTemplateId.values) {
    group('${template.id}:', () {
      for (final aspect in DeckAspect.values) {
        final tag = tagOf(aspect);
        final design = DeckDesign(template: template, aspect: aspect);

        testWidgets('un mazo común en $tag entra entero, sin «…», en el '
            'teléfono y en la computadora', (tester) async {
          final problems = [
            ...await renderDeck(
              tester,
              sampleDeck(illustrations: true),
              design,
              width: 360,
              allowEllipsis: false,
              name: '${template.id}-$tag-360',
            ),
            ...await renderDeck(
              tester,
              sampleDeck(),
              design,
              width: 1280,
              allowEllipsis: false,
              name: '${template.id}-$tag-1280',
            ),
          ];
          expect(problems, isEmpty, reason: problems.join('\n'));
        });

        testWidgets('el peor caso en $tag no desborda', (tester) async {
          final problems = [
            ...await renderDeck(
              tester,
              longDeck(),
              design,
              width: 360,
              name: '${template.id}-$tag-largo-360',
            ),
            ...await renderDeck(
              tester,
              longDeck(),
              design,
              width: 1280,
              name: '${template.id}-$tag-largo-1280',
            ),
          ];
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }

      testWidgets('los ocho diseños de F45, en 16:9 y 4:3: comunes sin «…», '
          'el peor caso sin desbordar y el mínimo entero', (tester) async {
        final problems = <String>[];
        for (final aspect in DeckAspect.values) {
          final tag = tagOf(aspect);
          final design = DeckDesign(template: template, aspect: aspect);
          problems
            ..addAll(
              await renderDeck(
                tester,
                moreDeck(illustrations: true),
                design,
                width: 360,
                allowEllipsis: false,
                name: '${template.id}-$tag-f45-360',
              ),
            )
            ..addAll(
              await renderDeck(
                tester,
                moreDeck(),
                design,
                width: 1280,
                allowEllipsis: false,
                name: '${template.id}-$tag-f45-1280',
              ),
            )
            ..addAll(
              await renderDeck(
                tester,
                longMoreDeck(),
                design,
                width: 360,
                name: '${template.id}-$tag-f45-largo-360',
              ),
            );
        }
        problems.addAll(
          await renderDeck(
            tester,
            minimalMoreDeck(),
            DeckDesign(template: template),
            width: 640,
            allowEllipsis: false,
            name: '${template.id}-f45-minimo',
          ),
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      testWidgets('un mazo mínimo se dibuja entero', (tester) async {
        final problems = await renderDeck(
          tester,
          minimalDeck(),
          DeckDesign(template: template),
          width: 640,
          allowEllipsis: false,
          name: '${template.id}-minimo',
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      testWidgets('sus seis paletas y un color propio', (tester) async {
        final problems = <String>[];
        for (var palette = 0; palette < DeckDesign.paletteCount; palette++) {
          problems.addAll(
            await renderDeck(
              tester,
              sampleDeck(),
              DeckDesign(template: template, paletteIndex: palette),
              width: 320,
              allowEllipsis: false,
              name: '${template.id}-paleta-${palette + 1}',
            ),
          );
        }
        problems.addAll(
          await renderDeck(
            tester,
            sampleDeck(),
            DeckDesign(template: template, customColor: 0xFF2E7D32),
            width: 320,
            allowEllipsis: false,
            name: '${template.id}-color-propio',
          ),
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    });
  }

  group('cada tipografía en cada densidad', () {
    var turn = 0;
    for (final fonts in CreationFontPair.values) {
      for (final density in DeckDensity.values) {
        // Cada combinación con otra plantilla, para recorrerlas todas.
        final template =
            DeckTemplateId.values[turn++ % DeckTemplateId.values.length];
        testWidgets('${fonts.name} · ${density.id} (${template.id})', (
          tester,
        ) async {
          final problems = <String>[];
          for (final aspect in DeckAspect.values) {
            final design = DeckDesign(
              template: template,
              fontPair: fonts.name,
              density: density,
              aspect: aspect,
              footer: true,
            );
            problems
              ..addAll(
                await renderDeck(
                  tester,
                  sampleDeck(),
                  design,
                  width: 480,
                  allowEllipsis: false,
                  name: '${fonts.name}-${density.id}-${tagOf(aspect)}',
                ),
              )
              ..addAll(
                await renderDeck(
                  tester,
                  longDeck(),
                  design,
                  width: 480,
                  name: '${fonts.name}-${density.id}-${tagOf(aspect)}-largo',
                ),
              );
          }
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    }
  });
}
