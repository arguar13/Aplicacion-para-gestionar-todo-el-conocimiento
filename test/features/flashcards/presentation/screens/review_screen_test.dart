import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Un doble en vez de `AnkiPackageBuilder` de verdad: ese ya se prueba a
/// fondo en `anki_package_builder_test.dart`, y abrir ahí una segunda
/// conexión SQLite cruda mientras corre bajo `testWidgets` se cuelga —un
/// problema del entorno de pruebas de Flutter, no de la clase en sí (un
/// `test()` liso, sin bindings de Flutter, la abre sin problema). Lo que
/// importa acá es solo que la pantalla la llame y reaccione bien.
class _FakeAnkiDeckBuilder implements AnkiDeckBuilder {
  @override
  Future<Uint8List> build(List<AnkiCardExport> cards) async {
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpReview(WidgetTester tester) async {
    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            exportFlashcardsToAnkiUseCaseProvider.overrideWith(
              (ref) => ExportFlashcardsToAnkiUseCase(
                flashcards: ref.watch(flashcardRepositoryProvider),
                topics: ref.watch(ankiTopicResolverProvider),
                bibliography: ref.watch(bibliographyRepositoryProvider),
                locator: ref.watch(fragmentLocatorResolverProvider),
                citationStyle: ref.watch(defaultCitationStyleProvider),
                citationLanguage: ref.watch(defaultCitationLanguageProvider),
                builder: _FakeAnkiDeckBuilder(),
                saver: ref.watch(fileSaverProvider),
              ),
            ),
          ],
          child: const ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el botón de exportar a Anki aparece en la barra superior', (
    tester,
  ) async {
    await pumpReview(tester);

    expect(find.byTooltip('Exportar mazo a Anki'), findsOneWidget);
  });

  testWidgets('tocar el botón arma el .apkg y lo pasa al selector', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();
    // F17, D4: el diálogo pregunta el alcance antes de exportar.
    await tester.tap(find.byKey(const Key('review-export-confirm')));
    await tester.pumpAndSettle();

    expect(harness.fileSaver.savedFileName, 'sinapsis.apkg');
    expect(harness.fileSaver.savedBytes, isNotNull);
  });

  testWidgets('si el selector de guardado falla, avisa con un mensaje', (
    tester,
  ) async {
    harness.fileSaver.error = StateError('el diálogo se cayó');
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-export-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('cancelar el diálogo no exporta nada', (tester) async {
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(harness.fileSaver.savedFileName, isNull);
  });

  testWidgets('elegir TSV en el diálogo exporta un .tsv (F17, commit 5)', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-export-format-tsv')));
    await tester.tap(find.byKey(const Key('review-export-confirm')));
    await tester.pumpAndSettle();

    expect(harness.fileSaver.savedFileName, 'sinapsis.tsv');
  });

  group('la racha en la barra superior (F17, D3/commit 8)', () {
    testWidgets('sin ninguna racha, no muestra nada', (tester) async {
      await pumpReview(tester);

      expect(find.byKey(const Key('review-streak-indicator')), findsNothing);
    });

    testWidgets('con algo hecho hoy, muestra los días y avisa que ya cuenta', (
      tester,
    ) async {
      await harness.database
          .into(harness.database.habitEvents)
          .insert(
            HabitEventsCompanion.insert(
              id: 'ev-1',
              kind: HabitEventKind.triage,
              occurredAt: harness.container.read(clockProvider)(),
            ),
          );

      await pumpReview(tester);

      expect(find.byKey(const Key('review-streak-indicator')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip(es.reviewStreakActiveTooltip(1)), findsOneWidget);
    });

    testWidgets(
      'con algo hecho ayer y nada hoy todavía, sigue viva pero avisa que '
      'falta hacer algo',
      (tester) async {
        await harness.database
            .into(harness.database.habitEvents)
            .insert(
              HabitEventsCompanion.insert(
                id: 'ev-1',
                kind: HabitEventKind.vocabulary,
                occurredAt: harness.container
                    .read(clockProvider)()
                    .subtract(const Duration(days: 1)),
              ),
            );

        await pumpReview(tester);

        expect(
          find.byKey(const Key('review-streak-indicator')),
          findsOneWidget,
        );
        expect(find.text('1'), findsOneWidget);
        expect(
          find.byTooltip(es.reviewStreakPendingTooltip(1)),
          findsOneWidget,
        );
      },
    );
  });

  group('ver de dónde salió la tarjeta (F11)', () {
    /// Guarda una fuente y le crea una tarjeta; con [range], dice de qué
    /// fragmento sale.
    Future<String> seedCard({({int start, int end})? range}) async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final id = items.single.id;
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(
            itemId: id,
            front: '¿Qué señala?',
            back: 'El texto.',
            sourceCharStart: range?.start,
            sourceCharEnd: range?.end,
          );
      return id;
    }

    Future<void> pumpRouted(WidgetTester tester) async {
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.pushTo(RoutePaths.review);
      await tester.pumpAndSettle();
    }

    testWidgets('con la respuesta a la vista, ofrece ir a la fuente; antes '
        'no', (tester) async {
      await seedCard(range: (start: 4, end: 12));
      await pumpRouted(tester);

      expect(find.text(es.flashcardsViewSource), findsNothing);

      await tester.tap(find.text(es.reviewShowAnswer));
      await tester.pumpAndSettle();

      expect(find.text(es.flashcardsViewSource), findsOneWidget);
    });

    testWidgets('una tarjeta que no dice de dónde salió no lo ofrece', (
      tester,
    ) async {
      await seedCard();
      await pumpRouted(tester);

      await tester.tap(find.text(es.reviewShowAnswer));
      await tester.pumpAndSettle();

      expect(find.text(es.flashcardsViewSource), findsNothing);
    });

    testWidgets('tocarlo abre la lectura en ese fragmento', (tester) async {
      final id = await seedCard(range: (start: 4, end: 12));
      await pumpRouted(tester);
      await tester.tap(find.text(es.reviewShowAnswer));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.flashcardsViewSource));
      await tester.pumpAndSettle();

      final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(reading.itemId, id);
      expect(reading.jump, (start: 4, end: 12));
    });
  });
}
