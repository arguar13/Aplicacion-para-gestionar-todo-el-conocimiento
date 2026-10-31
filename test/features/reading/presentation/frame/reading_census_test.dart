import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/presentation/providers/marked_download_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/transcript_follow_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_section_edit_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_cut_screen.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';
import '../../../creations/extract/extract_harness.dart';
import '../../../creations/report/support/report_harness.dart';
import '../../../creations/report/support/sample_reports.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// **El censo de funciones** del marco de lectura (F47, paso 1): cada función
/// de los cuatro lectores de antes —«Lo que hay hoy (y no se pierde)» del
/// plan— con dónde quedó en el lector nuevo, y una prueba que llega a ella.
///
/// Las pruebas van por familia de documento; cada una anota lo que alcanzó
/// con `reach`, y al final se comprueba que **no quedó ninguna sin
/// alcanzar**, salvo las que todavía no existen en la app (con el paso que
/// las trae).
void main() {
  final es = AppLocalizationsEs();

  /// La función, y dónde quedó.
  const census = <String, String>{
    // El texto.
    'Las palabras clave en rosa': 'el cuerpo del texto extraído',
    'El resumen y la síntesis marcados con su color y su punto, ocultables':
        'las fichas de la fila de IA del original',
    'La línea que se lee, siguiendo a la voz':
        'el cuerpo, con el color de «Resaltado de lectura»',
    'La página que se ve': 'el paso de páginas del libro, abajo del cuerpo',
    'El texto limpio, sin direcciones ni ![](…)': 'el texto extraído',
    // Con lo que se selecciona.
    'Copiar, Escuchar, Nota y resaltar a mano': 'la barrita de la selección',
    '«A Procesado», mientras se corta del original':
        'la pantalla de cortes del triaje, con el mismo visor',
    '«A la línea de tiempo»': 'la barrita de la selección',
    'Explicar en el chat': 'Preguntar a la IA, en la fila de IA',
    // Las tres fichas.
    'Resumir · Sintetizar · Palabras clave, con su estado y su avance':
        'la fila de IA',
    // Ver la fuente.
    '«Ver N fuentes»': 'Contenido',
    'Las fichas de cada fuente': 'Contenido',
    'Desde una tarjeta, ir al pasaje': 'el marco de la fuente, en el pasaje',
    // Editar.
    'Editar lo procesado': '⋮ «Editar el texto»',
    'Las notas en el texto': 'F45, paso 8 (todavía no existen)',
    // Bajar.
    '«Descargar con lo marcado»': '⋮ del original de Procesado',
    'Exportar lo creado': '⋮ «Descargar» y «Compartir»',
    'Imprimir': 'el PDF de lo creado, en ⋮ «Descargar»',
    // El original.
    'El PDF con su maquetación': 'el cuerpo del original',
    'El libro paginado': 'el cuerpo del original',
    'La página web en vista móvil': 'el cuerpo del original',
    '«Ampliar»': 'la vista previa abre el marco',
    // Leer en voz alta.
    '«Leer: Todo · Resumen · Síntesis · Palabras clave»': 'Contenido',
    'En un audio o un video, empezar por lo estudiado':
        'el marco de la transcripción',
    'La velocidad y la voz': 'el lugar del reproductor, abajo',
    'Seguir sonando al cambiar de pantalla': 'el lector flotante, al salir',
    // Lo de cada lector de antes.
    '🎧 de «Lo creado»': '«Escuchar», en el lugar del reproductor',
    'A− A+ y la letra': 'Apariencia',
    'El tema de lectura (claro, oscuro, sepia)': 'Apariencia',
    'El lector de pantalla': 'cada botón con su nombre',
  };

  /// Lo que todavía no existe, con quién lo trae.
  const pending = {'Las notas en el texto': 'F45, paso 8'};

  final reached = <String>{};
  void reach(String name) {
    expect(census, contains(name), reason: 'no está en el censo: $name');
    reached.add(name);
  }

  tearDownAll(() {
    final missing = {
      for (final name in census.keys)
        if (!reached.contains(name) && !pending.containsKey(name)) name,
    };
    expect(missing, isEmpty, reason: 'funciones sin alcanzar en el marco');
    expect(reached.intersection(pending.keys.toSet()), isEmpty);
  });

  test('el censo tiene las 30 funciones de «Lo que hay hoy»', () {
    expect(census, hasLength(30));
  });

  const text =
      'La república romana cayó. César cruzó el Rubicón. '
      'Su [concilio](https://ejemplo.org/concilio) votó. '
      '![](https://ejemplo.org/foto.png)';

  group('el original de Procesado: un libro', () {
    late LibraryHarness harness;

    setUp(() async {
      harness = await LibraryHarness.create(
        extraOverrides: [
          markedDownloadFormatProvider.overrideWith(
            (ref, request) async => MarkedDocumentFormat.docx,
          ),
        ],
      );
    });

    Future<String> processBook() async {
      await harness.saveTextSource(
        'roma',
        title: 'Roma',
        text: text,
        kind: SourceKind.document,
        originalName: 'notas.txt',
        originalBytes: text.codeUnits,
      );
      await harness.addSummarySentence('roma', text, 'César cruzó el Rubicón.');
      await harness.addSummarySentence(
        'roma',
        text,
        'república',
        kind: StudyMarkKind.keyword,
      );
      return harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
        ProcessedSection.keywords: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      }, original: const OriginalEdit(ProcessedChange.add));
    }

    testWidgets('«Ampliar» lo abre en el marco: el libro paginado, las '
        'fichas en la fila de IA, Contenido, la barrita, ⋮ y la voz', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final id = await processBook();
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('embedded-viewer-read-as-book')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);
      reach('«Ampliar»');
      expect(
        find.descendant(
          of: find.byKey(const Key('reading-frame')),
          matching: find.byType(DocumentReaderView),
        ),
        findsOneWidget,
      );
      reach('El libro paginado');
      // Sin el botón flotante: el marco trae su lugar.
      expect(harness.container.read(readAloudDockProvider), isNotEmpty);
      expect(find.byKey(const Key('read-aloud-button')), findsNothing);
      for (final label in [
        es.f47P1FrameContents,
        es.f47P1FrameAi,
        es.f47P1FrameAppearance,
        es.f47P1FrameMore,
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
        expect(tester.getSemantics(find.byTooltip(label)).tooltip, label);
      }
      reach('El lector de pantalla');

      // Las fichas: con su estado; tocar la del resumen lo oculta.
      Text state(StudyMarkKind kind) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('reading-ai-row')),
          matching: find.byKey(Key('original-study-state-${kind.name}')),
        ),
      );
      expect(state(StudyMarkKind.summary).data, es.f43OrigStateDone('summary'));
      expect(state(StudyMarkKind.synthesis).data, es.f43OrigStateNone);
      reach('Resumir · Sintetizar · Palabras clave, con su estado y su avance');
      await tester.tap(find.byKey(const Key('original-study-summary')));
      await tester.pumpAndSettle();
      expect(
        state(StudyMarkKind.summary).data,
        es.f43OrigStateHidden('summary'),
      );
      reach(
        'El resumen y la síntesis marcados con su color y su punto, '
        'ocultables',
      );
      await tester.tap(find.byKey(const Key('original-study-summary')));
      await tester.pumpAndSettle();

      // ⋮: «Descargar con lo marcado» y, en rojo, la copia.
      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('processed-original-download-marked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('processed-original-delete-copy')),
        findsOneWidget,
      );
      reach('«Descargar con lo marcado»');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Contenido: «Leer: Resumen», y el reproductor con su voz.
      await tester.tap(find.byKey(const Key('reading-frame-contents')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reading-read-summary')));
      await tester.pumpAndSettle();
      final reading = harness.container.read(readAloudControllerProvider);
      expect(reading.scope, ReadScope.summary);
      expect(reading.panel, ReadAloudPanel.expanded);
      reach('«Leer: Todo · Resumen · Síntesis · Palabras clave»');
      expect(find.byKey(const Key('read-aloud-speed')), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-voice')), findsOneWidget);
      reach('La velocidad y la voz');

      // Se sale del marco: sigue sonando.
      await tester.tap(find.byKey(const Key('reading-frame-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-frame')), findsNothing);
      expect(
        harness.container.read(readAloudControllerProvider).document,
        isNotNull,
      );
      expect(harness.container.read(readAloudDockProvider), isEmpty);
      reach('Seguir sonando al cambiar de pantalla');
      semantics.dispose();
    });

    testWidgets('el texto, el resumen y la síntesis se leen en el mismo marco: '
        'limpio, con el rosa, las fichas, Apariencia, ⋮ y «Escuchar»', (
      tester,
    ) async {
      final id = await processBook();
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('processed-read-text')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('processed-reader-full_text')),
        findsOneWidget,
      );
      expect(find.textContaining('TEXTO · '), findsOneWidget);

      // «Resumir», hecho: abre el resumen en el mismo marco.
      await tester.ensureVisible(
        find.byKey(const Key('extract-study-summary')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extract-study-summary')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('processed-reader-summary')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('extract-study-summary')),
                matching: find.byKey(const Key('original-study-state-summary')),
              ),
            )
            .data,
        es.f47P1ChipReading,
      );
      await tester.tap(find.byKey(const Key('reading-frame-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('extract-study-keyword')), findsOneWidget);
      // La letra, con Apariencia.
      await tester.tap(find.byKey(const Key('reading-frame-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reading-font-nunito')));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(readingAppearanceProvider).font,
        ReadingFont.nunito,
      );
      reach('A− A+ y la letra');
      final lilac = find.byKey(const Key('reading-highlight-lilac'));
      await tester.ensureVisible(lilac);
      await tester.tap(lilac);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Escuchar: la línea que suena, con el color elegido.
      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();
      expect([
        for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
          ...(() {
            final out = <String>[];
            rich.text.visitChildren((span) {
              if (span is TextSpan &&
                  span.style?.backgroundColor == ReadingHighlight.lilac.color &&
                  (span.text ?? '').isNotEmpty) {
                out.add(span.text!);
              }
              return true;
            });
            return out;
          })(),
      ], isNotEmpty);
      reach('La línea que se lee, siguiendo a la voz');
      await tester.tap(find.byKey(const Key('extract-player-close')));
      await tester.pumpAndSettle();

      // ⋮: editar lo procesado.
      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('processed-reader-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(ProcessedSectionEditScreen), findsOneWidget);
      reach('Editar lo procesado');
    });

    testWidgets('el original de la fuente, en la Biblioteca: el mismo marco, '
        'y la barrita de la selección con todo lo de resaltar a mano', (
      tester,
    ) async {
      await harness.saveTextSource(
        'roma',
        title: 'Roma',
        text: text,
        kind: SourceKind.document,
        originalName: 'notas.txt',
        originalBytes: text.codeUnits,
      );
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));
      await tester.tap(find.byKey(const Key('embedded-viewer-read-as-book')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable
        ..userUpdateTextEditingValue(
          editable.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 3, extentOffset: 11),
          ),
          SelectionChangedCause.tap,
        )
        ..showToolbar();
      await tester.pumpAndSettle();
      for (final tip in [
        es.highlightCopy,
        es.highlightListen,
        es.highlightAddNote,
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.byKey(const Key('highlight-color-violet')), findsOneWidget);
      reach('Copiar, Escuchar, Nota y resaltar a mano');
      expect(find.byTooltip(es.highlightAddToTimeline), findsOneWidget);
      reach('«A la línea de tiempo»');
    });

    testWidgets('las palabras clave, en rosa, sobre el texto extraído', (
      tester,
    ) async {
      final id = await processBook();
      await pumpApp(tester, harness);
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.extractReading(StudyCreationKind.fullText, [id]),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('extract-study-keyword')),
                matching: find.byKey(const Key('original-study-state-keyword')),
              ),
            )
            .data,
        es.f43OrigStateDone('keyword'),
      );
      final pink = <String>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.backgroundColor != null &&
              span.style?.fontWeight == FontWeight.bold) {
            pink.add(span.text ?? '');
          }
          return true;
        });
      }
      expect(pink.join(), contains('república'));
      reach('Las palabras clave en rosa');
    });

    testWidgets('el texto de una página web, limpio: los enlaces como '
        'palabras, sin su dirección, y sin las imágenes (F45, mejora 12)', (
      tester,
    ) async {
      await harness.saveTextSource('wiki', title: 'Concilio', text: text);
      final id = await harness.processTextAndNotes('wiki');
      await pumpApp(tester, harness);
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.extractReading(StudyCreationKind.fullText, [id]),
      );
      final body = [
        for (final rich in tester.widgetList<RichText>(
          find.descendant(
            of: find.byKey(const Key('extract-viewer-list')),
            matching: find.byType(RichText),
          ),
        ))
          rich.text.toPlainText(),
      ].join('\n');
      expect(body, contains('Su concilio votó.'));
      expect(body, isNot(contains('https://')));
      expect(body, isNot(contains('![')));
      reach('El texto limpio, sin direcciones ni ![](…)');
    });

    testWidgets('desde una tarjeta, el pasaje se abre en el marco de la '
        'fuente', (tester) async {
      await harness.saveTextSource('roma', title: 'Roma', text: text);
      await pumpApp(tester, harness);
      final start = text.indexOf('César');
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.reading('roma', start: start, end: start + 5),
      );
      expect(find.byKey(const Key('reading-screen')), findsOneWidget);
      expect(
        find.textContaining('César cruzó', findRichText: true),
        findsWidgets,
      );
      reach('Desde una tarjeta, ir al pasaje');
    });

    testWidgets('«A Procesado», mientras se corta del original: la pantalla '
        'de cortes del triaje, con el mismo visor', (tester) async {
      await harness.saveTextSource(
        'roma',
        title: 'Roma',
        text: text,
        kind: SourceKind.document,
      );
      await tester.pumpWidget(
        harness.wrap(
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => openProcessedCutScreen(context, 'roma'),
                child: const Text('Cortar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cortar'));
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable
        ..userUpdateTextEditingValue(
          editable.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 3, extentOffset: 11),
          ),
          SelectionChangedCause.tap,
        )
        ..showToolbar();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('highlight-to-processed')), findsOneWidget);
      reach('«A Procesado», mientras se corta del original');
    });

    testWidgets('un audio con su transcripción: el marco empieza a leer por '
        'lo estudiado, que lo demás ya suena en su audio', (tester) async {
      await harness.saveTextSource(
        'voz',
        title: 'Una charla',
        text: text,
        kind: SourceKind.audio,
      );
      await harness.addSummarySentence('voz', text, 'César cruzó el Rubicón.');
      await tester.pumpWidget(
        harness.wrap(const TranscriptFollowScreen(itemId: 'voz')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);
      final offered = harness.container.read(currentReadableProvider)!;
      expect(offered.ownAudio, isTrue);
      expect(offered.defaultScope, ReadScope.summary);
      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(readAloudControllerProvider).scope,
        ReadScope.summary,
      );
      reach('En un audio o un video, empezar por lo estudiado');
    });

    testWidgets('el libro dice en qué página se está', (tester) async {
      await tester.pumpWidget(
        harness.wrap(
          const DocumentReaderScreen(
            title: 'Un libro',
            content: 'Una página.\n\n---\n\nOtra página.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);
      expect(find.text(es.documentReaderPageOf(1, 2)), findsOneWidget);
      reach('La página que se ve');
    });
  });

  group('lo creado', () {
    late ExtractHarness h;

    setUp(() async => h = await ExtractHarness.create());

    testWidgets('«Ver N fuentes» y sus fichas en Contenido, Exportar en ⋮ y '
        '🎧 en «Escuchar»; Preguntar a la IA en la fila', (tester) async {
      final id = await h.document(
        'roma',
        title: 'Roma',
        text: 'César cruzó el Rubicón. Escipión volvió a Roma.',
      );
      await h.mark(id, 'César cruzó el Rubicón.');
      final creation = await h.creation(StudyCreationKind.summary, [id]);
      await h.open(tester, creation);

      await tester.tap(find.byKey(const Key('reading-frame-contents')));
      await tester.pumpAndSettle();
      expect(find.text(es.f43StudioViewSources(1)), findsOneWidget);
      reach('«Ver N fuentes»');
      expect(find.byType(CreationSourceChips), findsOneWidget);
      reach('Las fichas de cada fuente');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reading-more-download')), findsOneWidget);
      reach('Exportar lo creado');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reading-ai-ask')), findsOneWidget);
      reach('Explicar en el chat');

      await tester.tap(find.byKey(const Key('reading-listen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('extract-player')), findsOneWidget);
      reach('🎧 de «Lo creado»');

      // El modo de lectura, sobre el tema de la app: Sepia pinta el marco.
      await tester.tap(find.byKey(const Key('reading-frame-appearance')));
      await tester.pumpAndSettle();
      final sepia = find.byKey(const Key('reading-mode-sepia'));
      await tester.ensureVisible(sepia);
      await tester.tap(sepia);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Scaffold>(find.byKey(const Key('reading-frame')))
            .backgroundColor,
        AppThemeChoice.sepia.theme.colorScheme.surface,
      );
      reach('El tema de lectura (claro, oscuro, sepia)');
    });
  });

  group('el informe', () {
    testWidgets('⋮ «Descargar» ofrece el PDF, para leer o imprimir', (
      tester,
    ) async {
      final h = await ReportHarness.create();
      await h.processed('p-1', 'Éxodo');
      final creation = await h.ready(sampleReport());
      await h.open(tester, '/creations/${creation.id}');
      expect(find.byKey(const Key('reading-frame')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reading-more-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-export-pdf')), findsOneWidget);
      reach('Imprimir');
    });
  });

  group('las páginas que se ven como son', () {
    Future<void> pumpOriginal(
      WidgetTester tester,
      OriginalFormat format,
      String path,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const article = (
        itemId: 'i1',
        renditionId: 'r1',
        content: 'El artículo.',
        markdown: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readAloudControllerProvider.overrideWith(
              FakeReadAloudController.new,
            ),
            studyRepositoryProvider.overrideWithValue(
              MemoryStudyRepository(DocumentStudy.notStarted),
            ),
            studyAnalysisProvider.overrideWith(
              (ref, id) => FakeStudyAnalysis(),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OriginalScreen(
              title: 'Un original',
              format: format,
              study: const OriginalStudy.source(article),
              body: OriginalView(
                format: format,
                path: path,
                title: 'Un original',
                text: article,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('el PDF con su página de verdad', (tester) async {
      await pumpOriginal(tester, OriginalFormat.pdf, '/no/existe.pdf');
      expect(
        find.descendant(
          of: find.byKey(const Key('reading-frame')),
          matching: find.byType(PdfViewerView),
        ),
        findsOneWidget,
      );
      reach('El PDF con su maquetación');
    });

    testWidgets('la página web, como en el teléfono', (tester) async {
      await pumpOriginal(tester, OriginalFormat.page, '/no/existe.html');
      expect(
        find.descendant(
          of: find.byKey(const Key('reading-frame')),
          matching: find.byType(MobilePageWidth),
        ),
        findsOneWidget,
      );
      reach('La página web en vista móvil');
    });
  });
}
