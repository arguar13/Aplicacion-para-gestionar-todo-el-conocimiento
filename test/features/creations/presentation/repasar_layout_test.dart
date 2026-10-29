import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';

import 'repasar_harness.dart';

/// Repasar nuevo (F43, paso 6) en un teléfono de 360 dp con la letra al
/// doble, en los nueve temas: la pantalla entera —con «Para hoy», la grilla y
/// lo creado en cada estado—, la hoja de personalizar con la tarjeta «Con tu
/// IA actual» y la hoja del selector, sin que nada se desborde. Es la raíz
/// del desborde de 72 px que tenía la entrada de antes a 800 de alto.
void main() {
  late RepasarHarness harness;

  setUp(() async {
    harness = await RepasarHarness.create();
    await harness.processed(
      'p-1',
      'Declaración de los Derechos del Hombre y del Ciudadano, comentada',
      cards: 3,
    );
    await harness.processed('p-2', 'Génesis', cards: 1);
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(itemId: 'p-2', front: '¿Otra?', back: 'Sí');
    await harness.creation(
      StudyCreationKind.report,
      sources: ['p-1', 'p-2', 'ya-no-esta'],
      title: 'Análisis exegético del Éxodo: liberación, alianza y ley',
    );
    await harness.creation(
      StudyCreationKind.presentation,
      status: CreationStatus.generating,
      progress: 0.35,
      step: CreationStep.readingParts,
      sources: ['p-1'],
    );
    await harness.creation(
      StudyCreationKind.quiz,
      status: CreationStatus.failed,
      failure: CreationFailure.error,
      sources: ['p-2'],
    );
    await harness.creation(
      StudyCreationKind.mindMap,
      status: CreationStatus.queued,
      runNow: false,
      scope: const CreationScope.notebook('borrado'),
      sources: ['p-1'],
    );
  });

  Future<void> scrollToEnd(WidgetTester tester, Finder scrollable) async {
    for (var i = 0; i < 30; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  }

  for (final theme in AppThemeChoice.values) {
    testWidgets('360 dp, letra al doble, tema ${theme.name}: nada se '
        'desborda', (tester) async {
      await harness.openRepasar(
        tester,
        size: const Size(360, 800),
        theme: theme,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      // La pantalla entera, de arriba a abajo.
      await scrollToEnd(tester, find.byKey(const Key('review-entry')));

      // La hoja de personalizar de la infografía, con sus ilustraciones.
      final tile = find.byKey(
        ValueKey('creation-kind-${StudyCreationKind.infographic.storageKey}'),
      );
      await tester.drag(
        find.byKey(const Key('review-entry')),
        const Offset(0, 20000),
      );
      await tester.pumpAndSettle();
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
      expect(tester.takeException(), isNull);
      final toggle = find.byKey(
        const ValueKey('creation-option-${CreationOptionValues.illustrations}'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final sources = find.byKey(const Key('creation-sources-toggle'));
      await tester.ensureVisible(sources);
      await tester.pumpAndSettle();
      await tester.tap(sources);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creation-source-option-p-1')),
        findsOne,
      );
      await scrollToEnd(
        tester,
        find
            .descendant(
              of: find.byKey(const Key('creation-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('creation-sheet-close')));
      await tester.pumpAndSettle();

      // La hoja del selector, en sus cuatro pestañas.
      await tester.drag(
        find.byKey(const Key('review-entry')),
        const Offset(0, 20000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('repasar-scope')));
      await tester.pumpAndSettle();
      for (final tab in ['document', 'notebook', 'topic', 'all']) {
        final chip = find.byKey(Key('creation-scope-tab-$tab'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
