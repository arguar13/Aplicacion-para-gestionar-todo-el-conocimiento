import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_labels.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_style_gallery.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../presentation_deck/support/deck_widget_harness.dart';
import '../support/infographic_muestrario.dart';
import '../support/sample_infographics.dart';

/// La galería de estilos (F43, y los doce de F45): los treinta en sus dos
/// familias, cada uno con la lámina de la persona en vivo; elegir uno no
/// vuelve a la IA.
void main() {
  setUpAll(loadInfographicFonts);

  const design = InfographicDesign(
    composition: InfographicComposition.bento,
    paletteIndex: 3,
    fontPair: 'handwritten',
    orientation: InfographicOrientation.square,
    detail: InfographicDetail.detailed,
  );

  testWidgets('los treinta, en dos familias, con una muestra viva cada uno', (
    tester,
  ) async {
    final changes = <InfographicDesign>[];
    await pumpDeckScreen(
      tester,
      InfographicStyleGallery(
        sheet: sampleInfographic(),
        design: design,
        onChanged: changes.add,
      ),
      height: 1200,
    );
    expect(find.text('Dibujados por la app'), findsOneWidget);
    // Uno por uno, en orden y bajando: los de abajo aparecen al desplazar.
    for (final id in InfographicStyleId.values) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('infographic-style-${id.id}')),
        200,
      );
      expect(
        find.byKey(ValueKey('infographic-style-${id.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('Con ilustraciones con IA'), findsOneWidget);
    expect(
      find.text(
        'Sin una IA de imágenes se ven igual, con su versión dibujada.',
      ),
      findsOneWidget,
    );
    // Cada muestra es una lámina de verdad con el estilo de su tarjeta.
    final previews = tester.widgetList<InfographicView>(
      find.byType(InfographicView),
    );
    expect(previews, isNotEmpty);
    for (final preview in previews) {
      expect(preview.design.orientation, InfographicOrientation.square);
      expect(preview.sheet, sampleInfographic());
    }
  });

  testWidgets('elegir uno da su diseño de fábrica y deja lo demás', (
    tester,
  ) async {
    final changes = <InfographicDesign>[];
    await pumpDeckScreen(
      tester,
      InfographicStyleGallery(
        sheet: sampleInfographic(),
        design: design,
        onChanged: changes.add,
      ),
      height: 1200,
    );
    final tile = find.byKey(const ValueKey('infographic-style-chalkboard'));
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);
    expect(
      changes.single,
      const InfographicDesign(
        style: InfographicStyleId.chalkboard,
        composition: InfographicComposition.bento,
        orientation: InfographicOrientation.square,
        detail: InfographicDetail.detailed,
      ),
    );
  });

  testWidgets('«Automático» dice qué eligió, y el elegido se anuncia', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDeckScreen(
      tester,
      InfographicStyleGallery(
        sheet: dataInfographic(),
        design: const InfographicDesign(),
        onChanged: (_) {},
      ),
      height: 1200,
    );
    expect(find.text('Automático: Datos'), findsOneWidget);
    expect(find.bySemanticsLabel('Automático: Datos, elegido'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('el carrusel de la hoja de crear, con la lámina de muestra, en '
      '360 y con letra grande', (tester) async {
    for (final scale in [1.0, 2.0]) {
      final changes = <InfographicDesign>[];
      await pumpDeckScreen(
        tester,
        Builder(
          builder: (context) => ListView(
            children: [
              InfographicStyleCarousel(
                sheet: AppLocalizations.of(context)!.infographicSample(),
                design: const InfographicDesign(),
                onChanged: changes.add,
              ),
            ],
          ),
        ),
        width: 360,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      // Las muestras son la lámina de muestra, en el idioma de la app.
      expect(find.text('Tu tema en una lámina'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('infographic-style-editorial')),
      );
      expect(changes.single.style, InfographicStyleId.editorial);
    }
  });

  testWidgets('a 360 con letra grande y en modo oscuro, nada desborda', (
    tester,
  ) async {
    await pumpDeckScreen(
      tester,
      InfographicStyleGallery(
        sheet: sampleInfographic(),
        design: const InfographicDesign(),
        onChanged: (_) {},
      ),
      width: 360,
      textScale: 2,
      dark: true,
    );
    expect(tester.takeException(), isNull);
  });
}
