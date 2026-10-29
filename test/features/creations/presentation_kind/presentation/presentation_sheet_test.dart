import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/presentation_harness.dart';

/// La hoja de la Presentación (F43, paso 11): el tipo registrado, elegir la
/// plantilla viéndola, el estilo de las ilustraciones y lo que se avisa que
/// consume. El camino con la cola de verdad está en
/// `presentation_generator_test.dart`; el visor, en
/// `presentation_viewer_test.dart`.
void main() {
  final es = AppLocalizationsEs();
  late PresentationHarness h;

  setUp(() async {
    h = await PresentationHarness.create();
    await h.processed('d1', 'Éxodo');
  });

  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(420, 1400),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    await h.open(
      tester,
      '/review',
      size: size,
      theme: theme,
      textScale: textScale,
    );
    final tile = find.byKey(const ValueKey('creation-kind-presentation'));
    for (var i = 0; i < 20 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scaffold).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  /// Desliza la tira [strip] hasta que se vea [tile].
  Future<void> reveal(WidgetTester tester, Finder tile, String strip) async {
    await tester.scrollUntilVisible(
      tile,
      150,
      scrollable: find
          .descendant(
            of: find.byKey(Key(strip)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  test('el tipo registrado: su tira en vez del desplegable, sus estimaciones '
      'y su visor', () {
    final spec = h.container
        .read(creationKindRegistryProvider)
        .of(StudyCreationKind.presentation);
    expect(spec.optionsBuilder, isNotNull);
    expect(spec.viewerBuilder, isNotNull);
    expect(spec.viewerActions, isNotNull);
    expect(spec.exporter, isNotNull);
    expect(
      spec.options.map((o) => o.key),
      isNot(contains(CreationOptionValues.template)),
    );
    expect(spec.defaults[CreationOptionValues.template], 'auto');
    const standard = {CreationOptionValues.illustrations: true};
    const short = {
      CreationOptionValues.illustrations: true,
      CreationOptionValues.length: CreationOptionValues.short,
    };
    expect(spec.illustrationsFor(standard), 7);
    expect(spec.illustrationsFor(short), 4);
    expect(spec.illustrationsFor(const {}), 0);
    expect(spec.outputTokensFor(short), 8 * 225);

    // «Ver petición y fuentes»: la plantilla y el estilo, que no son
    // opciones de la hoja común.
    final lines = spec.requestLines!;
    expect(lines(es, const {CreationOptionValues.template: 'auto'}), [
      (es.f43StudioOptTemplate, es.f43StudioOptTemplateAuto),
    ]);
    expect(
      lines(es, const {
        CreationOptionValues.template: 'neon',
        CreationOptionValues.illustrations: true,
        PresentationOptionKeys.illustrationStyle: 'clay',
      }),
      [
        (es.f43StudioOptTemplate, es.f43DeckTemplateNeon),
        (es.f43PresIllustrationStyle, es.f43PresStyleClay),
      ],
    );
    // La que se eligió después, en el visor, manda.
    expect(
      lines(es, {
        CreationOptionValues.template: 'neon',
        PresentationOptionKeys.design: const DeckDesign(
          template: DeckTemplateId.swiss,
        ).toJson(),
      }),
      [(es.f43StudioOptTemplate, es.f43DeckTemplateSwiss)],
    );
  });

  testWidgets('elegir la plantilla viéndola, en la tira o en la galería; el '
      'estilo de las ilustraciones solo con ilustraciones, y el aviso las '
      'cuenta', (tester) async {
    await openSheet(tester);
    expect(find.byKey(const Key('presentation-options')), findsOneWidget);
    expect(
      find.byKey(const Key('presentation-template-strip')),
      findsOneWidget,
    );
    final auto = tester.getSemantics(
      find.byKey(const ValueKey('presentation-template-auto')),
    );
    expect(auto.label, es.f43DeckGallerySelected(es.f43StudioOptTemplateAuto));
    expect(find.byKey(const Key('presentation-style-strip')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('creation-option-illustrations')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-style-strip')), findsOneWidget);
    expect(h.estimates.last.images, 7);

    final clay = find.byKey(const ValueKey('presentation-style-clay'));
    await reveal(tester, clay, 'presentation-style-strip');
    await tester.tap(clay);
    await tester.pumpAndSettle();

    final swiss = find.byKey(const ValueKey('presentation-template-swiss'));
    await reveal(tester, swiss, 'presentation-template-strip');
    await tester.tap(swiss);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(swiss).label,
      es.f43DeckGallerySelected(es.f43DeckTemplateSwiss),
    );

    // La galería entera, y elegir ahí la cierra.
    await tester.tap(find.byKey(const Key('presentation-templates-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-gallery-sheet')), findsOneWidget);
    final midnight = find.byKey(const ValueKey('template-midnight'));
    await tester.scrollUntilVisible(
      midnight,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('presentation-gallery-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(midnight);
    await tester.pumpAndSettle();
    await tester.tap(midnight);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-gallery-sheet')), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('presentation-template-midnight')),
          )
          .label,
      es.f43DeckGallerySelected(es.f43DeckTemplateMidnight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('la hoja a 360 dp con la letra al doble, en oscuro, con las '
      'ilustraciones prendidas: nada desborda', (tester) async {
    await openSheet(
      tester,
      size: const Size(360, 720),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    final toggle = find.byKey(const ValueKey('creation-option-illustrations'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final styles = find.byKey(const Key('presentation-style-strip'));
    await tester.ensureVisible(styles);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
