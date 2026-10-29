import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_design_sheet.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_spec.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/widgets/infographic_viewer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

import '../../../../support/pdf_annotations.dart';
import '../../infographic/support/infographic_muestrario.dart';
import '../../presentation/repasar_harness.dart';
import '../support/infographic_kind_fakes.dart';

/// El visor de la infografía (F43, paso 12): la lámina entera con el zoom,
/// el lector de pantalla, cambiar el estilo sin volver a la IA, guardarla
/// como imagen o PDF, y las ilustraciones —el porqué de las que no salieron y
/// rehacerlas con el costo antes—, en los nueve temas, a 360 dp y con la
/// letra al doble.
void main() {
  setUpAll(loadInfographicFonts);

  late RepasarHarness harness;
  late FakeIllustrationService images;

  setUp(() async {
    images = FakeIllustrationService();
    final spec = ProviderContainer().read(infographicKindSpecProvider);
    harness = await RepasarHarness.create(
      specs: [spec],
      overrides: [illustrationServiceProvider.overrideWithValue(images)],
    );
    await harness.processed('exodo', 'Éxodo');
  });

  /// Una infografía lista con [content] y [design].
  Future<StudyCreation> ready({
    InfographicContent? content,
    InfographicDesign design = const InfographicDesign(
      style: InfographicStyleId.editorial,
    ),
    Map<String, Object?> extra = const {},
  }) async {
    final created = (await harness.creations.create(
      CreationRequest(
        kind: StudyCreationKind.infographic,
        scope: const CreationScope.allProcessed(),
        sourceIds: const ['exodo'],
        options: withInfographicDesign(extra, design),
      ),
    )).getOrElse((f) => throw StateError('$f'));
    await harness.creations.complete(
      created.id,
      title: 'Éxodo: liberación y alianza',
      content: (content ?? InfographicContent(sheet: sampleSheet())).encode(),
    );
    return (await harness.creations.find(
      created.id,
    )).getOrElse((f) => throw StateError('$f'))!;
  }

  Future<StudyCreation> stored(String id) async =>
      (await harness.creations.find(
        id,
      )).getOrElse((f) => throw StateError('$f'))!;

  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => harness.openRepasar(
    tester,
    size: size,
    theme: theme,
    textScale: textScale,
    location: '/creations/${creation.id}',
  );

  /// Espera, con el reloj de verdad, a que [done] se cumpla: dibujar fuera de
  /// pantalla y codificar la imagen no corren con el reloj de la prueba.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'no terminó a tiempo');
  }

  double scale(WidgetTester tester) => tester
      .state<InfographicZoomViewState>(find.byType(InfographicZoomView))
      .scale;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

  group('la lámina', () {
    testWidgets('entera, con los botones +, − y «Ajustar»', (tester) async {
      await open(tester, await ready());

      expect(find.byKey(const Key('infographic-viewer-sheet')), findsOneWidget);
      expect(scale(tester), 1);
      expect(enabled(tester, 'infographic-zoom-out'), isFalse);
      expect(enabled(tester, 'infographic-zoom-fit'), isFalse);

      await tester.tap(find.byKey(const Key('infographic-zoom-in')));
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(1.5, 1e-9));
      await tester.tap(find.byKey(const Key('infographic-zoom-in')));
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(2.25, 1e-9));
      expect(enabled(tester, 'infographic-zoom-out'), isTrue);

      await tester.tap(find.byKey(const Key('infographic-zoom-out')));
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(1.5, 1e-9));

      await tester.tap(find.byKey(const Key('infographic-zoom-fit')));
      await tester.pumpAndSettle();
      expect(scale(tester), 1);

      // Hasta el tope, y no más.
      for (var i = 0; i < 8; i++) {
        if (!enabled(tester, 'infographic-zoom-in')) break;
        await tester.tap(find.byKey(const Key('infographic-zoom-in')));
        await tester.pumpAndSettle();
      }
      expect(scale(tester), closeTo(InfographicZoomView.maxScale, 1e-9));
      expect(enabled(tester, 'infographic-zoom-in'), isFalse);
    });

    testWidgets('con pellizco se acerca', (tester) async {
      await open(tester, await ready());
      final center = tester.getCenter(
        find.byKey(const Key('infographic-zoom')),
      );
      final one = await tester.startGesture(center - const Offset(30, 0));
      final two = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 7,
      );
      await tester.pump();
      await one.moveTo(center - const Offset(120, 0));
      await two.moveTo(center + const Offset(120, 0));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
      expect(scale(tester), greaterThan(2));
      expect(enabled(tester, 'infographic-zoom-fit'), isTrue);
    });

    testWidgets('el lector de pantalla lee el título y cada bloque', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, await ready());
      expect(
        find.bySemanticsLabel('Éxodo: liberación y alianza'),
        findsWidgets,
      );
      expect(find.bySemanticsLabel(RegExp('La zarza que arde')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Salida de Egipto')), findsWidgets);
      expect(find.byTooltip('Acercar'), findsOneWidget);
      expect(find.byTooltip('Cambiar el estilo'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('un contenido ilegible lo dice', (tester) async {
      await open(
        tester,
        await ready(
          content: const InfographicContent(sheet: Infographic(title: 'Vacía')),
        ),
      );
      expect(
        find.byKey(const Key('infographic-viewer-unreadable')),
        findsOneWidget,
      );
    });
  });

  group('cambiar el estilo sin volver a la IA (decisión G)', () {
    testWidgets('la galería y la hoja de diseño cambian lo que se ve; al '
        'cerrar se guarda en las opciones y el contenido queda igual', (
      tester,
    ) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(
        find.byKey(const Key('infographic-change-style-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InfographicDesignSheet), findsOneWidget);

      await tester.tap(find.byKey(const Key('infographic-change-style')));
      await tester.pumpAndSettle();
      final gallery = find.byKey(const Key('infographic-style-gallery-sheet'));
      expect(gallery, findsOneWidget);
      final kawaii = find.byKey(const ValueKey('infographic-style-kawaii'));
      await tester.scrollUntilVisible(
        kawaii,
        300,
        scrollable: find
            .descendant(of: gallery, matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(kawaii);
      await tester.pumpAndSettle();
      await tester.tap(kawaii);
      await tester.pumpAndSettle();
      expect(gallery, findsNothing);

      final palette = find.byKey(const ValueKey('infographic-palette-2'));
      await tester.ensureVisible(palette);
      await tester.pumpAndSettle();
      await tester.tap(palette);
      await tester.pumpAndSettle();

      // Atrás, la lámina ya se ve así, antes de cerrar.
      InfographicDesign shown() => tester
          .widget<InfographicView>(
            find.byKey(const Key('infographic-viewer-sheet')),
          )
          .design;
      expect(shown().style, InfographicStyleId.kawaii);
      expect(shown().paletteIndex, 2);

      await tester.tap(
        find.descendant(
          of: find.byType(InfographicDesignSheet),
          matching: find.byType(CreationCloseButton),
        ),
      );
      await tester.pumpAndSettle();

      final saved = await stored(creation.id);
      expect(saved.options[InfographicOptionKeys.style], 'kawaii');
      expect(infographicDesignOf(saved.options).paletteIndex, 2);
      expect(saved.content, creation.content);
      expect(saved.status, CreationStatus.ready);
      // Nada fue a la cola: ni volver a generar ni crear otra.
      expect(harness.queue.calls, isEmpty);
      expect(shown().style, InfographicStyleId.kawaii);
    });
  });

  group('guardarla', () {
    testWidgets('«Guardar como imagen»: un PNG al doble de la lámina', (
      tester,
    ) async {
      await open(
        tester,
        await ready(
          design: const InfographicDesign(
            style: InfographicStyleId.chalkboard,
            orientation: InfographicOrientation.landscape,
          ),
        ),
      );
      final saver = harness.library.fileSaver;
      await tester.tap(find.byKey(const Key('infographic-save-image')));
      await waitFor(tester, () => saver.savedBytes != null);

      final png = saver.savedBytes!;
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(png, 16, 24);
      expect(header.getUint32(0), 1920 * 2);
      expect(header.getUint32(4), 1080 * 2);
      expect(saver.savedFileName, endsWith('.png'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Se guardó'), findsOneWidget);
    });

    testWidgets('«Descargar» del ⋮ pregunta, y el PDF es una página con la '
        'forma de la lámina', (tester) async {
      Pdfrx.pdfiumModulePath = pdfiumPath;
      await tester.runAsync(pdfrxInitialize);
      final creation = await ready(
        design: const InfographicDesign(
          style: InfographicStyleId.swiss,
          orientation: InfographicOrientation.square,
        ),
      );
      await open(tester, creation);
      final saver = harness.library.fileSaver;

      await tester.tap(find.byKey(ValueKey('creation-menu-${creation.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation-action-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('infographic-format-png')), findsOne);
      await tester.tap(find.byKey(const ValueKey('infographic-format-pdf')));
      await waitFor(tester, () => saver.savedBytes != null);

      final pdf = saver.savedBytes!;
      expect(pdf.sublist(0, 5), '%PDF-'.codeUnits);
      expect(saver.savedFileName, endsWith('.pdf'));
      final sizes = (await tester.runAsync(() async {
        final document = await PdfDocument.openData(pdf);
        try {
          return [for (final page in document.pages) (page.width, page.height)];
        } finally {
          await document.dispose();
        }
      }))!;
      expect(sizes, hasLength(1));
      expect(sizes.single.$1, closeTo(sizes.single.$2, 0.5));
    }, skip: pdfiumPath == null);
  });

  group('las ilustraciones', () {
    final failedContent = InfographicContent(
      sheet: sampleSheet(),
      failures: const {
        InfographicSlot.headerId: ImageFailure.noBilling,
        'block-1': ImageFailure.noBilling,
      },
      accountLabel: 'Personal',
    );
    const clay = InfographicDesign(style: InfographicStyleId.clay);
    const asked = {
      CreationOptionValues.illustrations: true,
      CreationOptionKeys.imageAccountId: 'g',
    };

    testWidgets('el aviso dice cuántas no salieron y por qué; su lugar se ve '
        'dibujado', (tester) async {
      await open(
        tester,
        await ready(content: failedContent, design: clay, extra: asked),
      );
      final notice = find.byKey(const Key('infographic-illustration-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.textContaining('no tiene facturación activa'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notice, matching: find.textContaining('2 ilustr')),
        findsOneWidget,
      );
    });

    testWidgets('sin ilustraciones pedidas y con un estilo dibujado, no hay '
        'aviso ni ✨', (tester) async {
      await open(
        tester,
        await ready(
          content: InfographicContent(sheet: sampleSheet(illustrations: false)),
        ),
      );
      expect(
        find.byKey(const Key('infographic-illustration-notice')),
        findsNothing,
      );
      expect(find.byKey(const Key('infographic-illustrations')), findsNothing);
    });

    testWidgets('pasar a un estilo ilustrado deja sus lugares dibujados, con '
        '«Completar ilustraciones»', (tester) async {
      await open(
        tester,
        await ready(
          content: InfographicContent(sheet: sampleSheet()),
          design: clay,
        ),
      );
      final notice = find.byKey(const Key('infographic-illustration-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.textContaining('Faltan 5 ilustraciones'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('infographic-illustrations')),
        findsOneWidget,
      );
    });

    testWidgets('rehacer una: primero el costo, solo de imágenes; después se '
        'dibuja y queda guardada', (tester) async {
      RepasarHarness.estimate = (request) =>
          fakeEstimate(request, imageAccounts: [geminiImages()]);
      final creation = await ready(
        content: failedContent,
        design: clay,
        extra: asked,
      );
      await open(tester, creation);

      await tester.tap(
        find.byKey(const Key('infographic-complete-illustrations')),
      );
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('infographic-illustrations-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('infographic-slot-block-1')),
          matching: find.textContaining('no tiene facturación activa'),
        ),
        findsOneWidget,
      );

      final draw = find.byKey(const ValueKey('infographic-slot-draw-block-1'));
      await tester.ensureVisible(draw);
      await tester.pumpAndSettle();
      await tester.tap(draw);
      await tester.pumpAndSettle();

      // El costo, antes de dibujar nada.
      expect(images.calls, isEmpty);
      expect(find.byType(AiCapabilityCard), findsOneWidget);
      expect(find.byKey(const Key('ai-capability-text')), findsNothing);
      expect(find.byKey(const Key('ai-capability-images')), findsOneWidget);
      final request = harness.estimates.last;
      expect(request.images, 1);
      expect(request.textRequests, 0);
      expect(request.imageAccountId, 'g');

      final confirm = find.byKey(
        const Key('infographic-illustrations-confirm'),
      );
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await waitFor(
        tester,
        () => find
            .byKey(const Key('infographic-illustrations-result'))
            .evaluate()
            .isNotEmpty,
      );

      expect(images.calls, hasLength(1));
      expect(images.calls.single.account?.id, 'g');
      final saved = InfographicContent.decode(
        (await stored(creation.id)).content,
      );
      final reference = saved.sheet.blocks[1].illustrationRef;
      expect(reference, startsWith('originales/${creation.id}/ilustraciones/'));
      expect(harness.library.files.paths, contains(reference));
      expect(saved.failures.keys, [InfographicSlot.headerId]);
      expect(find.text('Hechas: 1 · No salieron: 0'), findsOneWidget);
    });

    testWidgets('«Completar las que faltan» pide todas las que faltan', (
      tester,
    ) async {
      RepasarHarness.estimate = (request) =>
          fakeEstimate(request, imageAccounts: [geminiImages()]);
      await open(
        tester,
        await ready(content: failedContent, design: clay, extra: asked),
      );
      await tester.tap(find.byKey(const Key('infographic-illustrations')));
      await tester.pumpAndSettle();
      final complete = find.byKey(const Key('infographic-complete-missing'));
      await tester.ensureVisible(complete);
      await tester.pumpAndSettle();
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(harness.estimates.last.images, 5);
    });
  });

  group('en cualquier teléfono', () {
    testWidgets('los nueve temas, a 360 dp y con la letra al doble, sin '
        'desbordes: el visor y la hoja de ilustraciones', (tester) async {
      final creation = await ready(
        content: InfographicContent(
          sheet: sampleSheet(),
          failures: const {'block-1': ImageFailure.quotaExhausted},
          accountLabel: 'Una cuenta con un nombre bastante largo',
        ),
        design: const InfographicDesign(style: InfographicStyleId.kawaii),
        extra: const {CreationOptionValues.illustrations: true},
      );
      for (final theme in AppThemeChoice.values) {
        await open(
          tester,
          creation,
          size: const Size(360, 760),
          theme: theme,
          textScale: 2,
        );
        expect(tester.takeException(), isNull, reason: theme.name);
        expect(
          find.byKey(const Key('infographic-illustration-notice')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('infographic-zoom-in')), findsOneWidget);
        await tester.tap(find.byKey(const Key('infographic-illustrations')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: theme.name);
        final sheet = find.byKey(const Key('infographic-illustrations-sheet'));
        expect(sheet, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: sheet,
            matching: find.byType(CreationCloseButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
      }
    });
  });
}
