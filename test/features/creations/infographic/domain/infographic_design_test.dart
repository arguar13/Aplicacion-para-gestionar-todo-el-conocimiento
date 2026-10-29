import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

/// El diseño de una infografía (decisión G): se guarda aparte, vuelve igual y
/// se lee con tolerancia —nunca falla, lo raro toma el valor de fábrica—.
void main() {
  test('dieciocho estilos en dos familias y diez composiciones más la '
      'automática', () {
    expect(InfographicStyleId.values, hasLength(18));
    expect(
      InfographicStyleId.values.where((s) => s.isIllustrated).map((s) => s.id),
      ['clay', 'kawaii', 'watercolor', 'isometric', 'comic', 'photo'],
    );
    expect(InfographicComposition.concrete, hasLength(10));
    expect(
      InfographicComposition.concrete,
      isNot(contains(InfographicComposition.auto)),
    );
    // Los nombres que se guardan no se repiten.
    expect(InfographicStyleId.values.map((s) => s.id).toSet(), hasLength(18));
    expect(
      InfographicComposition.values.map((c) => c.jsonName).toSet(),
      hasLength(11),
    );
  });

  test('las tres orientaciones tienen la misma superficie', () {
    for (final o in InfographicOrientation.values) {
      expect(o.logicalWidth * o.logicalHeight, closeTo(1920 * 1080, 1e-6));
    }
    expect(InfographicOrientation.portrait.ratio, closeTo(9 / 16, 1e-9));
  });

  test('ida y vuelta, también por texto', () {
    const design = InfographicDesign(
      style: InfographicStyleId.chalkboard,
      composition: InfographicComposition.statPanel,
      paletteIndex: 4,
      customColor: 0xFF2E7D32,
      fontPair: 'handwritten',
      orientation: InfographicOrientation.square,
      detail: InfographicDetail.detailed,
      iconLook: InfographicIconLook.outline,
      background: InfographicBackground.gradient,
    );
    expect(InfographicDesign.parse(design.toJson()), design);
    expect(
      InfographicDesign.parse(jsonDecode(jsonEncode(design.toJson()))),
      design,
    );
    expect(design.toJson()['customColor'], '#FF2E7D32');
  });

  test('lo de fábrica no escribe lo que toma del estilo', () {
    final json = const InfographicDesign().toJson();
    expect(json.containsKey('icons'), isFalse);
    expect(json.containsKey('background'), isFalse);
    expect(json.containsKey('customColor'), isFalse);
    expect(InfographicDesign.parse(json), const InfographicDesign());
  });

  test('lo raro toma el valor de fábrica, y nunca falla', () {
    expect(InfographicDesign.parse(null), const InfographicDesign());
    expect(InfographicDesign.parse('x'), const InfographicDesign());
    final odd = InfographicDesign.parse({
      'style': 'inventado',
      'composition': 42,
      'palette': 99,
      'customColor': 'rojo',
      'fonts': '',
      'orientation': 'diagonal',
      'detail': null,
      'icons': 'brillantes',
      'background': true,
    });
    expect(odd, const InfographicDesign(paletteIndex: 5));
    expect(
      InfographicDesign.parse({'palette': -3, 'customColor': '#00ff00'}),
      const InfographicDesign(customColor: 0xFF00FF00),
    );
  });
}
