import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/deck_illustration_style.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_prompts.dart';

/// Lo que eligió la persona, lo que se guarda y lo que se le pide a la IA en
/// una Presentación (F43, paso 11).
void main() {
  group('PresentationOptions', () {
    test('de fábrica: detallada, estándar, automática, sin ilustraciones', () {
      final o = PresentationOptions.of(const {});
      expect(o.format, DeckFormat.detailed);
      expect(o.short, isFalse);
      expect(o.template, isNull);
      expect(o.illustrations, isFalse);
      expect(o.illustrationStyle, DeckIllustrationStyle.template);
      expect(o.slideTarget, PresentationOptions.standardSlides);
      expect(o.maxIllustrations, 7);
    });

    test('lee lo de la hoja', () {
      final o = PresentationOptions.of(const {
        CreationOptionValues.format: CreationOptionValues.presenter,
        CreationOptionValues.length: CreationOptionValues.short,
        CreationOptionValues.template: 'paper_cut',
        CreationOptionValues.illustrations: true,
        PresentationOptionKeys.illustrationStyle: 'clay',
        CreationOptionKeys.description: '  para chicos  ',
        CreationOptionKeys.imageAccountId: 'w',
      });
      expect(o.format, DeckFormat.presenter);
      expect(o.short, isTrue);
      expect(o.slideTarget, PresentationOptions.shortSlides);
      expect(o.maxIllustrations, 4);
      expect(o.template, DeckTemplateId.paperCut);
      expect(o.illustrations, isTrue);
      expect(o.illustrationStyle, DeckIllustrationStyle.clay);
      expect(o.description, 'para chicos');
      expect(o.imageAccountId, 'w');
    });

    test('la plantilla por su id o por el nombre que guardaba la hoja de '
        'fábrica; «auto» y lo desconocido son «Automática»', () {
      expect(
        PresentationOptions.templateOf('paper_cut'),
        DeckTemplateId.paperCut,
      );
      expect(
        PresentationOptions.templateOf('paperCut'),
        DeckTemplateId.paperCut,
      );
      expect(PresentationOptions.templateOf('auto'), isNull);
      expect(PresentationOptions.templateOf('rara'), isNull);
      expect(PresentationOptions.templateOf(3), isNull);
    });

    test('lo que se estima que escribe crece con la duración y las notas', () {
      int tokens(String length, String format) => PresentationOptions.of({
        CreationOptionValues.length: length,
        CreationOptionValues.format: format,
      }).expectedOutputTokens;
      final shortDetailed = tokens(
        CreationOptionValues.short,
        CreationOptionValues.detailed,
      );
      final standardDetailed = tokens(
        CreationOptionValues.standard,
        CreationOptionValues.detailed,
      );
      final standardPresenter = tokens(
        CreationOptionValues.standard,
        CreationOptionValues.presenter,
      );
      expect(shortDetailed, 8 * 225);
      expect(standardDetailed, 14 * 225);
      expect(standardPresenter, 14 * 330);
    });

    test('el diseño: el guardado en el visor; si no, la plantilla elegida; '
        'en «Automática», la que sugirió la IA; si tampoco, Editorial', () {
      const saved = DeckDesign(
        template: DeckTemplateId.neon,
        paletteIndex: 3,
        density: DeckDensity.compact,
      );
      expect(
        presentationDesignOf({
          PresentationOptionKeys.design: saved.toJson(),
          CreationOptionValues.template: 'swiss',
        }, hint: DeckTemplateId.aurora),
        saved,
      );
      expect(
        presentationDesignOf(const {
          CreationOptionValues.template: 'swiss',
        }, hint: DeckTemplateId.aurora).template,
        DeckTemplateId.swiss,
      );
      expect(
        presentationDesignOf(const {
          CreationOptionValues.template: 'auto',
        }, hint: DeckTemplateId.aurora).template,
        DeckTemplateId.aurora,
      );
      expect(presentationDesignOf(const {}).template, DeckTemplateId.editorial);
    });
  });

  group('DeckIllustrationStyle', () {
    test('cada plantilla tiene su pista, en inglés; los estilos, la suya', () {
      for (final template in DeckTemplateId.values) {
        final hint = DeckIllustrationStyle.template.hintFor(template);
        expect(hint, isNotEmpty, reason: template.id);
        expect(hint, isNot(contains('á')), reason: template.id);
      }
      expect(
        DeckIllustrationStyle.template.hintFor(DeckTemplateId.chalkboard),
        contains('chalk'),
      );
      expect(
        DeckIllustrationStyle.clay.hintFor(DeckTemplateId.chalkboard),
        contains('claymation'),
      );
      expect(
        DeckIllustrationStyle.fromId('isometric'),
        DeckIllustrationStyle.isometric,
      );
      expect(DeckIllustrationStyle.fromId('nada'), isNull);
    });
  });

  group('PresentationContent', () {
    const deck = SlideDeck(
      title: 'Éxodo',
      format: DeckFormat.presenter,
      slides: [
        Slide.cover(
          title: 'Éxodo',
          illustrationPrompt: 'El mar',
          illustrationRef: 'originales/c1/ilustraciones/diapositiva-1.png',
        ),
        Slide.bullets(title: 'Ideas', bullets: ['Una']),
        Slide.imageText(
          title: 'El Sinaí',
          body: 'La alianza.',
          illustrationPrompt: 'Una montaña',
        ),
        Slide.closing(title: 'Cierre'),
      ],
    );

    test('ida y vuelta, con la sugerencia, las fallas y la cuenta', () {
      const content = PresentationContent(
        deck: deck,
        templateHint: DeckTemplateId.aurora,
        misses: [IllustrationMiss(slide: 2, failure: ImageFailure.noBilling)],
        illustrationAccount: 'Personal',
      );
      final read = PresentationContent.decode(content.encode());
      expect(read.deck, deck);
      expect(read.templateHint, DeckTemplateId.aurora);
      expect(read.misses, content.misses);
      expect(read.illustrationAccount, 'Personal');
      final json = jsonDecode(content.encode()) as Map;
      expect(json['template_hint'], 'aurora');
      expect(json['illustration_misses'], [
        {'slide': 2, 'failure': 'noBilling'},
      ]);
    });

    test('lo que falta, lo hecho y completar una', () {
      const content = PresentationContent(
        deck: deck,
        misses: [IllustrationMiss(slide: 2, failure: ImageFailure.rateLimited)],
      );
      expect(content.missing, [2]);
      expect(content.files, {'originales/c1/ilustraciones/diapositiva-1.png'});
      expect(content.missOf(2)?.failure, ImageFailure.rateLimited);
      expect(content.missOf(1), isNull);

      final done = content.withIllustration(
        2,
        'originales/c1/ilustraciones/d3.png',
      );
      expect(done.missing, isEmpty);
      expect(done.misses, isEmpty);
      expect(done.files, hasLength(2));
      expect(
        done.deck.slides[2].illustrationRef,
        'originales/c1/ilustraciones/d3.png',
      );
    });

    test('con tolerancia: una falla de una diapositiva que no está, o que ya '
        'tiene la suya, no cuenta; un porqué desconocido es «otra cosa»', () {
      final json = {
        'title': 'Éxodo',
        'slides': [
          {
            'layout': 'cover',
            'title': 'Éxodo',
            'illustration_ref': 'originales/c/ilustraciones/a.png',
          },
          {
            'layout': 'bullets',
            'title': 'Ideas',
            'bullets': ['Una'],
          },
        ],
        'illustration_misses': [
          {'slide': 0, 'failure': 'noBilling'},
          {'slide': 1, 'failure': 'algo-nuevo'},
          {'slide': 7, 'failure': 'noBilling'},
          {'slide': 'uno'},
          'basura',
        ],
        'template_hint': 'no-existe',
      };
      final read = PresentationContent.decode(jsonEncode(json));
      expect(read.misses, const [
        IllustrationMiss(slide: 1, failure: ImageFailure.unknown),
      ]);
      expect(read.templateHint, isNull);
      expect(PresentationContent.decode(null).deck.slides, isEmpty);
      expect(PresentationContent.decode('no es json').deck.slides, isEmpty);
    });
  });

  group('PresentationPrompts', () {
    test('cuántas, en qué orden y en qué formato; las ilustraciones con su '
        'tope; en «Automática», que elija la plantilla', () {
      final auto = PresentationOptions.of(const {
        CreationOptionValues.length: CreationOptionValues.short,
        CreationOptionValues.format: CreationOptionValues.presenter,
      });
      final task = PresentationPrompts.task(auto);
      expect(task, contains('unas 8 diapositivas'));
      expect(task, contains('entre 6 y 10'));
      expect(task, contains('"cover"'));
      expect(task, contains('"closing"'));
      expect(task, contains('Formato "presenter"'));
      expect(task, contains('unas 4 diapositivas'));
      expect(task, contains('"template"'));
      expect(task, contains('paper_cut'));
      // Las veintiocho, también las de F45: la IA no elige una que no
      // conoce, y no sugiere una que la app no tiene.
      for (final id in DeckTemplateId.values) {
        expect(task, contains('${id.id} ('), reason: id.id);
      }

      final chosen = PresentationOptions.of(const {
        CreationOptionValues.template: 'neon',
      });
      expect(PresentationPrompts.task(chosen), isNot(contains('"template"')));
      expect(PresentationPrompts.task(chosen), contains('Formato "detailed"'));

      final part = PresentationPrompts.partTask(auto);
      expect(part, contains('sin portada ni cierre'));
      expect(part, isNot(contains('"template"')));
      final merge = PresentationPrompts.mergeTask(auto);
      expect(merge, contains('unas 8 diapositivas'));
      expect(merge, contains('"speaker_notes"'));
      expect(merge, contains('"template"'));
    });
  });
}
