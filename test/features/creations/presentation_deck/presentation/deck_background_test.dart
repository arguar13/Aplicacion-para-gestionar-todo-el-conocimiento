import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_background_painter.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';

import '../support/muestrario.dart';
import '../support/sample_decks.dart';
import '../support/slide_test_support.dart';

/// El fondo que se elige en «Personalizar» (F45, paso 5): liso, con la
/// textura de la plantilla o en degradé. Lo liso y el degradé sacan los
/// adornos, pero nunca lo que un diseño necesita debajo de su texto.
void main() {
  /// El fondo de [design] para [layout], pintado a un cuarto (480×270).
  Future<ByteData> paint(
    WidgetTester tester,
    DeckDesign design, {
    SlideLayout layout = SlideLayout.bullets,
  }) async => (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(0.25);
    DeckBackgroundPainter(
      style: DeckStyle(design: design),
      layout: layout,
      index: 0,
    ).paint(canvas, const Size(1920, 1080));
    final image = await recorder.endRecording().toImage(480, 270);
    try {
      return (await image.toByteData())!;
    } finally {
      image.dispose();
    }
  }))!;

  /// El color del píxel (x, y) de [pixels], de 480 de ancho.
  Color at(ByteData pixels, int x, int y) {
    final i = 4 * (y * 480 + x);
    return Color.fromARGB(
      pixels.getUint8(i + 3),
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
  }

  /// Cuántos píxeles de [pixels] no son [color].
  int differentFrom(ByteData pixels, Color color) {
    final target = color.toARGB32();
    var count = 0;
    for (var y = 0; y < 270; y++) {
      for (var x = 0; x < 480; x++) {
        if (at(pixels, x, y).toARGB32() != target) count++;
      }
    }
    return count;
  }

  testWidgets('de fábrica, el de la plantilla: con sus adornos', (
    tester,
  ) async {
    const design = DeckDesign(template: DeckTemplateId.midnight);
    expect(DeckStyle(design: design).background, DeckBackground.texture);
    final background = DeckTemplates.of(
      DeckTemplateId.midnight,
    ).palettes.first.background;
    final pixels = await paint(tester, design);
    // Las estrellas y los filetes de oro: buena parte no es el fondo.
    expect(differentFrom(pixels, background), greaterThan(2000));
    expect(
      await paint(tester, design.copyWith(background: DeckBackground.texture)),
      _samePixels(pixels),
    );
  });

  testWidgets('liso: solo el color del fondo, en todas las plantillas que no '
      'necesitan nada debajo del texto', (tester) async {
    for (final id in DeckTemplateId.values) {
      if (id == DeckTemplateId.executive) continue;
      for (final palette in [0, 5]) {
        final design = DeckDesign(
          template: id,
          paletteIndex: palette,
          background: DeckBackground.plain,
        );
        final pixels = await paint(tester, design, layout: SlideLayout.cover);
        expect(
          differentFrom(
            pixels,
            DeckTemplates.of(id).palettes[palette].background,
          ),
          0,
          reason: '${id.id}, paleta ${palette + 1}',
        );
      }
    }
  });

  testWidgets('liso y degradé dejan la banda de Ejecutiva, donde va el título '
      'en claro', (tester) async {
    final palette = DeckTemplates.of(DeckTemplateId.executive).palettes.first;
    for (final background in [DeckBackground.plain, DeckBackground.gradient]) {
      final design = DeckDesign(
        template: DeckTemplateId.executive,
        background: background,
      );
      // La portada: la banda ocupa el 42 % de la izquierda.
      final cover = await paint(tester, design, layout: SlideLayout.cover);
      expect(at(cover, 60, 135), palette.primary, reason: background.id);
      // El contenido: la barra fina del borde izquierdo.
      final content = await paint(tester, design);
      expect(at(content, 2, 135), palette.primary, reason: background.id);
    }
  });

  testWidgets('degradé: del fondo, arriba a la izquierda, hacia el primario, '
      'abajo a la derecha', (tester) async {
    const id = DeckTemplateId.swiss;
    final palette = DeckTemplates.of(id).palettes.first;
    final pixels = await paint(
      tester,
      const DeckDesign(template: id, background: DeckBackground.gradient),
    );
    double distance(Color a, Color b) =>
        (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
    expect(distance(at(pixels, 0, 0), palette.background), lessThan(0.02));
    final end = at(pixels, 479, 269);
    expect(
      distance(end, palette.primary),
      lessThan(distance(palette.background, palette.primary) * 0.95),
    );
    // Sin el círculo rojo de la portada suiza: el degradé saca los adornos.
    final textured = await paint(
      tester,
      const DeckDesign(template: id),
      layout: SlideLayout.cover,
    );
    final gradient = await paint(
      tester,
      const DeckDesign(template: id, background: DeckBackground.gradient),
      layout: SlideLayout.cover,
    );
    expect(distance(at(textured, 403, 81), palette.primary), lessThan(0.05));
    expect(distance(at(gradient, 403, 81), palette.primary), greaterThan(0.5));
  });

  setUpAll(loadCreationFonts);

  testWidgets('con los tres fondos, ningún mazo desborda', (tester) async {
    final problems = <String>[];
    for (final id in DeckTemplateId.values) {
      for (final background in [
        DeckBackground.plain,
        DeckBackground.gradient,
      ]) {
        problems.addAll(
          await renderDeck(
            tester,
            sampleDeck(),
            DeckDesign(template: id, background: background),
            width: 320,
            allowEllipsis: false,
            name: '${id.id}-${background.id}',
          ),
        );
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

/// Los mismos bytes, uno por uno.
Matcher _samePixels(ByteData expected) => predicate<ByteData>((actual) {
  if (actual.lengthInBytes != expected.lengthInBytes) return false;
  for (var i = 0; i < actual.lengthInBytes; i++) {
    if (actual.getUint8(i) != expected.getUint8(i)) return false;
  }
  return true;
}, 'los mismos píxeles');
