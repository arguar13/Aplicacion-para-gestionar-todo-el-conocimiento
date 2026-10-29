import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';

/// El diseño de un mazo se guarda aparte del contenido (decisión G): vuelve
/// igual, y lo guardado roto o de otra versión se lee sin fallar.
void main() {
  test('cada combinación vuelve igual', () {
    var count = 0;
    for (final template in DeckTemplateId.values) {
      for (final density in DeckDensity.values) {
        for (final transition in DeckTransition.values) {
          for (final aspect in DeckAspect.values) {
            final design = DeckDesign(
              template: template,
              paletteIndex: count % DeckDesign.paletteCount,
              customColor: count.isEven ? null : 0xFF12AB34,
              fontPair: count % 3 == 0 ? null : 'book',
              density: density,
              transition: transition,
              aspect: aspect,
              numbering: count.isEven,
              footer: count % 3 == 0,
            );
            final json = jsonDecode(jsonEncode(design.toJson()));
            expect(DeckDesign.parse(json), design);
            count++;
          }
        }
      }
    }
    expect(count, 16 * 3 * 4 * 2);
  });

  test('se escribe con nombres estables y el color en hex', () {
    const design = DeckDesign(
      template: DeckTemplateId.paperCut,
      paletteIndex: 4,
      customColor: 0xFF2E7D32,
      fontPair: 'handwritten',
      density: DeckDensity.airy,
      transition: DeckTransition.zoom,
      aspect: DeckAspect.standard,
      numbering: false,
      footer: true,
    );
    expect(design.toJson(), {
      'template': 'paper_cut',
      'palette': 4,
      'customColor': '#FF2E7D32',
      'fonts': 'handwritten',
      'density': 'airy',
      'transition': 'zoom',
      'aspect': '4:3',
      'numbering': false,
      'footer': true,
    });
  });

  test('lo de fábrica: Editorial, la primera paleta, fundido, 16:9, '
      'numerada y sin pie', () {
    const design = DeckDesign();
    expect(design.template, DeckTemplateId.editorial);
    expect(design.paletteIndex, 0);
    expect(design.customColor, isNull);
    expect(design.fontPair, isNull);
    expect(design.density, DeckDensity.standard);
    expect(design.transition, DeckTransition.fade);
    expect(design.aspect, DeckAspect.widescreen);
    expect(design.numbering, isTrue);
    expect(design.footer, isFalse);
  });

  group('con tolerancia', () {
    test('lo que no es un mapa da el de fábrica', () {
      expect(DeckDesign.parse(null), const DeckDesign());
      expect(DeckDesign.parse('roto'), const DeckDesign());
      expect(DeckDesign.parse([1, 2]), const DeckDesign());
    });

    test('lo desconocido toma el valor de fábrica, campo por campo', () {
      final design = DeckDesign.parse({
        'template': 'holograma',
        'palette': 'tres',
        'density': 'muy-aireada',
        'transition': 'espiral',
        'aspect': '21:9',
        'numbering': 'sí',
        'footer': 1,
        'fonts': '',
        'customColor': 'rojo',
      });
      expect(design, const DeckDesign());
    });

    test('la paleta se lleva a las seis que hay', () {
      expect(DeckDesign.parse({'palette': 99}).paletteIndex, 5);
      expect(DeckDesign.parse({'palette': -3}).paletteIndex, 0);
      expect(DeckDesign.parse({'palette': 2.0}).paletteIndex, 2);
    });

    test('el color propio se lee en hex de 6 u 8 cifras, o como entero', () {
      expect(
        DeckDesign.parse({'customColor': '#12ab34'}).customColor,
        0xFF12AB34,
      );
      expect(
        DeckDesign.parse({'customColor': '8012AB34'}).customColor,
        0x8012AB34,
      );
      expect(
        DeckDesign.parse({'customColor': 0xFF000001}).customColor,
        0xFF000001,
      );
      expect(DeckDesign.parse({'customColor': '#12ab3'}).customColor, isNull);
    });

    test('una tipografía que esta versión no conoce se guarda igual', () {
      // El dibujo la cambia por la de la plantilla, pero no se pierde: una
      // versión que la conozca la vuelve a usar.
      expect(DeckDesign.parse({'fonts': 'futura'}).fontPair, 'futura');
    });
  });

  test('los formatos tienen el mismo alto lógico', () {
    expect(
      DeckAspect.widescreen.logicalHeight,
      DeckAspect.standard.logicalHeight,
    );
    expect(DeckAspect.widescreen.ratio, closeTo(16 / 9, 1e-9));
    expect(DeckAspect.standard.ratio, closeTo(4 / 3, 1e-9));
  });

  test('cada plantilla está en la familia que dice el plan', () {
    Set<String> of(DeckTemplateFamily family) => {
      for (final id in DeckTemplateId.values)
        if (id.family == family) id.id,
    };
    expect(of(DeckTemplateFamily.classic), {
      'editorial',
      'parchment',
      'academic',
    });
    expect(of(DeckTemplateFamily.modern), {
      'swiss',
      'bento',
      'aurora',
      'glass',
    });
    expect(of(DeckTemplateFamily.dark), {'midnight', 'neon', 'chalkboard'});
    expect(of(DeckTemplateFamily.warm), {'watercolor', 'pastel', 'paper_cut'});
    expect(of(DeckTemplateFamily.business), {'corporate', 'data', 'executive'});
    expect(DeckTemplateId.fromId('neon'), DeckTemplateId.neon);
    expect(DeckTemplateId.fromId('nada'), isNull);
  });
}
