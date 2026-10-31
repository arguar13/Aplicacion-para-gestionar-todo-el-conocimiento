import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_usage_bar.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_grid.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'repasar_harness.dart';

/// Las tarjetas de crear y la hoja de personalizar de Repasar (F43, paso 6):
/// la grilla, la hoja común con las opciones de cada tipo, «Uso de IA» y la
/// tarjeta «Con tu IA actual», y lo que se le pide a la cola.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  setUp(() async {
    harness = await RepasarHarness.create();
    await harness.processed('p-1', 'Éxodo — Comentario');
    await harness.processed('p-2', 'Génesis');
  });

  Future<void> openSheet(WidgetTester tester, StudyCreationKind kind) async {
    final tile = find.byKey(ValueKey('creation-kind-${kind.storageKey}'));
    // Con la letra grande la grilla puede quedar fuera de lo armado: se baja
    // hasta ella.
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

  CreationRequest lastRequest() => harness.queue.requests.last;

  group('la grilla', () {
    testWidgets('las once tarjetas, con las tres de extraer juntas en la '
        'primera fila', (tester) async {
      await harness.openRepasar(tester);

      for (final kind in StudyCreationKind.values) {
        expect(
          find.byKey(ValueKey('creation-kind-${kind.storageKey}')),
          findsOneWidget,
        );
      }
      double top(StudyCreationKind kind) => tester
          .getTopLeft(find.byKey(ValueKey('creation-kind-${kind.storageKey}')))
          .dy;
      expect(top(StudyCreationKind.summary), top(StudyCreationKind.fullText));
      expect(top(StudyCreationKind.synthesis), top(StudyCreationKind.fullText));
      // De a dos en el teléfono, y Tabla de datos en la última fila, con el
      // Podcast (F47).
      expect(
        top(StudyCreationKind.mindMap),
        top(StudyCreationKind.presentation),
      );
      expect(
        top(StudyCreationKind.presentation),
        greaterThan(top(StudyCreationKind.fullText)),
      );
      expect(
        top(StudyCreationKind.dataTable),
        greaterThan(top(StudyCreationKind.infographic)),
      );
      expect(find.text(es.f43StudioTileReports), findsOneWidget);
    });

    test('de a dos en un teléfono, de a tres o cuatro en ancho, menos con '
        'letra grande', () {
      expect(CreationKindGrid.columnsFor(388, 150, 2), 2);
      expect(CreationKindGrid.columnsFor(700, 150, 3), 3);
      expect(CreationKindGrid.columnsFor(1000, 150, 4), 4);
      // Con letra al doble, cada una pide 300: en un teléfono, una por fila.
      expect(CreationKindGrid.columnsFor(328, 300, 2), 1);
      expect(CreationKindGrid.columnsFor(328, 192, 3), 1);
      expect(CreationKindGrid.columnsFor(328, 96, 3), 3);
    });

    testWidgets('en una pantalla ancha, cuatro por fila', (tester) async {
      await harness.openRepasar(tester, size: const Size(1300, 1400));

      double top(StudyCreationKind kind) => tester
          .getTopLeft(find.byKey(ValueKey('creation-kind-${kind.storageKey}')))
          .dy;
      expect(
        top(StudyCreationKind.flashcards),
        top(StudyCreationKind.presentation),
      );
      expect(
        top(StudyCreationKind.quiz),
        greaterThan(top(StudyCreationKind.presentation)),
      );
    });

    testWidgets('tocar una abre su hoja, con su título y la ✕ redonda', (
      tester,
    ) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.presentation);

      expect(find.text(es.f43StudioSheetPresentation), findsOneWidget);
      await tester.tap(find.byKey(const Key('creation-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('creation-sheet')), findsNothing);
    });
  });

  group('la hoja de una de la IA', () {
    testWidgets('«Generar ahora» encola con el recorte, sus fuentes, las '
        'opciones de fábrica y español', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.presentation);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('creation-sources-count')))
            .data,
        es.f43StudioSources(2),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      final request = lastRequest();
      expect(request.kind, StudyCreationKind.presentation);
      expect(request.scope, const CreationScope.allProcessed());
      expect(request.sourceIds.toSet(), {'p-1', 'p-2'});
      expect(request.runNow, isTrue);
      expect(request.languageCode, 'es');
      expect(request.options, {
        CreationOptionValues.format: CreationOptionValues.detailed,
        CreationOptionValues.template: CreationOptionValues.auto,
        CreationOptionValues.length: CreationOptionValues.standard,
        CreationOptionValues.illustrations: false,
      });
      expect(find.byKey(const Key('creation-sheet')), findsNothing);
      expect(find.text(es.f43StudioQueuedSnack), findsOneWidget);
    });

    testWidgets('«Generar más tarde» va a la cola de fondo', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.mindMap);
      await tapInSheet(
        tester,
        find.byKey(const Key('creation-generate-later')),
      );

      expect(lastRequest().runNow, isFalse);
      expect(find.text(es.f43StudioLaterSnack), findsOneWidget);
    });

    testWidgets('los segmentados, el idioma y la descripción llegan a lo '
        'pedido, y lo elegido se recuerda la próxima vez', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.presentation);

      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-length-short')),
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-format-presenter')),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-language')));
      await tester.tap(find.byKey(const ValueKey('picker-item-en')).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('creation-description')),
        '  Para principiantes  ',
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      var request = lastRequest();
      expect(request.options[CreationOptionValues.length], 'short');
      expect(request.options[CreationOptionValues.format], 'presenter');
      expect(
        request.options[CreationOptionKeys.description],
        'Para principiantes',
      );
      expect(request.languageCode, 'en');

      // La próxima vez abre así; la descripción era para esa.
      await openSheet(tester, StudyCreationKind.presentation);
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      request = lastRequest();
      expect(request.options[CreationOptionValues.length], 'short');
      expect(request.options[CreationOptionValues.format], 'presenter');
      expect(
        request.options.containsKey(CreationOptionKeys.description),
        isFalse,
      );
      expect(request.languageCode, 'en');
    });

    testWidgets('destildar una fuente la deja afuera; sin ninguna no se '
        'puede generar', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.dataTable);

      await tapInSheet(
        tester,
        find.byKey(const Key('creation-sources-toggle')),
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-source-option-p-2')),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('creation-sources-count')))
            .data,
        '${es.f43StudioSources(1)} (${es.f43StudioSourcesOf(1, 2)})',
      );

      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-source-option-p-1')),
      );
      expect(find.text(es.f43StudioSourcesNoneChosen), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('creation-generate-now')),
            )
            .onPressed,
        isNull,
      );

      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-source-option-p-1')),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(lastRequest().sourceIds, ['p-1']);
    });

    testWidgets('un recorte sin documentos procesados lo dice y no genera', (
      tester,
    ) async {
      harness.container.read(repasarScopeProvider.notifier).state =
          const CreationScope.notebook('vacío');
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.quiz);

      expect(find.byKey(const Key('creation-sources-empty')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('creation-generate-later')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('el tema sugerido se toca y va como tema', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.flashcards);

      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-suggested-Moisés y Faraón')),
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-count-more')),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      final options = lastRequest().options;
      expect(options[CreationOptionKeys.topic], 'Moisés y Faraón');
      expect(options[CreationOptionValues.count], 'more');
      expect(options[CreationOptionValues.difficulty], 'medium');
      expect(options[CreationOptionValues.images], false);
    });

    testWidgets('los tipos de pregunta: al menos uno, en su orden', (
      tester,
    ) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.quiz);

      // El único elegido no se puede sacar.
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-questionTypes-single')),
      );
      await tapInSheet(
        tester,
        find.byKey(
          const ValueKey('creation-option-questionTypes-short_answer'),
        ),
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-questionTypes-fill_blank')),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      expect(lastRequest().options[CreationOptionValues.questionTypes], [
        'single',
        'fill_blank',
        'short_answer',
      ]);
    });

    testWidgets('el informe con plantilla propia muestra su campo y la '
        'guarda', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.report);

      expect(
        find.byKey(const ValueKey('creation-option-customTemplate')),
        findsNothing,
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-template-custom')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('creation-option-customTemplate')),
        'Un acta',
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      expect(lastRequest().options[CreationOptionValues.template], 'custom');
      expect(
        lastRequest().options[CreationOptionValues.customTemplate],
        'Un acta',
      );
    });
  });

  group('la barra de abajo', () {
    bool scrolls(WidgetTester tester) => find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byKey(const Key('creation-generate-now')),
        )
        .evaluate()
        .isNotEmpty;

    testWidgets('queda fija con la letra de siempre', (tester) async {
      await harness.openRepasar(tester, size: const Size(360, 800));
      await openSheet(tester, StudyCreationKind.presentation);

      expect(find.byKey(const Key('creation-generate-now')), findsOneWidget);
      expect(scrolls(tester), isFalse);
    });

    testWidgets('con la letra al doble en un teléfono bajo pasa al final de '
        'la lista, sin tapar las opciones', (tester) async {
      await harness.openRepasar(
        tester,
        size: const Size(360, 800),
        textScale: 2,
      );
      await openSheet(tester, StudyCreationKind.presentation);

      expect(scrolls(tester), isTrue);
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-illustrations')),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('creation-option-illustrations')),
            )
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('«Uso de IA» y «Con tu IA actual»', () {
    testWidgets('la estimación sale del material de las fuentes elegidas y '
        'de lo que escribe ese tipo', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.presentation);

      expect(find.byType(AiUsageBar), findsOneWidget);
      expect(find.byType(AiCapabilityCard), findsNothing);
      final request = harness.estimates.last;
      // Dos fuentes de 9.000 caracteres (3.000 tokens cada una) y la
      // instrucción.
      expect(
        request.inputTokens,
        estimateCreationTokens(18000) + kCreationInstructionTokens,
      );
      expect(request.expectedOutputTokens, 3500);
      expect(request.textRequests, 1);
      expect(request.images, 0);
    });

    testWidgets('con ilustraciones aparece la tarjeta; «Seguir sin '
        'ilustraciones» las apaga', (tester) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.infographic);

      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-illustrations')),
      );
      expect(find.byType(AiCapabilityCard), findsOneWidget);
      expect(harness.estimates.last.images, 5);

      await tapInSheet(tester, find.byKey(const Key('ai-alternative-1')));

      expect(find.byType(AiCapabilityCard), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('creation-option-illustrations')),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('«Usar otra cuenta» la elige para las ilustraciones y va en '
        'lo pedido', (tester) async {
      RepasarHarness.estimate = (request) => fakeEstimate(
        request,
        imageAccounts: [
          geminiImages(
            state: ImageCapabilityState.cannot,
            reason: ImageFailure.noBilling,
          ),
          geminiImages(id: 'w'),
        ],
      );
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.presentation);
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-illustrations')),
      );

      await tapInSheet(tester, find.byKey(const Key('ai-alternative-2')));
      expect(harness.estimates.last.imageAccountId, 'w');

      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(lastRequest().options[CreationOptionKeys.imageAccountId], 'w');
      expect(lastRequest().options[CreationOptionValues.illustrations], true);
    });

    testWidgets('si la IA elegida no puede escribir, lo dice y solo ofrece '
        '«más tarde»', (tester) async {
      RepasarHarness.estimate = (request) =>
          fakeEstimate(request, canWrite: false);
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.mindMap);

      expect(find.byType(AiCapabilityCard), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('creation-generate-now')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('creation-generate-later')),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  group('las de extraer', () {
    testWidgets('no le piden nada a la IA: solo «Crear», y queda lista', (
      tester,
    ) async {
      await harness.openRepasar(tester);
      await openSheet(tester, StudyCreationKind.summary);

      expect(find.byType(AiUsageBar), findsNothing);
      expect(find.byKey(const Key('creation-generate-now')), findsNothing);
      expect(find.byKey(const Key('creation-generate-later')), findsNothing);
      expect(find.text(es.f43StudioExtractIntro), findsOneWidget);
      // Ninguna de las dos tiene resumen todavía: se pide al crear.
      expect(find.text(es.f43StudioExtractMissing(2)), findsOneWidget);

      await tapInSheet(tester, find.byKey(const Key('creation-create')));

      expect(lastRequest().kind, StudyCreationKind.summary);
      expect(find.text(es.f43StudioCreatedSnack), findsOneWidget);
      final created = (await harness.creations.pending()).getOrElse(
        (f) => fail('$f'),
      );
      expect(created, isEmpty);
    });
  });

  group('volver a generar con otras opciones', () {
    testWidgets('abre con lo de esa creación y la vuelve a la cola en su '
        'lugar', (tester) async {
      final creation = await harness.creation(
        StudyCreationKind.flashcards,
        sources: ['p-2'],
      );
      await harness.creations.requeue(
        creation.id,
        options: const {CreationOptionValues.count: 'fewer'},
      );
      await harness.creations.complete(
        creation.id,
        title: 'Mazo de Génesis',
        content: '{}',
      );
      await harness.openRepasar(tester);

      await tester.longPress(
        find.byKey(ValueKey('creation-tile-${creation.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('creation-action-regenerate')),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.f43StudioSheetFlashcards), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('creation-sources-count')))
            .data,
        '${es.f43StudioSources(1)} (${es.f43StudioSourcesOf(1, 2)})',
      );
      await tapInSheet(
        tester,
        find.byKey(const ValueKey('creation-option-difficulty-hard')),
      );
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

      final call = harness.queue.calls.last;
      expect(call.action, 'regenerate');
      expect(call.id, creation.id);
      final detail =
          call.detail!
              as ({
                bool? runNow,
                Map<String, Object?>? options,
                List<String>? sourceIds,
                String? languageCode,
              });
      expect(detail.sourceIds, ['p-2']);
      expect(detail.options![CreationOptionValues.count], 'fewer');
      expect(detail.options![CreationOptionValues.difficulty], 'hard');
      expect(detail.runNow, isTrue);
    });
  });

  group('el registro de tipos', () {
    test(
      'las de fábrica dicen lo que escribe y cuántas ilustraciones pide',
      () {
        final presentation = defaultCreationKindSpec(
          StudyCreationKind.presentation,
        );
        final options = presentation.withDefaults(const {});
        expect(presentation.outputTokensFor(options), 3500);
        expect(presentation.illustrationsFor(options), 0);
        final illustrated = {
          ...options,
          CreationOptionValues.illustrations: true,
          CreationOptionValues.length: 'short',
        };
        expect(presentation.illustrationsFor(illustrated), 4);
        expect(presentation.offersIllustrations, isTrue);
        expect(
          defaultCreationKindSpec(
            StudyCreationKind.summary,
          ).outputTokensFor(const {}),
          0,
        );
        // Lo guardado que ya no vale vuelve al de fábrica.
        expect(
          presentation.withDefaults(const {
            CreationOptionValues.length: 'eterna',
          })[CreationOptionValues.length],
          CreationOptionValues.standard,
        );
      },
    );
  });
}
