import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';
import '../../../../support/recording_dated_events.dart';

class _MockOrganizeRepository extends Mock implements OrganizeRepository {}

class _MockCaptureItemUseCase extends Mock implements CaptureItemUseCase {}

/// Resaltar a mano en el lector de Word, EPUB y texto, «Leer como libro»
/// (F38): los mismos resaltados que «Texto extraído», en posiciones del texto
/// entero aunque cada página sea un tramo de él.
void main() {
  final es = AppLocalizationsEs();
  const pageOne = 'Primera página. Nada importante acá.';
  const pageTwo =
      'La revolución industrial cambió todo. Las fábricas usaban vapor.';
  const content = '$pageOne\n\n---\n\n$pageTwo';
  final twoStart = content.indexOf(pageTwo);

  late _MockOrganizeRepository repository;
  late _MockCaptureItemUseCase captureUseCase;
  late ProviderContainer container;
  late List<Map<Symbol, dynamic>> created;

  setUpAll(() {
    registerFallbackValue(RelationKind.relatedTo);
    registerFallbackValue(HighlightStyle.fill);
  });

  Highlight at(
    int start,
    int end, {
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String id = 'h1',
  }) => Highlight(
    id: id,
    renditionId: 'r1',
    startOffset: start,
    endOffset: end,
    excerpt: content.substring(start, end),
    createdAt: DateTime.utc(2026),
    color: color,
    style: style,
  );

  Future<void> pumpReader(
    WidgetTester tester, {
    List<Highlight> highlights = const [],
    bool withStudy = true,
    DocumentStudy? study,
    List<Override> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    when(
      () => repository.watchHighlightsForRendition(any()),
    ).thenAnswer((_) => Stream.value(highlights));
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        studyRepositoryProvider.overrideWithValue(
          MemoryStudyRepository(study ?? DocumentStudy.notStarted),
        ),
        organizeRepositoryProvider.overrideWithValue(repository),
        captureItemUseCaseProvider.overrideWithValue(captureUseCase),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentReaderScreen(
            title: 'Un libro',
            content: content,
            study: withStudy
                ? (
                    itemId: 'item-1',
                    renditionId: 'r1',
                    content: content,
                    markdown: true,
                  )
                : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> nextPage(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
  }

  /// Selecciona `[base, extent)` de la página que se ve y abre el menú.
  Future<void> select(WidgetTester tester, int base, int extent) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: base, extentOffset: extent),
      ),
      SelectionChangedCause.tap,
    );
    state.showToolbar();
    await tester.pumpAndSettle();
  }

  Future<void> tapAt(WidgetTester tester, int offset) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: offset),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();
  }

  List<(String, Color?, Color?)> pieces(WidgetTester tester) => [
    for (final span
        in tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .children!
            .cast<TextSpan>())
      (
        span.text!,
        span.style?.backgroundColor,
        span.style?.decoration == TextDecoration.underline
            ? span.style?.decorationColor
            : null,
      ),
  ];

  setUp(() {
    repository = _MockOrganizeRepository();
    captureUseCase = _MockCaptureItemUseCase();
    created = [];
    when(
      () => repository.createHighlight(
        renditionId: any(named: 'renditionId'),
        startOffset: any(named: 'startOffset'),
        endOffset: any(named: 'endOffset'),
        excerpt: any(named: 'excerpt'),
        note: any(named: 'note'),
        color: any(named: 'color'),
        style: any(named: 'style'),
      ),
    ).thenAnswer((invocation) async {
      created.add(invocation.namedArguments);
      return right(at(0, 5));
    });
    when(
      () => repository.updateHighlightLook(
        id: any(named: 'id'),
        color: any(named: 'color'),
        style: any(named: 'style'),
      ),
    ).thenAnswer((_) async => right(at(0, 5)));
    when(
      () => repository.deleteHighlight(any()),
    ).thenAnswer((_) async => right(unit));
  });

  group('la barrita', () {
    testWidgets('al seleccionar en la primera página aparece, y un color '
        'resalta con las posiciones del texto', (tester) async {
      await pumpReader(tester);
      expect(find.byType(HighlightToolbar), findsNothing);

      await select(tester, 0, 7);
      expect(find.byType(HighlightToolbar), findsOneWidget);
      await tester.tap(find.byKey(const Key('highlight-color-violet')));
      await tester.pumpAndSettle();

      expect(created, hasLength(1));
      expect(created.single[#renditionId], 'r1');
      expect(created.single[#startOffset], 0);
      expect(created.single[#endOffset], 7);
      expect(created.single[#excerpt], 'Primera');
      expect(created.single[#color], HighlightColor.violet);
      expect(created.single[#style], HighlightStyle.fill);
    });

    testWidgets('en la segunda página las posiciones son las del texto '
        'entero, no las de la página', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);

      await select(tester, 3, 13);
      await tester.tap(find.byKey(const Key('highlight-color-orange')));
      await tester.pumpAndSettle();

      expect(created.single[#startOffset], twoStart + 3);
      expect(created.single[#endOffset], twoStart + 13);
      expect(created.single[#excerpt], 'revolución');
      expect(created.single[#color], HighlightColor.orange);
    });

    testWidgets('Subrayar guarda un subrayado, con el último color', (
      tester,
    ) async {
      await pumpReader(tester);
      await nextPage(tester);
      await select(tester, 3, 13);
      await tester.tap(find.byKey(const Key('highlight-color-turquoise')));
      await tester.pumpAndSettle();

      await select(tester, 14, 24);
      await tester.tap(find.byKey(const Key('highlight-underline')));
      await tester.pumpAndSettle();

      expect(created.last[#style], HighlightStyle.underline);
      expect(created.last[#color], HighlightColor.turquoise);
      expect(created.last[#startOffset], twoStart + 14);
      expect(created.last[#excerpt], 'industrial');
    });

    testWidgets('Nota resalta con la nota que se escribe', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);
      await select(tester, 3, 13);

      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'clave');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(created.single[#note], 'clave');
      expect(created.single[#startOffset], twoStart + 3);
    });

    testWidgets('Extraer como nota la vincula al elemento, con el lugar del '
        'texto entero', (tester) async {
      final newItem = KnowledgeItem(
        id: 'item-extracted',
        title: 'revolución',
        source: Source(
          id: 'src',
          kind: SourceKind.manualNote,
          capturedAt: DateTime(2026),
        ),
        processingState: ProcessingState.ready,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      when(
        () => captureUseCase.call(
          const CaptureRequest.text(rawInput: 'revolución'),
        ),
      ).thenAnswer((_) async => right(newItem));
      when(
        () => repository.createRelation(
          fromItemId: any(named: 'fromItemId'),
          toItemId: any(named: 'toItemId'),
          kind: any(named: 'kind'),
          sourceCharStart: any(named: 'sourceCharStart'),
          sourceCharEnd: any(named: 'sourceCharEnd'),
        ),
      ).thenAnswer((_) async => right(unit));
      await pumpReader(tester);
      await nextPage(tester);
      await select(tester, 3, 13);

      await tester.tap(find.byTooltip(es.detailExtractSelection));
      await tester.pumpAndSettle();

      verify(
        () => repository.createRelation(
          fromItemId: 'item-extracted',
          toItemId: 'item-1',
          kind: RelationKind.extractedFrom,
          sourceCharStart: twoStart + 3,
          sourceCharEnd: twoStart + 13,
        ),
      ).called(1);
    });

    testWidgets('Hacer tarjeta pide la pregunta, con el fragmento de '
        'respuesta', (tester) async {
      await pumpReader(tester);
      await select(tester, 0, 7);

      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Primera'), findsOneWidget);
    });

    testWidgets('A la línea de tiempo abre el formulario con la cita, en '
        'posiciones del texto entero (F40)', (tester) async {
      final dated = RecordingDatedEvents();
      await pumpReader(
        tester,
        extra: [
          datedEventRepositoryProvider.overrideWithValue(dated),
          libraryItemProvider.overrideWith((ref, id) => Stream.value(null)),
        ],
      );
      await nextPage(tester);
      await select(tester, 3, 13);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      // La cita puesta, la fecha vacía (la selección no trae ninguna) y el
      // título propuesto: la propia cita, que es corta.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dated-event-form-quote')),
          matching: find.text('revolución'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1850',
      );
      await tester.tap(find.byKey(const ValueKey('dated-event-form-save')));
      await tester.pumpAndSettle();

      final saved = dated.added.single;
      expect(saved.itemId, 'item-1');
      expect(saved.input.title, 'revolución');
      expect(saved.input.date.year, 1850);
      expect(saved.input.renditionId, 'r1');
      expect(saved.input.startOffset, twoStart + 3);
      expect(saved.input.endOffset, twoStart + 13);
      expect(saved.input.excerpt, 'revolución');
    });

    testWidgets('sin el texto de un elemento —un adjunto— no hay dónde '
        'guardar un resaltado: el menú de siempre', (tester) async {
      await pumpReader(tester, withStudy: false);

      await select(tester, 0, 7);

      expect(find.byType(HighlightToolbar), findsNothing);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });
  });

  group('pintado', () {
    testWidgets('lo subrayado se ve en su página con su color, y el de antes '
        'con el de siempre', (tester) async {
      await pumpReader(
        tester,
        highlights: [
          at(0, 7, color: HighlightColor.violet),
          at(twoStart + 3, twoStart + 13, id: 'h2'),
        ],
      );
      final context = tester.element(find.byType(DocumentReaderScreen));

      expect(pieces(tester).first, (
        'Primera',
        HighlightPalette.resolve(context, HighlightColor.violet),
        null,
      ));
      await nextPage(tester);
      expect(pieces(tester).firstWhere((p) => p.$1 == 'revolución'), (
        'revolución',
        Theme.of(context).colorScheme.tertiaryContainer,
        null,
      ));
    });

    testWidgets('cada uno de los nueve colores se pinta en «Leer como libro» '
        'con su tono, de fondo y de subrayado (F39)', (tester) async {
      for (final color in HighlightColor.values) {
        await pumpReader(tester, highlights: [at(0, 7, color: color)]);
        var context = tester.element(find.byType(DocumentReaderScreen));
        expect(pieces(tester).first, (
          'Primera',
          HighlightPalette.resolve(context, color),
          null,
        ), reason: color.name);

        await tester.pumpWidget(const SizedBox());
        await pumpReader(
          tester,
          highlights: [at(0, 7, color: color, style: HighlightStyle.underline)],
        );
        context = tester.element(find.byType(DocumentReaderScreen));
        expect(pieces(tester).first, (
          'Primera',
          null,
          HighlightPalette.line(context, color),
        ), reason: color.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('un subrayado que ya no entra en el texto —la forma se '
        'regeneró más corta— no se pinta', (tester) async {
      await pumpReader(
        tester,
        highlights: [
          Highlight(
            id: 'fuera',
            renditionId: 'r1',
            startOffset: 0,
            endOffset: content.length + 50,
            excerpt: 'un fragmento que ya no está',
            createdAt: DateTime.utc(2026),
            color: HighlightColor.orange,
          ),
        ],
      );

      expect(pieces(tester).where((p) => p.$2 != null), isEmpty);
    });

    testWidgets('un subrayado que cruza de una página a otra se recorta en '
        'cada una', (tester) async {
      final end = twoStart + 8;
      await pumpReader(
        tester,
        highlights: [
          at(
            content.indexOf('importante'),
            end,
            color: HighlightColor.orange,
            style: HighlightStyle.underline,
          ),
        ],
      );
      final context = tester.element(find.byType(DocumentReaderScreen));
      final line = HighlightPalette.line(context, HighlightColor.orange);

      expect(
        pieces(tester).where((p) => p.$3 == line).map((p) => p.$1).join(),
        contains('importante'),
      );
      await nextPage(tester);
      expect(
        pieces(tester).where((p) => p.$3 == line).map((p) => p.$1).join(),
        'La revol',
      );
    });

    testWidgets('lo que subrayó la persona va encima de la oración y debajo '
        'de la palabra clave', (tester) async {
      final summary = StudyMark(
        id: 's1',
        kind: StudyMarkKind.summary,
        origin: ContentOrigin.ai,
        start: twoStart,
        end: twoStart + 37,
      );
      final keyword = StudyMark(
        id: 'k1',
        kind: StudyMarkKind.keyword,
        origin: ContentOrigin.ai,
        start: twoStart + 3,
        end: twoStart + 8,
      );
      await pumpReader(
        tester,
        highlights: [at(twoStart, twoStart + 20, color: HighlightColor.violet)],
        study: DocumentStudy(
          marks: [summary, keyword],
          analyzedUntil: content.length,
          complete: true,
        ),
      );
      await nextPage(tester);
      container.read(studyViewProvider('r1').notifier).state = const StudyView(
        summary: true,
        keywords: true,
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DocumentReaderScreen));
      final study = StudyPalette.of(Theme.of(context).brightness);

      expect(pieces(tester).map((p) => (p.$1, p.$2)), [
        ('La ', HighlightPalette.resolve(context, HighlightColor.violet)),
        ('revol', study.keyword),
        (
          'ución indust',
          HighlightPalette.resolve(context, HighlightColor.violet),
        ),
        ('rial cambió todo.', study.summary),
        (' Las fábricas usaban vapor.', null),
      ]);
    });
  });

  group('la ficha', () {
    testWidgets('tocar algo ya resaltado la abre, y cambiarle el color lo '
        'guarda', (tester) async {
      await pumpReader(
        tester,
        highlights: [at(twoStart + 3, twoStart + 13, id: 'h2')],
      );
      await nextPage(tester);

      await tapAt(tester, 6);
      expect(find.text(es.highlightCardTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-color-violet')));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateHighlightLook(
          id: 'h2',
          color: HighlightColor.violet,
          style: HighlightStyle.fill,
        ),
      ).called(1);
    });

    testWidgets('quitarlo desde la ficha lo borra', (tester) async {
      await pumpReader(
        tester,
        highlights: [at(twoStart + 3, twoStart + 13, id: 'h2')],
      );
      await nextPage(tester);
      await tapAt(tester, 6);

      await tester.tap(find.text(es.detailRemoveHighlight));
      await tester.pumpAndSettle();

      verify(() => repository.deleteHighlight('h2')).called(1);
    });

    testWidgets('tocar lo que no está resaltado no abre nada', (tester) async {
      await pumpReader(
        tester,
        highlights: [at(twoStart + 3, twoStart + 13, id: 'h2')],
      );
      await nextPage(tester);

      await tapAt(tester, 30);

      expect(find.text(es.highlightCardTitle), findsNothing);
    });

    testWidgets('eligiendo palabras clave, tocar es para elegirlas: no abre '
        'la ficha', (tester) async {
      await pumpReader(
        tester,
        highlights: [at(twoStart + 3, twoStart + 13, id: 'h2')],
      );
      await nextPage(tester);
      container.read(studyViewProvider('r1').notifier).state = const StudyView(
        pick: StudyMarkKind.keyword,
      );
      await tester.pumpAndSettle();

      await tapAt(tester, 6);

      expect(find.text(es.highlightCardTitle), findsNothing);
    });
  });
}
