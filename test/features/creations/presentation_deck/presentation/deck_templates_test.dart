import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_style.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_parts.dart';

/// Las veintiocho plantillas (las dieciséis de F43 y las doce de F45): cada
/// una la suya, con seis paletas que se leen bien, y entre todas usan cada
/// forma de componer y cada par de letras.
void main() {
  test('son veintiocho, en el orden de sus nombres', () {
    expect(DeckTemplates.all, hasLength(28));
    for (final id in DeckTemplateId.values) {
      expect(DeckTemplates.of(id).id, id);
    }
  });

  group('las paletas', () {
    for (final template in DeckTemplates.all) {
      test('${template.id.id}: seis distintas y todas legibles', () {
        expect(template.palettes, hasLength(DeckDesign.paletteCount));
        expect(template.palettes.toSet(), hasLength(DeckDesign.paletteCount));
        for (final (i, palette) in template.palettes.indexed) {
          final where = '${template.id.id}, paleta ${i + 1}';
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

    test('las claras traen una de noche; las oscuras son todas de noche', () {
      for (final template in DeckTemplates.all) {
        final darks = template.palettes.where((p) => p.isDark).length;
        if (template.family == DeckTemplateFamily.dark) {
          expect(darks, DeckDesign.paletteCount, reason: template.id.id);
        } else {
          expect(darks, inInclusiveRange(1, 5), reason: template.id.id);
        }
      }
    });
  });

  test('la nota adhesiva y el resaltador (F45) dejan leer el texto encima, '
      'en todas las paletas', () {
    for (final template in DeckTemplates.all) {
      for (final (i, palette) in template.palettes.indexed) {
        final where = '${template.id.id}, paleta ${i + 1}';
        final note = DeckPanel.noteColor(palette);
        expect(
          CreationContrast.ratio(palette.text, note),
          greaterThanOrEqualTo(7),
          reason: '$where: el texto de la nota',
        );
        expect(
          CreationContrast.ratio(palette.muted, note),
          greaterThanOrEqualTo(4.5),
          reason: '$where: el tenue de la nota',
        );
        final mark = SlideTitle.highlightOf(palette);
        expect(
          CreationContrast.ratio(palette.text, mark),
          greaterThanOrEqualTo(4.5),
          reason: '$where: el título sobre el resaltador',
        );
        expect(mark, isNot(palette.background), reason: where);
      }
    }
    // En Manuscrito la nota se ve de color: no es la superficie lisa.
    for (final palette in DeckTemplates.of(
      DeckTemplateId.manuscript,
    ).palettes) {
      expect(DeckPanel.noteColor(palette), isNot(palette.surfaceOnBackground));
    }
  });

  test('ninguna plantilla es igual a otra', () {
    final recipes = {
      for (final t in DeckTemplates.all)
        (
          t.cover,
          t.section,
          t.quote,
          t.list,
          t.title,
          t.panel,
          t.bullet,
          t.art,
        ),
    };
    expect(recipes, hasLength(DeckTemplates.all.length));
    expect(
      DeckTemplates.all.map((t) => t.palettes.first).toSet(),
      hasLength(DeckTemplates.all.length),
    );
  });

  test('entre todas usan cada forma de componer y cada letra', () {
    const all = DeckTemplates.all;
    expect(all.map((t) => t.cover).toSet(), CoverLook.values.toSet());
    expect(all.map((t) => t.section).toSet(), SectionLook.values.toSet());
    expect(all.map((t) => t.quote).toSet(), QuoteLook.values.toSet());
    expect(all.map((t) => t.list).toSet(), ListLook.values.toSet());
    expect(all.map((t) => t.title).toSet(), TitleLook.values.toSet());
    expect(all.map((t) => t.panel).toSet(), PanelLook.values.toSet());
    expect(all.map((t) => t.bullet).toSet(), BulletMark.values.toSet());
    expect(all.map((t) => t.fonts).toSet(), CreationFontPair.values.toSet());
  });

  group('el estilo resuelto', () {
    test('la paleta elegida, o la primera si el número no existe', () {
      final style = DeckStyle(
        design: const DeckDesign(
          template: DeckTemplateId.neon,
          paletteIndex: 3,
        ),
      );
      expect(style.palette, DeckTemplates.of(DeckTemplateId.neon).palettes[3]);
      expect(
        DeckTemplates.of(DeckTemplateId.neon).palette(40),
        DeckTemplates.of(DeckTemplateId.neon).palettes.last,
      );
    });

    test('el color propio tiñe la paleta elegida', () {
      final style = DeckStyle(
        design: const DeckDesign(
          template: DeckTemplateId.pastel,
          customColor: 0xFF2E7D32,
        ),
      );
      expect(style.palette.primary.toARGB32(), 0xFF2E7D32);
      expect(
        style.palette.background,
        DeckTemplates.of(DeckTemplateId.pastel).palettes.first.background,
      );
    });

    test('la letra elegida, o la de la plantilla si no se conoce', () {
      expect(
        DeckStyle(
          design: const DeckDesign(
            template: DeckTemplateId.swiss,
            fontPair: 'handwritten',
          ),
        ).fonts,
        CreationFontPair.handwritten,
      );
      expect(
        DeckStyle(
          design: const DeckDesign(
            template: DeckTemplateId.swiss,
            fontPair: 'futura',
          ),
        ).fonts,
        CreationFontPair.swiss,
      );
    });

    test('la densidad cambia el aire y la letra, y el formato el ancho', () {
      DeckStyle of(
        DeckDensity density, [
        DeckAspect aspect = DeckAspect.widescreen,
      ]) => DeckStyle(
        design: DeckDesign(density: density, aspect: aspect),
      );
      expect(
        of(DeckDensity.airy).marginX,
        greaterThan(of(DeckDensity.standard).marginX),
      );
      expect(
        of(DeckDensity.compact).bodySize,
        lessThan(of(DeckDensity.standard).bodySize),
      );
      expect(of(DeckDensity.standard, DeckAspect.standard).canvas.width, 1440);
      expect(of(DeckDensity.standard).canvas.height, 1080);
    });

    test('sin numeración ni pie no se reserva lugar abajo', () {
      expect(
        DeckStyle(design: const DeckDesign(numbering: false)).footerHeight,
        0,
      );
      expect(
        DeckStyle(design: const DeckDesign()).footerHeight,
        greaterThan(0),
      );
    });
  });
}
