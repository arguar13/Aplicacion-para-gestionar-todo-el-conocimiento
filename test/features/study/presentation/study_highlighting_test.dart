import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../support/memory_study_repository.dart';
import '../../../support/read_aloud_test_support.dart';

void main() {
  const pageOne = 'Primera página. Nada importante acá.';
  const pageTwo =
      'La revolución industrial cambió todo. Las fábricas usaban vapor.';
  const content = '$pageOne\n\n---\n\n$pageTwo';

  StudyMark mark(String id, StudyMarkKind kind, String text) {
    final start = content.indexOf(text);
    return StudyMark(
      id: id,
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + text.length,
    );
  }

  final study = DocumentStudy(
    marks: [
      mark(
        's1',
        StudyMarkKind.summary,
        'La revolución industrial cambió todo.',
      ),
      mark('k1', StudyMarkKind.keyword, 'revolución'),
      mark('y1', StudyMarkKind.synthesis, 'Las fábricas usaban vapor.'),
      mark('k2', StudyMarkKind.keyword, 'vapor'),
    ]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );
  final light = StudyPalette.of(Brightness.light);

  group('studyPaints', () {
    test('sin nada prendido no se pinta nada', () {
      expect(studyPaints(study, const StudyView(), light), isEmpty);
    });

    test('el resumen pinta sus oraciones de verde, debajo, y la síntesis no '
        'aparece', () {
      final paints = studyPaints(
        study,
        const StudyView(layer: StudyLayer.summary),
        light,
      );

      expect(paints, hasLength(1));
      final sentence = paints.single;
      expect(
        content.substring(sentence.start, sentence.end),
        'La revolución industrial cambió todo.',
      );
      expect(sentence.background, light.summary);
      expect(sentence.foreground, StudyPalette.ink);
      expect(sentence.aboveHighlights, isFalse);
    });

    test('las palabras clave van encima y en negrita, solo las de las '
        'oraciones que se ven', () {
      final paints = studyPaints(
        study,
        const StudyView(layer: StudyLayer.synthesis, keywords: true),
        light,
      );

      expect(
        [for (final p in paints) content.substring(p.start, p.end)],
        ['Las fábricas usaban vapor.', 'vapor'],
      );
      expect(paints.first.background, light.synthesis);
      final keyword = paints.last;
      expect(keyword.background, light.keyword);
      expect(keyword.bold, isTrue);
      expect(keyword.aboveHighlights, isTrue);
    });

    test('sin resumen ni síntesis, las palabras clave se ven solas, las de '
        'las dos', () {
      final paints = studyPaints(study, const StudyView(keywords: true), light);

      expect(
        [for (final p in paints) content.substring(p.start, p.end)],
        ['revolución', 'vapor'],
      );
    });

    test('eligiendo palabras clave, se ven aunque no estén prendidas', () {
      final paints = studyPaints(
        study,
        const StudyView(layer: StudyLayer.summary, picking: true),
        light,
      );

      expect(paints.map((p) => p.bold), [false, true]);
    });

    test('los colores de modo oscuro son otros, pero no el amarillo de lo '
        'que suena', () {
      final dark = StudyPalette.of(Brightness.dark);

      expect(dark.summary, isNot(light.summary));
      for (final palette in [light, dark]) {
        expect({
          palette.summary,
          palette.synthesis,
          palette.keyword,
        }, hasLength(3));
        expect([
          palette.summary,
          palette.synthesis,
          palette.keyword,
        ], isNot(contains(RenderedMarkdown.playingColor)));
      }
    });
  });

  test('paintsWithin recorta a la página y cuenta desde su principio', () {
    const paints = [
      PaintedRange(0, 5, background: Colors.green),
      PaintedRange(8, 20, background: Colors.blue, bold: true),
      PaintedRange(25, 30, background: Colors.pink),
    ];

    final within = paintsWithin(paints, 10, 25);

    expect(within, hasLength(1));
    expect((within.single.start, within.single.end), (0, 10));
    expect(within.single.bold, isTrue);
    expect(paintsWithin(paints, 5, 8), isEmpty);
  });

  group('en «Leer como libro»', () {
    late ProviderContainer container;
    late MemoryStudyRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repository = MemoryStudyRepository(study);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          studyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> pumpReader(WidgetTester tester, {String? renditionId}) async {
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
              study: (
                itemId: 'i1',
                renditionId: renditionId ?? 'r1',
                content: content,
                markdown: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    StateController<StudyView> view() =>
        container.read(studyViewProvider('r1').notifier);

    Future<void> nextPage(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }

    /// Los tramos de la página que se ve, con su fondo.
    List<(String, Color?)> pieces(WidgetTester tester) => [
      for (final span
          in tester
              .widget<SelectableText>(find.byType(SelectableText))
              .textSpan!
              .children!
              .cast<TextSpan>())
        (span.text!, span.style?.backgroundColor),
    ];

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

    testWidgets('el resumen se pinta en su página, en su lugar, aunque la '
        'página empiece más adelante en el texto', (tester) async {
      await pumpReader(tester);
      view().state = const StudyView(layer: StudyLayer.summary, keywords: true);
      await tester.pumpAndSettle();

      expect(
        pieces(tester).where((p) => p.$2 != null),
        isEmpty,
        reason: 'la primera página no tiene nada del resumen',
      );

      await nextPage(tester);

      expect(pieces(tester), [
        ('La ', light.summary),
        ('revolución', light.keyword),
        (' industrial cambió todo.', light.summary),
        (' Las fábricas usaban vapor.', null),
      ]);
    });

    testWidgets('pasar a la síntesis apaga el resumen: nunca los dos', (
      tester,
    ) async {
      await pumpReader(tester);
      await nextPage(tester);

      view().state = const StudyView(layer: StudyLayer.synthesis);
      await tester.pumpAndSettle();

      expect(pieces(tester), [
        ('La revolución industrial cambió todo. ', null),
        ('Las fábricas usaban vapor.', light.synthesis),
      ]);
    });

    testWidgets('eligiendo palabras clave, tocar una la agrega con su lugar '
        'en el texto entero, y tocarla de nuevo la saca', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(layer: StudyLayer.summary, picking: true);
      await tester.pumpAndSettle();

      await tapAt(tester, pageTwo.indexOf('industrial') + 2);

      expect(repository.added, ['industrial']);
      expect(
        pieces(tester).firstWhere((p) => p.$1 == 'industrial').$2,
        light.keyword,
      );

      await tapAt(tester, pageTwo.indexOf('industrial') + 2);

      expect(repository.removed, ['new0']);
      expect(pieces(tester).where((p) => p.$1 == 'industrial'), isEmpty);
    });

    testWidgets('sin elegir palabras clave, tocar no cambia nada', (
      tester,
    ) async {
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(layer: StudyLayer.summary);
      await tester.pumpAndSettle();

      await tapAt(tester, pageTwo.indexOf('industrial') + 2);

      expect(repository.added, isEmpty);
      expect(repository.removed, isEmpty);
    });

    testWidgets('con la oración llena, lo avisa', (tester) async {
      repository = MemoryStudyRepository(
        DocumentStudy(
          marks: [
            mark(
              's1',
              StudyMarkKind.summary,
              'La revolución industrial cambió todo.',
            ),
            for (final (i, word) in const [
              'revolución',
              'La',
              'cambió',
              'todo',
            ].indexed)
              mark('k$i', StudyMarkKind.keyword, word),
          ]..sort((a, b) => a.start.compareTo(b.start)),
          analyzedUntil: content.length,
          complete: true,
        ),
      );
      container.dispose();
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          studyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(layer: StudyLayer.summary, picking: true);
      await tester.pumpAndSettle();

      await tapAt(tester, pageTwo.indexOf('industrial') + 2);

      expect(repository.added, isEmpty);
      expect(
        find.text(
          'Esta oración ya tiene sus 4 palabras clave: sacá una para '
          'elegir otra.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('abajo lleva los botones de estudiar, no «Resumir con IA»: '
        'Resumir pinta el resumen en la página', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);

      expect(find.byType(SummarizeButton), findsNothing);
      await tester.tap(find.byKey(const Key('study-toggle-summary')));
      await tester.pumpAndSettle();

      expect(view().state.layer, StudyLayer.summary);
      expect(pieces(tester).where((p) => p.$2 == light.summary), isNotEmpty);
    });

    testWidgets('un texto que no se estudia —un adjunto— sigue con «Resumir '
        'con IA»', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DocumentReaderScreen(title: 'Un adjunto', content: content),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SummarizeButton), findsOneWidget);
      expect(find.byKey(const Key('study-toggle-summary')), findsNothing);
    });

    testWidgets('lo de un texto no se pinta en otro', (tester) async {
      await pumpReader(tester, renditionId: 'otro');
      await nextPage(tester);
      view().state = const StudyView(layer: StudyLayer.summary);
      await tester.pumpAndSettle();

      expect(pieces(tester).where((p) => p.$2 != null), isEmpty);
    });
  });
}
