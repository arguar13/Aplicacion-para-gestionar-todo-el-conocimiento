import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';

/// Los treinta estilos (los dieciocho de F43 y los doce de F45): cada uno el
/// suyo, con seis paletas que se leen bien; los ilustrados, con su pedido
/// para la IA de imágenes y su versión dibujada.
void main() {
  test('una receta por estilo de verdad; «Automático» usa la de Bento', () {
    expect(InfographicStyles.all, hasLength(29));
    for (final id in InfographicStyleId.values) {
      if (id == InfographicStyleId.auto) continue;
      expect(InfographicStyles.of(id).id, id);
    }
    expect(
      InfographicStyles.of(InfographicStyleId.auto).id,
      InfographicStyleId.bento,
    );
  });

  test('los ilustrados traen su pedido a la IA; los dibujados, no', () {
    for (final spec in InfographicStyles.all) {
      expect(spec.isIllustrated, spec.id.isIllustrated, reason: spec.id.id);
      if (spec.isIllustrated) {
        expect(spec.illustrationHint, contains('no text'), reason: spec.id.id);
      }
    }
  });

  test('los que se llaman como una plantilla de presentación usan sus '
      'paletas: una lámina y un mazo del mismo nombre combinan', () {
    const pairs = {
      InfographicStyleId.editorial: DeckTemplateId.editorial,
      InfographicStyleId.swiss: DeckTemplateId.swiss,
      InfographicStyleId.chalkboard: DeckTemplateId.chalkboard,
      InfographicStyleId.neon: DeckTemplateId.neon,
      InfographicStyleId.parchment: DeckTemplateId.parchment,
      InfographicStyleId.data: DeckTemplateId.data,
      InfographicStyleId.watercolor: DeckTemplateId.watercolor,
      // Los doce de F45, todos.
      InfographicStyleId.newspaper: DeckTemplateId.newspaper,
      InfographicStyleId.ink: DeckTemplateId.ink,
      InfographicStyleId.magazine: DeckTemplateId.magazine,
      InfographicStyleId.bauhaus: DeckTemplateId.bauhaus,
      InfographicStyleId.brutalist: DeckTemplateId.brutalist,
      InfographicStyleId.darkMinimal: DeckTemplateId.darkMinimal,
      InfographicStyleId.terminal: DeckTemplateId.terminal,
      InfographicStyleId.artDeco: DeckTemplateId.artDeco,
      InfographicStyleId.retro: DeckTemplateId.retro,
      InfographicStyleId.manuscript: DeckTemplateId.manuscript,
      InfographicStyleId.whiteboard: DeckTemplateId.whiteboard,
      InfographicStyleId.blueprint: DeckTemplateId.blueprint,
    };
    for (final MapEntry(key: style, value: template) in pairs.entries) {
      expect(
        InfographicStyles.of(style).palettes,
        DeckTemplates.of(template).palettes,
      );
    }
  });

  group('las paletas', () {
    for (final spec in InfographicStyles.all) {
      test('${spec.id.id}: seis distintas y todas legibles', () {
        expect(spec.palettes, hasLength(InfographicDesign.paletteCount));
        expect(
          spec.palettes.toSet(),
          hasLength(InfographicDesign.paletteCount),
        );
        final darks = spec.palettes.where((p) => p.isDark).length;
        // Los que comparten nombre con una plantilla oscura son todos de
        // noche; los claros traen al menos una.
        final template = DeckTemplateId.fromId(spec.id.id);
        if (template?.family == DeckTemplateFamily.dark) {
          expect(darks, InfographicDesign.paletteCount, reason: spec.id.id);
        } else {
          expect(darks, inInclusiveRange(1, 5), reason: spec.id.id);
        }
        for (final (i, palette) in spec.palettes.indexed) {
          final where = '${spec.id.id}, paleta ${i + 1}';
          for (final background in [
            palette.background,
            palette.surfaceOnBackground,
          ]) {
            expect(
              CreationContrast.ratio(palette.text, background),
              greaterThanOrEqualTo(7),
              reason: '$where: el texto',
            );
            expect(
              CreationContrast.ratio(palette.muted, background),
              greaterThanOrEqualTo(4.5),
              reason: '$where: el texto tenue',
            );
            expect(
              CreationContrast.ratio(palette.accentText, background),
              greaterThanOrEqualTo(4.5),
              reason: '$where: el rótulo de color',
            );
          }
          for (final fill in [
            palette.primary,
            palette.secondary,
            palette.accent,
          ]) {
            expect(
              CreationContrast.ratio(CreationContrast.readableOn(fill), fill),
              greaterThanOrEqualTo(4.5),
              reason: '$where: el texto sobre $fill',
            );
          }
        }
      });
    }

    test('un color propio deja todo legible, en cualquier estilo', () {
      for (final spec in InfographicStyles.all) {
        for (final seed in [0xFFFFEB3B, 0xFF0D47A1, 0xFF888888]) {
          final p = spec.palette(0, customColor: seed);
          expect(p.primary, isNot(spec.palettes.first.primary));
          expect(
            CreationContrast.ratio(p.text, p.background),
            greaterThanOrEqualTo(7),
            reason: spec.id.id,
          );
          expect(
            CreationContrast.ratio(p.accentText, p.background),
            greaterThanOrEqualTo(4.5),
            reason: spec.id.id,
          );
        }
      }
    });
  });

  test('la nota adhesiva deja leer el texto encima, y se ve de color', () {
    final notes = InfographicStyles.all.where(
      (s) => s.panel == InfoPanelLook.note,
    );
    expect(notes, isNotEmpty);
    for (final spec in notes) {
      for (final palette in spec.palettes) {
        final paper = palette.noteColor;
        expect(paper, isNot(palette.surfaceOnBackground), reason: spec.id.id);
        expect(
          CreationContrast.ratio(palette.text, paper),
          greaterThanOrEqualTo(7),
        );
        expect(
          CreationContrast.ratio(palette.muted, paper),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('ningún estilo es igual a otro, y entre todos usan cada caja, cada '
      'cabecera y cada textura', () {
    final recipes = {
      for (final s in InfographicStyles.all)
        (s.panel, s.header, s.texture, s.art, s.fonts, s.palettes.first),
    };
    expect(recipes, hasLength(InfographicStyles.all.length));
    expect(
      InfographicStyles.all.map((s) => s.panel).toSet(),
      InfoPanelLook.values.toSet(),
    );
    expect(
      InfographicStyles.all.map((s) => s.header).toSet(),
      InfoHeaderLook.values.toSet(),
    );
    expect(
      InfographicStyles.all.map((s) => s.texture).toSet(),
      InfoTexture.values.toSet(),
    );
  });
}
