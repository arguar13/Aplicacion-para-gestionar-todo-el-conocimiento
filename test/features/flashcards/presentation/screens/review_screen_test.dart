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
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_preferences.dart';
import 'package:sinapsis/features/habit/presentation/screens/badges_screen.dart';
import 'package:sinapsis/features/habit/presentation/screens/review_history_screen.dart';
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

  testWidgets('el botón de insignias abre esa pantalla (F17, D7/commit 9b)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.pushTo(RoutePaths.review);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(es.reviewBadgesTooltip));
    await tester.pumpAndSettle();

    expect(find.byType(BadgesScreen), findsOneWidget);
  });

  testWidgets('el botón de historial abre esa pantalla (F17, D8/commit 10b)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.pushTo(RoutePaths.review);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(es.reviewHistoryTooltip));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewHistoryScreen), findsOneWidget);
  });

  testWidgets(
    'con el interruptor de hábito apagado (F17, D9), ninguno de los tres '
    'aparece —pero exportar a Anki (17.1) sigue—',
    (tester) async {
      await harness.container
          .read(habitFeaturesEnabledProvider.notifier)
          .setEnabled(enabled: false);

      await pumpReview(tester);

      expect(find.byKey(const Key('review-streak-indicator')), findsNothing);
      expect(find.byTooltip(es.reviewBadgesTooltip), findsNothing);
      expect(find.byTooltip(es.reviewHistoryTooltip), findsNothing);
      expect(find.byTooltip(es.reviewExportToAnkiTooltip), findsOneWidget);
    },
  );

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

  // Los botones de calificar eran `OutlinedButton`s con el relleno lateral
  // estándar: en un teléfono a cada uno le quedaban unos 40 puntos para el
  // texto, «De nuevo» se partía letra por letra y estiraba su botón.
  group('los botones de calificar', () {
    Future<void> openCard(WidgetTester tester, {double width = 360}) async {
      tester.view.physicalSize = Size(width * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(
            itemId: items.single.id,
            front: '¿Qué hizo Teodora?',
            back: 'Lo ayudó a escapar.',
          );
      await pumpReview(tester);
      await tester.tap(find.text(es.reviewShowAnswer));
      await tester.pumpAndSettle();
    }

    Finder button(String grade) => find.byKey(Key('grade-$grade'));

    for (final width in [320.0, 360.0, 412.0]) {
      testWidgets('miden lo mismo, y el texto entra sin partirse, en un '
          'teléfono de $width puntos', (tester) async {
        await openCard(tester, width: width);

        final sizes = [
          for (final grade in ['again', 'hard', 'good', 'easy'])
            tester.getSize(button(grade)),
        ];
        // El mismo ancho y el mismo alto, los cuatro.
        expect(sizes.map((s) => s.width).toSet().length, 1, reason: '$sizes');
        expect(sizes.map((s) => s.height).toSet().length, 1, reason: '$sizes');

        // Ninguna palabra partida: cada nombre es una sola línea, más baja
        // que dos renglones de su fuente.
        for (final label in [
          es.reviewGradeAgain,
          es.reviewGradeHard,
          es.reviewGradeGood,
          es.reviewGradeEasy,
        ]) {
          final text = tester.getSize(find.text(label));
          expect(text.height, lessThan(24), reason: '«$label» se partió');
        }
      });
    }

    testWidgets('cada uno dice cuándo vuelve la tarjeta', (tester) async {
      await openCard(tester);

      // Una tarjeta nueva (F31): vuelve en minutos dentro de la sesión, salvo
      // «Fácil», que se gradúa a 4 días.
      final expected = {
        'again': es.reviewIntervalMinutes(1),
        'hard': es.reviewIntervalMinutes(6),
        'good': es.reviewIntervalMinutes(10),
        'easy': es.reviewIntervalDays(4),
      };
      for (final entry in expected.entries) {
        expect(
          find.descendant(
            of: button(entry.key),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: entry.key,
        );
      }
    });

    testWidgets('«Mostrar respuesta» tiene la misma altura y forma', (
      tester,
    ) async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: items.single.id, front: '¿P?', back: 'R.');
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpReview(tester);

      final reveal = tester.getSize(
        find.byKey(const Key('review-show-answer')),
      );
      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();

      expect(reveal.height, tester.getSize(button('good')).height);
    });

    testWidgets('tocar uno califica la tarjeta: «Fácil» la gradúa y no queda '
        'nada', (tester) async {
      await openCard(tester);

      await tester.tap(button('easy'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grade-easy')), findsNothing);
      // Se contestó una: en vez del «no hay nada», el resumen de la sesión.
      expect(find.byKey(const Key('review-summary')), findsOneWidget);
      expect(find.text(es.reviewSessionSummaryTitle), findsOneWidget);
      expect(find.text(es.reviewAllDone), findsNothing);
    });

    testWidgets('«Bien» en una nueva la deja para dentro de 10 minutos: la '
        'sesión espera y lo dice (F31)', (tester) async {
      await openCard(tester);

      await tester.tap(button('good'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grade-good')), findsNothing);
      expect(find.byKey(const Key('review-waiting')), findsOneWidget);
      expect(find.text(es.reviewWaitMessage(1, 10)), findsOneWidget);
      expect(find.text(es.reviewAllDone), findsNothing);
    });
  });

  // La sesión sigue la cola de estudio (F31): lo que toca lo decide ella tras
  // cada respuesta, con los pasos de aprendizaje y los límites del día.
  group('la sesión sigue la cola de estudio (F31)', () {
    late String itemId;

    Future<void> addCards(List<String> fronts) async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      itemId = items.single.id;
      for (final front in fronts) {
        await harness.container
            .read(flashcardRepositoryProvider)
            .create(itemId: itemId, front: front, back: 'R de $front');
      }
    }

    Future<void> grade(WidgetTester tester, String grade) async {
      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('grade-$grade')));
      await tester.pumpAndSettle();
    }

    testWidgets('dice cuántas quedan y baja con cada una que se termina', (
      tester,
    ) async {
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      await pumpReview(tester);
      expect(find.text(es.reviewRemaining(3)), findsOneWidget);

      await grade(tester, 'easy');

      expect(find.text(es.reviewRemaining(2)), findsOneWidget);
    });

    testWidgets('«De nuevo» la deja para dentro de 1 minuto: pasa a la '
        'siguiente, y al no haber más espera y deja volver ya', (tester) async {
      await addCards(['¿Uno?', '¿Dos?']);
      await pumpReview(tester);
      expect(find.text('¿Uno?'), findsOneWidget);

      await grade(tester, 'again');
      // La que olvidó no vuelve enseguida: toca la otra.
      expect(find.text('¿Dos?'), findsOneWidget);
      expect(find.text('¿Uno?'), findsNothing);

      await grade(tester, 'easy');
      // No queda nada más que esa que vuelve en 1 minuto.
      expect(find.byKey(const Key('review-waiting')), findsOneWidget);
      expect(find.text(es.reviewWaitMessage(1, 1)), findsOneWidget);

      await tester.tap(find.text(es.reviewWaitNow));
      await tester.pumpAndSettle();

      expect(find.text('¿Uno?'), findsOneWidget);
      // Y los botones dicen lo que de verdad pasa con una que se está
      // aprendiendo en su primer paso.
      await tester.tap(find.byKey(const Key('review-show-answer')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('grade-good')),
          matching: find.text(es.reviewIntervalMinutes(10)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('al llegar al límite de nuevas de hoy lo dice, y «Estudiar más '
        'hoy» sigue', (tester) async {
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      await pumpReview(tester);
      expect(find.text(es.reviewRemaining(1)), findsOneWidget);

      await grade(tester, 'easy');

      expect(find.byKey(const Key('review-limit-reached')), findsOneWidget);
      expect(find.text(es.reviewLimitTitle), findsOneWidget);
      expect(find.text(es.reviewLimitMessage(2, 0)), findsOneWidget);
      expect(find.text(es.reviewAllDone), findsNothing);

      await tester.tap(find.text(es.reviewLimitMore));
      await tester.pumpAndSettle();

      expect(find.text('¿Dos?'), findsOneWidget);
    });

    testWidgets('una tarjeta pausada no se muestra', (tester) async {
      await addCards(['¿Uno?']);
      final card =
          (await harness.container.read(flashcardRepositoryProvider).getAll())
              .getRight()
              .toNullable()!
              .single;
      await harness.container.read(flashcardRepositoryProvider).suspend([
        card.id,
      ]);

      await pumpReview(tester);

      expect(find.text('¿Uno?'), findsNothing);
      expect(find.text(es.reviewAllDone), findsOneWidget);
    });

    testWidgets('si aparece una tarjeta mientras no había nada, la sesión la '
        'toma sola', (tester) async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      await pumpReview(tester);
      expect(find.text('¿Nueva?'), findsNothing);
      expect(find.byKey(const Key('review-show-answer')), findsNothing);

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: items.single.id, front: '¿Nueva?', back: 'R');
      await tester.pumpAndSettle();

      expect(find.text('¿Nueva?'), findsOneWidget);
    });
  });

  group('la insignia de Repasar en la navegación (F31)', () {
    testWidgets('cuenta lo que hay para estudiar hoy, respetando los límites '
        'y lo pausado', (tester) async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final cards = harness.container.read(flashcardRepositoryProvider);
      for (final front in ['¿1?', '¿2?', '¿3?']) {
        await cards.create(itemId: items.single.id, front: front, back: 'R');
      }
      Future<int> badge() async {
        final sub = harness.container.listen(
          studyDueTodayCountProvider,
          (_, _) {},
        );
        addTearDown(sub.close);
        await tester.pumpAndSettle();
        return sub.read().valueOrNull ?? -1;
      }

      expect(await badge(), 3);

      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(2);
      expect(await badge(), 2);

      final all = (await cards.getAll()).getRight().toNullable()!;
      await cards.suspend([all.first.id]);
      expect(await badge(), 2);
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(20);
      expect(await badge(), 2);
    });
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

  group('una tarjeta de opción múltiple (F20)', () {
    /// Guarda una fuente y le crea una tarjeta de opción múltiple, con un
    /// distractor anclado a OTRO elemento —mismo patrón real que
    /// `DistractorSourcer`—.
    Future<String> seedMultipleChoiceCard() async {
      await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
      await harness.capture('Otra fuente, con su propio texto.');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final cardItemId = items.first.id;
      final otherItemId = items.last.id;

      final card =
          (await harness.container
                  .read(flashcardRepositoryProvider)
                  .createMultipleChoice(
                    itemId: cardItemId,
                    front: '¿Qué señala?',
                    options: [
                      FlashcardOptionDraft(
                        content: 'El texto.',
                        isCorrect: true,
                        sourceItemId: cardItemId,
                        sourceCharStart: 4,
                        sourceCharEnd: 12,
                      ),
                      FlashcardOptionDraft(
                        content: 'Otro texto.',
                        isCorrect: false,
                        sourceItemId: otherItemId,
                        sourceCharStart: 0,
                        sourceCharEnd: 5,
                      ),
                    ],
                  ))
              .getRight()
              .toNullable()!;
      return card.id;
    }

    Future<void> pumpRouted(WidgetTester tester) async {
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.pushTo(RoutePaths.review);
      await tester.pumpAndSettle();
    }

    testWidgets('muestra la pregunta y sus opciones, sin revelar nada '
        'todavía', (tester) async {
      await seedMultipleChoiceCard();
      await pumpRouted(tester);

      expect(find.text('¿Qué señala?'), findsOneWidget);
      expect(find.text('El texto.'), findsOneWidget);
      expect(find.text('Otro texto.'), findsOneWidget);
      // No hay botón de "mostrar respuesta": de opción múltiple se
      // contesta tocando una opción.
      expect(find.text(es.reviewShowAnswer), findsNothing);
      // Todavía sin contestar, ningún grado.
      expect(find.text(es.reviewGradeGood), findsNothing);
    });

    testWidgets('tocar la opción correcta la revela y deja calificar', (
      tester,
    ) async {
      await seedMultipleChoiceCard();
      await pumpRouted(tester);

      await tester.tap(find.text('El texto.'));
      await tester.pumpAndSettle();

      expect(find.text(es.reviewGradeGood), findsOneWidget);
    });

    testWidgets(
      'tocar un distractor también revela, con la procedencia de las dos '
      'opciones visibles',
      (tester) async {
        await seedMultipleChoiceCard();
        await pumpRouted(tester);

        await tester.tap(find.text('Otro texto.'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.menu_book_outlined), findsNWidgets(2));
        expect(find.text(es.reviewGradeGood), findsOneWidget);
      },
    );

    testWidgets(
      'ver la fuente de un distractor lleva al OTRO elemento, no al de la '
      'tarjeta',
      (tester) async {
        final cardId = await seedMultipleChoiceCard();
        final card =
            (await harness.container.read(flashcardRepositoryProvider).getAll())
                .getRight()
                .toNullable()!
                .firstWhere((c) => c.id == cardId);
        await pumpRouted(tester);

        await tester.tap(find.text('Otro texto.'));
        await tester.pumpAndSettle();
        // El orden de las opciones se mezcla (`MultipleChoiceOptions`), así
        // que no se puede asumir cuál ícono es `.first`/`.last`: se busca
        // el de la opción con el texto del distractor, no cualquiera.
        // `InkWell`, no `Row`: un `Row` ancestro también matchea el de la
        // barra de navegación de escritorio, que envuelve TODA la página.
        final distractorTile = find.ancestor(
          of: find.text('Otro texto.'),
          matching: find.byType(InkWell),
        );
        await tester.tap(
          find.descendant(
            of: distractorTile,
            matching: find.byIcon(Icons.menu_book_outlined),
          ),
        );
        await tester.pumpAndSettle();

        final reading = tester.widget<ReadingScreen>(
          find.byType(ReadingScreen),
        );
        expect(reading.itemId, isNot(card.itemId));
      },
    );
  });
}
