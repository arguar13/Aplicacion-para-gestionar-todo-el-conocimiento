import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_flows.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_grids.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';

import '../support/infographic_muestrario.dart';
import '../support/sample_infographics.dart';

/// La lámina dibujada (F43): «Automática» elige la composición por el
/// contenido, el detalle cambia lo que se ve sin pedir nada, cada bloque se
/// lee en voz alta y el lugar dibujado ocupa el de una ilustración que falta.
void main() {
  setUpAll(loadInfographicFonts);

  Future<void> pump(
    WidgetTester tester,
    Infographic sheet,
    InfographicDesign design, {
    InfographicIllustrationResolver? illustrations,
  }) async {
    tester.view
      ..physicalSize = const Size(540, 960)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Center(
        child: InfographicView(
          sheet: sheet,
          design: design,
          illustrations: illustrations,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('«Automática» arma cada contenido con su composición', (
    tester,
  ) async {
    await pump(tester, timelineInfographic(), const InfographicDesign());
    expect(find.byType(TimelineComposition), findsOneWidget);
    await pump(tester, dataInfographic(), const InfographicDesign());
    expect(find.byType(StatPanelComposition), findsOneWidget);
    await pump(tester, processInfographic(), const InfographicDesign());
    expect(find.byType(ProcessComposition), findsOneWidget);
    await pump(tester, conceptsInfographic(), const InfographicDesign());
    expect(find.byType(ConceptMapComposition), findsOneWidget);
    // Y la elegida a mano manda.
    await pump(
      tester,
      timelineInfographic(),
      const InfographicDesign(composition: InfographicComposition.pyramid),
    );
    expect(find.byType(PyramidComposition), findsOneWidget);
    expect(find.byType(TimelineComposition), findsNothing);
  });

  testWidgets('en la pirámide, una cifra va con su número en el texto', (
    tester,
  ) async {
    await pump(
      tester,
      sampleInfographic(),
      const InfographicDesign(composition: InfographicComposition.pyramid),
    );
    expect(find.text('40 años'), findsOneWidget);
    expect(find.text('de travesía por el desierto'), findsOneWidget);
  });

  testWidgets('el detalle cambia lo que se ve, sin pedir nada', (tester) async {
    final sheet = sampleInfographic();
    await pump(
      tester,
      sheet,
      const InfographicDesign(
        composition: InfographicComposition.bento,
        detail: InfographicDetail.concise,
      ),
    );
    // Lo esencial, sin su detalle.
    expect(find.text('La zarza que arde'), findsOneWidget);
    expect(
      find.text('Moisés recibe el llamado y el nombre de Dios.'),
      findsNothing,
    );
    expect(find.text('El paso del mar'), findsNothing);

    await pump(
      tester,
      sheet,
      const InfographicDesign(
        composition: InfographicComposition.bento,
        detail: InfographicDetail.detailed,
      ),
    );
    expect(
      find.text('Moisés recibe el llamado y el nombre de Dios.'),
      findsOneWidget,
    );
    expect(find.text('El paso del mar'), findsOneWidget);
    expect(find.text('Capítulos por parte'), findsOneWidget);
  });

  testWidgets('cada bloque se lee en voz alta, con el título de la lámina', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      sampleInfographic(),
      const InfographicDesign(detail: InfographicDetail.detailed),
    );
    expect(find.bySemanticsLabel('Éxodo: liberación y alianza'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        '40 años. de travesía por el desierto. Una generación entera camina '
        'hasta la tierra prometida.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Capítulos por parte. Egipto: 15 cap.; Desierto: 3 cap.; Sinaí: 22 '
        'cap.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('una ilustración ya hecha ocupa el lugar dibujado', (
    tester,
  ) async {
    final png = await tester.runAsync(() => solidPng(const Color(0xFF00FF00)));
    final sheet = conceptsInfographic().copyWith(
      blocks: [
        (conceptsInfographic().blocks.first as ConceptBlock).copyWith(
          illustrationRef: 'creaciones/1.png',
        ),
        ...conceptsInfographic().blocks.skip(1),
      ],
    );
    final asked = <String>[];
    await pump(
      tester,
      sheet,
      const InfographicDesign(
        style: InfographicStyleId.clay,
        composition: InfographicComposition.zigzag,
      ),
      illustrations: (reference) {
        asked.add(reference);
        return MemoryImage(png!);
      },
    );
    expect(asked, contains('creaciones/1.png'));
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('sin bloques, la lámina se dibuja igual (solo la cabecera)', (
    tester,
  ) async {
    await pump(
      tester,
      const Infographic(title: 'Vacía'),
      const InfographicDesign(),
    );
    expect(find.text('Vacía'), findsOneWidget);
  });

  testWidgets('cada composición se dibuja con la suya', (tester) async {
    const expected = {
      InfographicComposition.bento: BentoComposition,
      InfographicComposition.columns: ColumnsComposition,
      InfographicComposition.zigzag: ZigzagComposition,
      InfographicComposition.timeline: TimelineComposition,
      InfographicComposition.process: ProcessComposition,
      InfographicComposition.radial: RadialComposition,
      InfographicComposition.comparison: ComparisonComposition,
      InfographicComposition.pyramid: PyramidComposition,
      InfographicComposition.statPanel: StatPanelComposition,
      InfographicComposition.conceptMap: ConceptMapComposition,
    };
    expect(expected.keys.toSet(), InfographicComposition.concrete.toSet());
    for (final MapEntry(key: composition, value: type) in expected.entries) {
      await pump(
        tester,
        sampleInfographic(),
        InfographicDesign(composition: composition),
      );
      expect(find.byType(type), findsOneWidget, reason: composition.jsonName);
    }
  });
}
