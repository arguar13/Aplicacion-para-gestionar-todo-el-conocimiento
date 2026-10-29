import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_style_gallery.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_generators.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';

import '../../infographic/support/infographic_muestrario.dart';
import '../../presentation/repasar_harness.dart';

/// La hoja de crear la infografía (F43, paso 12): «Estilo visual» en un
/// carrusel con muestra, lo que estima según el estilo y el detalle, y lo que
/// se le pide a la cola. Y que la infografía está registrada.
void main() {
  setUpAll(loadInfographicFonts);

  late RepasarHarness harness;

  setUp(() async {
    final spec = ProviderContainer().read(infographicKindSpecProvider);
    harness = await RepasarHarness.create(specs: [spec]);
    await harness.processed('p-1', 'Éxodo — Comentario');
  });

  Future<void> openSheet(WidgetTester tester) async {
    final tile = find.byKey(
      ValueKey('creation-kind-${StudyCreationKind.infographic.storageKey}'),
    );
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseStyle(WidgetTester tester, String id) async {
    final tile = find.byKey(ValueKey('infographic-style-$id'));
    // Primero la tira, que con la letra grande queda más abajo en la hoja.
    await tester.ensureVisible(
      find.byKey(const Key('infographic-style-carousel')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('infographic-style-carousel')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapInSheet(tester, tile);
  }

  test('la infografía está registrada: su tipo y su generador', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final spec = container
        .read(creationKindRegistryProvider)
        .of(StudyCreationKind.infographic);
    expect(spec.viewerBuilder, isNotNull);
    expect(spec.viewerActions, isNotNull);
    expect(spec.exporter, isNotNull);
    expect(spec.optionsBuilder, isNotNull);
    expect(spec.defaults[InfographicOptionKeys.style], 'auto');
    expect(spec.offersIllustrations, isTrue);
    final generators = container.read(creationGeneratorRegistryProvider);
    expect(generators[StudyCreationKind.infographic], isA<CreationGenerator>());
    expect(
      generators[StudyCreationKind.infographic],
      same(container.read(infographicGeneratorProvider)),
    );
  });

  testWidgets('«Estilo visual» en un carrusel con la muestra; elegirlo cambia '
      'lo que estima y va en lo pedido', (tester) async {
    await harness.openRepasar(tester);
    await openSheet(tester);

    final carousel = find.byKey(const Key('infographic-style-carousel'));
    expect(carousel, findsOneWidget);
    expect(
      find.descendant(
        of: carousel,
        matching: find.byType(InfographicStyleTile),
      ),
      findsWidgets,
    );

    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-illustrations')),
    );
    // «Automático», con ilustraciones: la cabecera y siete bloques.
    expect(harness.estimates.last.images, 8);
    expect(
      harness.estimates.last.expectedOutputTokens,
      greaterThanOrEqualTo(1700 + 40 * 8),
    );

    await chooseStyle(tester, 'editorial');
    expect(harness.estimates.last.images, 3);

    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-detail-concise')),
    );
    expect(harness.estimates.last.images, 2);

    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    final options = harness.queue.requests.last.options;
    expect(options[InfographicOptionKeys.style], 'editorial');
    expect(options[CreationOptionValues.detail], 'concise');
    expect(options[CreationOptionValues.illustrations], true);
  });

  testWidgets('un estilo ilustrado sin «Ilustraciones con IA» dice que se ve '
      'con su versión dibujada', (tester) async {
    await harness.openRepasar(tester);
    await openSheet(tester);
    expect(find.byKey(const Key('infographic-style-drawn-note')), findsNothing);
    await chooseStyle(tester, 'clay');
    expect(
      find.byKey(const Key('infographic-style-drawn-note')),
      findsOneWidget,
    );
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-illustrations')),
    );
    expect(find.byKey(const Key('infographic-style-drawn-note')), findsNothing);
  });

  testWidgets('a 360 dp con la letra al doble y oscuro, sin desbordes', (
    tester,
  ) async {
    await harness.openRepasar(
      tester,
      size: const Size(360, 760),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    await openSheet(tester);
    await chooseStyle(tester, 'kawaii');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('infographic-style-drawn-note')),
      findsOneWidget,
    );
  });
}
