import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_prompts.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

import '../support/infographic_kind_fakes.dart';

/// Lo que decide la infografía sin IA (F43, paso 12): sus opciones y lo que
/// estima, qué lugares ilustra cada estilo, cómo se guarda su contenido y lo
/// que se le pide a la IA.
void main() {
  group('las opciones', () {
    test('el diseño sale de lo guardado, con el estilo, la orientación y el '
        'detalle de la hoja encima', () {
      final options = {
        InfographicOptionKeys.style: 'kawaii',
        CreationOptionValues.orientation: 'landscape',
        CreationOptionValues.detail: 'concise',
        InfographicOptionKeys.design: const InfographicDesign(
          style: InfographicStyleId.neon,
          paletteIndex: 3,
          fontPair: 'swiss',
        ).toJson(),
      };
      final design = infographicDesignOf(options);
      expect(design.style, InfographicStyleId.kawaii);
      expect(design.orientation, InfographicOrientation.landscape);
      expect(design.detail, InfographicDetail.concise);
      expect(design.paletteIndex, 3);
      expect(design.fontPair, 'swiss');
    });

    test('lo que falta o no se entiende queda de fábrica', () {
      final design = infographicDesignOf({
        InfographicOptionKeys.style: 'no-existe',
        CreationOptionValues.orientation: 42,
        InfographicOptionKeys.design: 'roto',
      });
      expect(design, const InfographicDesign());
    });

    test('guardar un diseño deja el estilo, la orientación y el detalle a la '
        'par, y vuelve a leerse igual', () {
      const design = InfographicDesign(
        style: InfographicStyleId.photo,
        composition: InfographicComposition.zigzag,
        orientation: InfographicOrientation.square,
        detail: InfographicDetail.detailed,
        paletteIndex: 2,
      );
      final options = withInfographicDesign({'description': 'x'}, design);
      expect(options['description'], 'x');
      expect(options[InfographicOptionKeys.style], 'photo');
      expect(options[CreationOptionValues.orientation], 'square');
      expect(options[CreationOptionValues.detail], 'detailed');
      // Viaja como JSON, igual que en la base.
      final stored = jsonDecode(jsonEncode(options)) as Map<String, Object?>;
      expect(infographicDesignOf(stored), design);
    });

    test('las ilustraciones: con un estilo ilustrado o «Automático», la '
        'cabecera y cada bloque; con uno dibujado, solo unos pocos', () {
      int count(String style, String detail) => infographicIllustrationsFor({
        InfographicOptionKeys.style: style,
        CreationOptionValues.detail: detail,
      });
      expect(count('clay', 'concise'), 6);
      expect(count('clay', 'standard'), 8);
      expect(count('auto', 'detailed'), 10);
      expect(count('editorial', 'concise'), 2);
      expect(count('editorial', 'standard'), 3);
      expect(count('bento', 'detailed'), 4);
    });

    test('lo que escribe crece con el detalle y con las ilustraciones', () {
      Map<String, Object?> o(String detail, {bool illustrations = false}) => {
        CreationOptionValues.detail: detail,
        CreationOptionValues.illustrations: illustrations,
        InfographicOptionKeys.style: 'clay',
      };
      expect(infographicOutputTokens(o('concise')), 1100);
      expect(infographicOutputTokens(o('standard')), 1700);
      expect(infographicOutputTokens(o('detailed')), 2600);
      expect(
        infographicOutputTokens(o('standard', illustrations: true)),
        1700 + 40 * 8,
      );
    });
  });

  group('qué se ilustra', () {
    final sheet = sampleSheet();

    test('un estilo ilustrado: la cabecera primero y los bloques con lugar '
        'para un dibujo, de lo que más pesa a lo que menos', () {
      final slots = InfographicIllustrationPlan.slotsFor(
        sheet,
        const InfographicDesign(style: InfographicStyleId.clay),
      );
      // Estándar: se ven los de nivel 1 y 2; la cifra, la comparación, la
      // cita y el gráfico no llevan.
      expect(slots.map((s) => s.id), [
        InfographicSlot.headerId,
        'block-1',
        'block-2',
        'block-4',
        'block-5',
      ]);
      expect(slots.first.isHeader, isTrue);
      expect(slots.first.prompt, 'El mar abierto al amanecer');
      // Lo que no escribió la IA se describe con el bloque.
      expect(slots[2].prompt, contains('Salida de Egipto'));
      expect(slots[1].aspect, IllustrationAspect.square);
    });

    test('la cabecera es casi cuadrada en la vertical y más ancha en las '
        'otras', () {
      IllustrationAspect header(InfographicOrientation o) =>
          InfographicIllustrationPlan.slotsFor(
            sheet,
            InfographicDesign(style: InfographicStyleId.photo, orientation: o),
          ).first.aspect;
      expect(
        header(InfographicOrientation.portrait),
        IllustrationAspect.square,
      );
      expect(
        header(InfographicOrientation.landscape),
        IllustrationAspect.classic,
      );
      expect(header(InfographicOrientation.square), IllustrationAspect.classic);
    });

    test('un estilo dibujado: solo los bloques que la pidieron, sin '
        'cabecera', () {
      final slots = InfographicIllustrationPlan.slotsFor(
        sheet,
        const InfographicDesign(style: InfographicStyleId.editorial),
      );
      expect(slots.map((s) => s.id), ['block-1']);
      expect(
        InfographicIllustrationPlan.slotsFor(
          sampleSheet(illustrations: false),
          const InfographicDesign(style: InfographicStyleId.editorial),
        ),
        isEmpty,
      );
    });

    test('«Conciso» deja solo lo esencial', () {
      final slots = InfographicIllustrationPlan.slotsFor(
        sheet,
        const InfographicDesign(
          style: InfographicStyleId.kawaii,
          detail: InfographicDetail.concise,
        ),
      );
      expect(slots.map((s) => s.id), [
        InfographicSlot.headerId,
        'block-1',
        'block-2',
      ]);
    });

    test('anotar, leer y quitar una ilustración; las que faltan', () {
      const design = InfographicDesign(style: InfographicStyleId.clay);
      var drawn = InfographicIllustrationPlan.withReference(
        sheet,
        InfographicSlot.headerId,
        'originales/c/ilustraciones/header.png',
      );
      drawn = InfographicIllustrationPlan.withReference(
        drawn,
        'block-4',
        'originales/c/ilustraciones/block-4.png',
      );
      expect(
        InfographicIllustrationPlan.referenceOf(drawn, 'block-4'),
        'originales/c/ilustraciones/block-4.png',
      );
      expect(drawn.blocks[4], isA<EventBlock>());
      expect(InfographicIllustrationPlan.references(drawn), {
        'originales/c/ilustraciones/header.png',
        'originales/c/ilustraciones/block-4.png',
      });
      expect(
        InfographicIllustrationPlan.missing(drawn, design).map((s) => s.id),
        ['block-1', 'block-2', 'block-5'],
      );
      final cleared = InfographicIllustrationPlan.withReference(
        drawn,
        'block-4',
        null,
      );
      expect(InfographicIllustrationPlan.referenceOf(cleared, 'block-4'), null);
      // Un lugar que no existe no cambia nada.
      expect(
        InfographicIllustrationPlan.withReference(drawn, 'block-99', 'x'),
        drawn,
      );
      expect(InfographicIllustrationPlan.referenceOf(drawn, 'otro'), isNull);
    });
  });

  group('el contenido guardado', () {
    test('la lámina, las que no salieron y la cuenta van y vuelven', () {
      final content = InfographicContent(
        sheet: sampleSheet(),
        failures: const {
          InfographicSlot.headerId: ImageFailure.noBilling,
          'block-2': ImageFailure.rateLimited,
        },
        accountLabel: 'Personal',
      );
      final back = InfographicContent.decode(content.encode());
      expect(back.sheet, content.sheet);
      expect(back.failures, content.failures);
      expect(back.accountLabel, 'Personal');
      // La ruta de cada ilustración va con la clave que lee la unión de
      // bóvedas (`studyCreationFilesSql`).
      final drawn = InfographicIllustrationPlan.withReference(
        content.sheet,
        'block-1',
        'originales/c/ilustraciones/block-1.png',
      );
      expect(
        InfographicContent(sheet: drawn).encode(),
        contains('"illustration_ref":"originales/c/ilustraciones/block-1.png"'),
      );
    });

    test('lee con tolerancia: la lámina sola, motivos que no conoce, nada', () {
      final bare = InfographicContent.decode(sampleReply());
      expect(bare.sheet.title, 'Éxodo: liberación y alianza');
      expect(bare.failures, isEmpty);

      final odd = InfographicContent.decode(
        jsonEncode({
          'sheet': jsonDecode(sampleReply()),
          'illustrations': {
            'failed': {'header': 'algo-nuevo', 'block-1': 'noCredits', '3': 1},
          },
        }),
      );
      expect(odd.failures, {'block-1': ImageFailure.noCredits});

      expect(InfographicContent.decode(null).sheet.blocks, isEmpty);
      expect(InfographicContent.decode('no es json').sheet.blocks, isEmpty);
    });
  });

  group('lo que se le pide a la IA', () {
    test('sin ilustraciones, que no las describa', () {
      final task = InfographicPrompts.task(
        const InfographicDesign(),
        illustrations: 0,
      );
      expect(task, contains('No escribas "illustration_prompt"'));
      expect(task, contains('vertical'));
      expect(task, isNot(contains('style_hint')));
    });

    test(
      '«Automático» con ilustraciones elige entre los estilos ilustrados',
      () {
        final task = InfographicPrompts.task(
          const InfographicDesign(
            orientation: InfographicOrientation.landscape,
          ),
          illustrations: 8,
        );
        expect(task, contains('"style_hint"'));
        expect(task, contains('"clay"'));
        expect(task, isNot(contains('"editorial"')));
        expect(task, contains('en la cabecera y en cada bloque'));
        expect(task, contains('horizontal'));
      },
    );

    test('un estilo dibujado pide pocas descripciones de ilustración', () {
      final task = InfographicPrompts.task(
        const InfographicDesign(
          style: InfographicStyleId.corporate,
          detail: InfographicDetail.detailed,
        ),
        illustrations: 4,
      );
      expect(task, contains('solo en los 4 bloques'));
      expect(task, isNot(contains('style_hint')));
    });

    test('por partes, cada parte elige sus mejores bloques y el paso de unir '
        'elige y ordena entre todos', () {
      const design = InfographicDesign(style: InfographicStyleId.clay);
      expect(
        InfographicPrompts.partTask(design, illustrations: 5),
        contains('hasta ${InfographicPrompts.blocksPerPart} bloques'),
      );
      final merge = InfographicPrompts.mergeTask(design, illustrations: 5);
      expect(merge, contains('elegí los mejores bloques sin repetir'));
      expect(merge, contains('ordenalos'));
    });

    test('el esquema lleva el detalle', () {
      expect(
        InfographicPrompts.schema(InfographicDetail.concise),
        contains('Detalle "conciso"'),
      );
    });

    test('una respuesta sin bloques, o con uno solo, se manda a corregir; un '
        'borrador con uno vale', () {
      expect(
        () => InfographicPrompts.parse({'title': 'x', 'blocks': <Object>[]}),
        throwsFormatException,
      );
      final one = {
        'title': 'x',
        'blocks': [
          {'type': 'fact', 'title': 'Una idea'},
        ],
      };
      expect(() => InfographicPrompts.parse(one), throwsFormatException);
      expect(InfographicPrompts.parsePart(one).blocks, hasLength(1));
      expect(
        InfographicPrompts.parse(jsonDecode(sampleReply())).blocks,
        hasLength(InfographicJson.decode(sampleReply()).blocks.length),
      );
      expect(
        InfographicPrompts.parse(jsonDecode(sampleReply())),
        isA<Infographic>(),
      );
    });
  });
}
