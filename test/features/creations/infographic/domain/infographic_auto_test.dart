import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

import '../support/sample_infographics.dart';

/// «Automático», «Automática» y el detalle (F43): todo determinista y sin
/// volver a la IA.
void main() {
  InfographicComposition auto(Infographic sheet) =>
      InfographicAuto.compositionFor(sheet, sheet.blocks);

  Infographic only(List<InfographicBlock> blocks, {String? hint}) =>
      Infographic(title: 'T', blocks: blocks, compositionHint: hint);

  const fact = InfographicBlock.fact(title: 'Idea', detail: 'Algo');
  const concept = InfographicBlock.concept(title: 'Concepto');
  const event = InfographicBlock.event(date: '1492', title: 'Hito');
  const step = InfographicBlock.step(title: 'Paso');
  const stat = InfographicBlock.stat(value: '40 %', label: 'algo');
  const comparison = InfographicBlock.comparison(
    left: InfographicSide(heading: 'A', points: ['a']),
    right: InfographicSide(heading: 'B', points: ['b']),
  );

  group('la composición automática', () {
    test('cada contenido con la suya', () {
      expect(auto(timelineInfographic()), InfographicComposition.timeline);
      expect(auto(processInfographic()), InfographicComposition.process);
      expect(auto(dataInfographic()), InfographicComposition.statPanel);
      expect(auto(conceptsInfographic()), InfographicComposition.conceptMap);
      expect(auto(sampleInfographic()), InfographicComposition.bento);
      expect(
        auto(only([comparison, fact, stat])),
        InfographicComposition.comparison,
      );
      expect(auto(only([fact, fact, concept])), InfographicComposition.columns);
      expect(
        auto(only([fact, concept, fact, fact, concept])),
        InfographicComposition.radial,
      );
    });

    test('con ilustraciones pedidas, ideas en zigzag', () {
      const illustrated = InfographicBlock.fact(
        title: 'Idea',
        illustrationPrompt: 'Un río',
      );
      expect(
        auto(only([illustrated, illustrated, illustrated, fact, fact])),
        InfographicComposition.zigzag,
      );
    });

    test('lo que no alcanza para una forma cae en la de bloques', () {
      // Dos hitos no hacen una cronología, ni dos pasos un proceso.
      expect(
        auto(only([event, event, fact, stat, fact, fact, fact, fact])),
        InfographicComposition.bento,
      );
      // Ni tres hitos perdidos entre muchas otras cosas: no son la mitad.
      expect(
        auto(only([event, event, event, fact, fact, fact, fact, stat])),
        InfographicComposition.bento,
      );
      expect(
        auto(only([step, step, fact, concept, stat, fact, fact, fact])),
        InfographicComposition.bento,
      );
      // Una comparación con mucho alrededor tampoco manda.
      expect(
        auto(only([comparison, fact, fact, fact, fact, fact])),
        InfographicComposition.bento,
      );
    });

    test('la sugerencia de la IA, si el contenido la sostiene', () {
      expect(
        auto(only([fact, fact, fact, fact], hint: 'pyramid')),
        InfographicComposition.pyramid,
      );
      expect(
        auto(only([fact, fact, fact, fact], hint: 'piramide')),
        InfographicComposition.pyramid,
      );
      // Una cronología sin hitos, no.
      expect(
        auto(only([fact, fact, fact], hint: 'timeline')),
        InfographicComposition.columns,
      );
      expect(
        auto(only([fact, fact, fact], hint: 'inventada')),
        InfographicComposition.columns,
      );
    });

    test('es siempre la misma', () {
      final sheet = sampleInfographic();
      final first = auto(sheet);
      for (var i = 0; i < 5; i++) {
        expect(auto(sheet), first);
      }
    });
  });

  group('el estilo automático', () {
    test('el que sugirió la IA, en inglés o en castellano', () {
      Infographic hinted(String hint) =>
          Infographic(title: 'T', styleHint: hint, blocks: const [fact]);
      expect(
        InfographicAuto.styleFor(hinted('chalkboard')),
        InfographicStyleId.chalkboard,
      );
      expect(
        InfographicAuto.styleFor(hinted('plastilina')),
        InfographicStyleId.clay,
      );
      expect(
        InfographicAuto.styleFor(hinted('neon_oscuro')),
        InfographicStyleId.neon,
      );
      // «auto» o uno desconocido no es una sugerencia.
      expect(
        InfographicAuto.styleFor(hinted('auto')),
        InfographicStyleId.bento,
      );
      expect(
        InfographicAuto.styleFor(hinted('barroco')),
        InfographicStyleId.bento,
      );
    });

    test('sin sugerencia, el que dicen los bloques', () {
      expect(
        InfographicAuto.styleFor(dataInfographic()),
        InfographicStyleId.data,
      );
      expect(
        InfographicAuto.styleFor(timelineInfographic()),
        InfographicStyleId.editorial,
      );
      expect(
        InfographicAuto.styleFor(processInfographic()),
        InfographicStyleId.corporate,
      );
      expect(
        InfographicAuto.styleFor(only([comparison, fact])),
        InfographicStyleId.swiss,
      );
      expect(
        InfographicAuto.styleFor(conceptsInfographic()),
        InfographicStyleId.geometric,
      );
      expect(
        InfographicAuto.styleFor(
          only([fact, const InfographicBlock.quote(quote: 'Algo')]),
        ),
        InfographicStyleId.parchment,
      );
    });
  });

  group('el detalle', () {
    final sheet = sampleInfographic();

    test('conciso, estándar y detallado muestran cada vez más', () {
      List<InfographicBlockKind> kinds(InfographicDetail detail) => [
        for (final b in InfographicAuto.visibleBlocks(sheet, detail)) b.kind,
      ];
      expect(kinds(InfographicDetail.concise), [
        InfographicBlockKind.stat,
        InfographicBlockKind.fact,
        InfographicBlockKind.step,
      ]);
      expect(kinds(InfographicDetail.standard), hasLength(6));
      expect(kinds(InfographicDetail.detailed), hasLength(8));
    });

    test('nunca menos de tres: entran los que más pesan, en su orden', () {
      const heavy = Infographic(
        title: 'T',
        blocks: [
          InfographicBlock.fact(title: 'a', level: InfographicLevel.extra),
          InfographicBlock.fact(title: 'b', level: InfographicLevel.supporting),
          InfographicBlock.fact(title: 'c', level: InfographicLevel.extra),
          InfographicBlock.fact(title: 'd'),
          InfographicBlock.fact(title: 'e', level: InfographicLevel.extra),
        ],
      );
      expect(
        InfographicAuto.visibleBlocks(
          heavy,
          InfographicDetail.concise,
        ).map((b) => b.headline),
        ['a', 'b', 'd'],
      );
      expect(
        InfographicAuto.visibleBlocks(
          minimalInfographic(),
          InfographicDetail.concise,
        ),
        hasLength(1),
      );
    });

    test('en conciso no van los detalles', () {
      expect(
        InfographicAuto.arrange(
          sheet,
          const InfographicDesign(detail: InfographicDetail.concise),
        ).showDetails,
        isFalse,
      );
      expect(
        InfographicAuto.arrange(sheet, const InfographicDesign()).showDetails,
        isTrue,
      );
    });
  });

  group('lo que entra en cada composición', () {
    test('lo de más se queda afuera, empezando por lo que menos pesa', () {
      final many = Infographic(
        title: 'T',
        blocks: [
          for (var i = 0; i < 12; i++)
            InfographicBlock.fact(
              title: 'b$i',
              level: i.isEven
                  ? InfographicLevel.essential
                  : InfographicLevel.extra,
            ),
        ],
      );
      final arranged = InfographicAuto.arrange(
        many,
        const InfographicDesign(
          composition: InfographicComposition.pyramid,
          detail: InfographicDetail.detailed,
        ),
      );
      expect(arranged.composition, InfographicComposition.pyramid);
      expect(arranged.blocks.map((b) => b.headline), [
        'b0',
        'b2',
        'b4',
        'b6',
        'b8',
      ]);
    });

    test('cada composición tiene lugar al menos para cinco', () {
      for (final composition in InfographicComposition.values) {
        for (final orientation in InfographicOrientation.values) {
          expect(
            InfographicAuto.capacity(composition, orientation),
            greaterThanOrEqualTo(5),
          );
        }
      }
    });

    test('«Automático» se resuelve: nunca queda en el arreglo', () {
      final arranged = InfographicAuto.arrange(
        dataInfographic(),
        const InfographicDesign(),
      );
      expect(arranged.style, InfographicStyleId.data);
      expect(arranged.composition, InfographicComposition.statPanel);
    });
  });
}
