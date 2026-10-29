import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_fullscreen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/presentation_fakes.dart';
import '../support/presentation_harness.dart';

/// El visor de la Presentación (F43, punto 5): de a una deslizando, la tira
/// de miniaturas, las notas, la pantalla completa apaisada, la plantilla
/// cambiada sin volver a generar y las ilustraciones que faltan.
void main() {
  final es = AppLocalizationsEs();
  late PresentationHarness h;

  setUp(() async {
    h = await PresentationHarness.create();
    await h.processed('d1', 'Éxodo');
  });

  String counter(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('deck-pager-counter')).first)
      .data!;

  testWidgets('de a una: la tira mueve el visor, deslizar pasa a la '
      'siguiente y las notas de «Del presentador» se ven y se ocultan', (
    tester,
  ) async {
    final c = await h.ready(viewerDeck(), options: presenterOptions);
    await h.openViewer(tester, c);

    expect(find.byKey(const Key('presentation-pager')), findsOneWidget);
    expect(counter(tester), '1 / 5');
    expect(find.byKey(const ValueKey('deck-thumbnail-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('deck-thumbnail-1')));
    await tester.pumpAndSettle();
    expect(counter(tester), '2 / 5');

    await tester.drag(
      find.byKey(const Key('presentation-pager')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(counter(tester), '3 / 5');

    // En «Del presentador» las notas se ven de entrada: las de la que se ve.
    await tester.tap(find.byKey(const Key('deck-pager-next')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-notes')), findsOneWidget);
    expect(find.text('El centro del libro.'), findsOneWidget);
    expect(find.text(es.f43DeckPdfSlideOf(4, 5)), findsOneWidget);

    await tester.tap(find.byKey(const Key('presentation-notes-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-notes')), findsNothing);

    await tester.tap(find.byKey(const Key('presentation-notes-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck-pager-previous')).first);
    await tester.pumpAndSettle();
    expect(find.text(es.f43DeckPdfNoNotes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('de punta a punta con la cola de la app: en la cola, '
      'generándose, lista; se abre en el visor y cambiar la plantilla no '
      'vuelve a pedirle nada a la IA', (tester) async {
    // La cola y la base, con el reloj de verdad.
    final done = (await tester.runAsync(() async {
      final queue = h.container.read(creationQueueProvider);
      final created = (await queue.create(
        const CreationRequest(
          kind: StudyCreationKind.presentation,
          scope: CreationScope.allProcessed(),
          sourceIds: ['d1'],
          options: presenterOptions,
        ),
      )).getOrElse((f) => throw StateError('$f'));
      expect(created.status, CreationStatus.queued);
      for (var i = 0; i < 400; i++) {
        final now = await h.stored(created.id);
        if (!now.status.isPending) return now;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw StateError('sigue pendiente');
    }))!;
    expect(done.status, CreationStatus.ready, reason: '${done.failure}');
    expect(h.writer.requests, hasLength(1));
    expect(h.images.requests, hasLength(3));
    final content = PresentationContent.decode(done.content);
    expect(content.templateHint, DeckTemplateId.aurora);
    expect(content.files, hasLength(3));

    await h.openViewer(tester, done);
    expect(find.byKey(const Key('presentation-pager')), findsOneWidget);
    expect(find.text('Hoy recorremos el Éxodo.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('presentation-design')));
    await tester.pumpAndSettle();
    final compact = find.byKey(const ValueKey('deck-density-compact'));
    await tester.ensureVisible(compact);
    await tester.pumpAndSettle();
    await tester.tap(compact);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final saved = await h.stored(done.id);
    final design = presentationDesignOf(saved.options);
    expect(design.template, DeckTemplateId.aurora);
    expect(design.density, DeckDensity.compact);
    expect(saved.content, done.content);
    expect(h.writer.requests, hasLength(1));
    expect(h.images.requests, hasLength(3));
  });

  testWidgets('en «Detallada» las notas empiezan ocultas', (tester) async {
    final c = await h.ready(viewerDeck(format: DeckFormat.detailed));
    await h.openViewer(tester, c);
    expect(find.byKey(const Key('presentation-notes')), findsNothing);
    expect(find.byKey(const Key('presentation-notes-toggle')), findsOneWidget);
  });

  testWidgets('cambiar la plantilla y la paleta no vuelve a generar: se ve '
      'enseguida y se guarda en las opciones, con el contenido intacto', (
    tester,
  ) async {
    final c = await h.ready(viewerDeck(), options: presenterOptions);
    await h.openViewer(tester, c);

    await tester.tap(find.byKey(const Key('presentation-design')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-design-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('deck-change-template')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-gallery-sheet')), findsOneWidget);
    final neon = find.byKey(const ValueKey('template-neon'));
    await tester.scrollUntilVisible(
      neon,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('presentation-gallery-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(neon);
    await tester.pumpAndSettle();
    await tester.tap(neon);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-gallery-sheet')), findsNothing);
    expect(find.text(es.f43DeckTemplateNeon), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('deck-palette-2')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final saved = await h.stored(c.id);
    final design = presentationDesignOf(saved.options);
    expect(design.template, DeckTemplateId.neon);
    expect(design.paletteIndex, 2);
    expect(saved.content, c.content);
    expect(saved.status, CreationStatus.ready);
    // Nada le pidió algo a la IA.
    expect(h.writer.calls, isEmpty);
    expect(h.images.requests, isEmpty);
  });

  testWidgets('pantalla completa: apaisada y sin barras mientras dura, con '
      'las notas y la misma diapositiva al volver', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final c = await h.ready(viewerDeck(), options: presenterOptions);
    await h.openViewer(tester, c);

    await tester.tap(find.byKey(const Key('presentation-fullscreen-open')));
    await tester.pumpAndSettle();
    expect(find.byType(PresentationFullscreen), findsOneWidget);
    expect(
      calls.where((c) => c.method == 'SystemChrome.setPreferredOrientations'),
      [
        isA<MethodCall>().having((c) => c.arguments, 'orientaciones', [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]),
      ],
    );
    expect(
      calls
          .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
          .map((c) => c.arguments),
      ['SystemUiMode.immersiveSticky'],
    );

    await tester.tap(find.byKey(const Key('presentation-fullscreen-next')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('presentation-fullscreen-counter')),
          )
          .data,
      '2 / 5',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('presentation-fullscreen-notes')))
          .data,
      'Primero, por qué importa.',
    );
    await tester.tap(
      find.byKey(const Key('presentation-fullscreen-notes-toggle')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('presentation-fullscreen-notes')),
      findsNothing,
    );

    // Los controles se esconden solos, y un toque los vuelve a mostrar.
    await tester.pump(const Duration(seconds: 5));
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('presentation-fullscreen-exit')));
    await tester.pumpAndSettle();

    expect(find.byType(PresentationFullscreen), findsNothing);
    expect(
      calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .last
          .arguments,
      isEmpty,
    );
    expect(
      calls
          .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
          .last
          .arguments,
      'SystemUiMode.edgeToEdge',
    );
    expect(counter(tester), '2 / 5');
    // Las notas se apagaron en la pantalla completa: también acá.
    expect(find.byKey(const Key('presentation-notes')), findsNothing);
  });

  testWidgets('las que no salieron dicen por qué; completarlas muestra '
      'primero lo que cuesta, y recién con «Dibujar» se piden', (tester) async {
    final c = await h.ready(
      viewerDeck(),
      options: presenterOptions,
      illustrated: const [0],
      misses: const [
        IllustrationMiss(slide: 2, failure: ImageFailure.noBilling),
        IllustrationMiss(slide: 3, failure: ImageFailure.noBilling),
      ],
    );
    await h.openViewer(tester, c);

    expect(find.byKey(const Key('presentation-misses')), findsOneWidget);
    expect(find.text(es.f43PresMissesTitle(2)), findsOneWidget);
    final reason = es.f43AiReasonNoBilling('Personal');
    expect(find.text(es.f43PresMissesReason(reason)), findsOneWidget);

    await tester.tap(find.byKey(const Key('presentation-misses-complete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('presentation-illustration-sheet')),
      findsOneWidget,
    );
    expect(find.text(es.f43PresCompleteHint(2)), findsOneWidget);
    expect(
      find.text(es.f43AiIllustrateWith(2, 'Nano Banana 2.1 · Personal')),
      findsOneWidget,
    );
    final asked = h.estimates.last;
    expect(asked.images, 2);
    expect(asked.textRequests, 0);
    expect(h.images.requests, isEmpty);

    await tester.tap(find.byKey(const Key('presentation-illustration-draw')));
    await tester.pumpAndSettle();
    expect(h.images.requests.map((r) => r.prompt), [
      'Un desierto',
      'Una montaña',
    ]);
    expect(
      find.byKey(const Key('presentation-illustration-sheet')),
      findsNothing,
    );
    expect(find.text(es.f43PresDrawnSnack(2)), findsOneWidget);

    final content = PresentationContent.decode((await h.stored(c.id)).content);
    expect(content.misses, isEmpty);
    expect(content.missing, isEmpty);
    expect(content.files, hasLength(3));
    expect(find.byKey(const Key('presentation-misses')), findsNothing);
  });

  testWidgets('volver a dibujar la de esta diapositiva reemplaza el archivo; '
      'si no sale, lo dice y la de antes queda', (tester) async {
    final c = await h.ready(
      viewerDeck(),
      options: presenterOptions,
      illustrated: const [0],
    );
    final before = PresentationContent.decode(c.content).files.single;
    await h.openViewer(tester, c);

    expect(find.text(es.f43PresRedrawIllustration), findsOneWidget);
    h.images.outcomes.add(failed(ImageFailure.contentRefused));
    await tester.tap(find.byKey(const Key('presentation-redraw')));
    await tester.pumpAndSettle();
    expect(find.text(es.f43PresRedrawTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('presentation-illustration-draw')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('presentation-illustration-failed')),
      findsOneWidget,
    );
    expect(
      find.text(es.f43PresDrawFailed(es.f43AiReasonContentRefused)),
      findsOneWidget,
    );
    var content = PresentationContent.decode((await h.stored(c.id)).content);
    expect(content.files, {before});
    expect(content.misses, isEmpty);

    await tester.tap(find.byKey(const Key('presentation-illustration-draw')));
    await tester.pumpAndSettle();
    content = PresentationContent.decode((await h.stored(c.id)).content);
    expect(content.files.single, isNot(before));
    expect(h.library.files.deleted, [before]);
    expect(h.images.requests, hasLength(2));
  });

  testWidgets('en una diapositiva sin ilustración pedida no se ofrece '
      'dibujar; en una que la pidió y no la tiene, «Dibujar la ilustración»', (
    tester,
  ) async {
    final c = await h.ready(viewerDeck());
    await h.openViewer(tester, c);
    expect(find.text(es.f43PresDrawIllustration), findsOneWidget);
    expect(find.text(es.f43PresCompleteIllustrations(3)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('deck-thumbnail-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presentation-redraw')), findsNothing);
  });

  group('en cualquier pantalla', () {
    testWidgets('360 dp con la letra al doble, oscuro: nada desborda, ni el '
        'visor ni sus hojas', (tester) async {
      final c = await h.ready(
        viewerDeck(),
        options: presenterOptions,
        misses: const [
          IllustrationMiss(slide: 2, failure: ImageFailure.quotaExhausted),
        ],
      );
      await h.openViewer(
        tester,
        c,
        size: const Size(360, 720),
        theme: AppThemeChoice.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('presentation-notes')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('presentation-viewer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('presentation-design')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(find.byKey(const Key('presentation-design-sheet'))),
      ).pop();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('presentation-misses-complete')),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('presentation-viewer')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('presentation-misses-complete')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('en los nueve temas, claros y oscuros', (tester) async {
      final c = await h.ready(viewerDeck(), options: presenterOptions);
      for (final theme in AppThemeChoice.values) {
        await h.openViewer(tester, c, theme: theme);
        expect(
          find.byKey(const Key('presentation-pager')),
          findsOneWidget,
          reason: theme.name,
        );
        expect(tester.takeException(), isNull, reason: theme.name);
      }
    });
  });
}
