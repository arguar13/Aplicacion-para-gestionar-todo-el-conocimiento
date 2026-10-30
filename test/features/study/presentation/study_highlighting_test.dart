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

  group('StudyView: cada resaltado por su lado (F39)', () {
    test('prender o apagar uno no toca el otro ni las palabras clave', () {
      const none = StudyView(keywords: true);

      expect(
        none.withLayer(StudyLayer.synthesis, on: true),
        const StudyView(synthesis: true, keywords: true),
      );
      expect(
        none.withLayer(StudyLayer.summary, on: true),
        const StudyView(summary: true, keywords: true),
      );

      const both = StudyView(summary: true, synthesis: true);
      expect(
        both.withLayer(StudyLayer.summary, on: false),
        const StudyView(synthesis: true),
      );
      expect(
        both.withLayer(StudyLayer.synthesis, on: false),
        const StudyView(summary: true),
      );
    });

    test('shows y layers dicen cuál se ve, el resumen abajo', () {
      const synthesis = StudyView(synthesis: true);
      expect(synthesis.shows(StudyLayer.synthesis), isTrue);
      expect(synthesis.shows(StudyLayer.summary), isFalse);
      expect(const StudyView(summary: true).shows(StudyLayer.summary), isTrue);
      expect(const StudyView(summary: true, synthesis: true).layers, [
        StudyLayer.summary,
        StudyLayer.synthesis,
      ]);
    });

    test('dos vistas son iguales solo si coinciden en todo', () {
      const base = StudyView(summary: true);
      expect(base, const StudyView(summary: true));
      expect(base.hashCode, const StudyView(summary: true).hashCode);
      for (final other in const [
        StudyView(),
        StudyView(summary: true, synthesis: true),
        StudyView(summary: true, keywords: true),
        StudyView(summary: true, pick: StudyMarkKind.summary),
      ]) {
        expect(base, isNot(other));
      }
    });
  });

  group('studyPaints', () {
    test('sin nada prendido no se pinta nada', () {
      expect(studyPaints(study, const StudyView(), light), isEmpty);
    });

    test('el resumen pinta sus oraciones de verde, debajo, y la síntesis no '
        'aparece', () {
      final paints = studyPaints(study, const StudyView(summary: true), light);

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

    test('las palabras clave van encima y en negrita, todas, también las '
        'de oraciones que no se ven resaltadas (F39)', () {
      final paints = studyPaints(
        study,
        const StudyView(synthesis: true, keywords: true),
        light,
      );

      expect(
        [for (final p in paints) content.substring(p.start, p.end)],
        ['Las fábricas usaban vapor.', 'revolución', 'vapor'],
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

    test('eligiendo palabras clave, se ven aunque no estén prendidas, y '
        'todas, no solo las del resumen: se eligen en cualquier oración '
        '(F39)', () {
      final paints = studyPaints(
        study,
        const StudyView(summary: true, pick: StudyMarkKind.keyword),
        light,
      );

      expect(
        [for (final p in paints) (content.substring(p.start, p.end), p.bold)],
        [
          ('La revolución industrial cambió todo.', false),
          ('revolución', true),
          ('vapor', true),
        ],
      );
    });

    test('con el resumen prendido, también todas las palabras clave: se '
        'estudian de punta a punta (F39)', () {
      final paints = studyPaints(
        study,
        const StudyView(summary: true, keywords: true),
        light,
      );

      expect(
        [
          for (final p in paints)
            if (p.bold) content.substring(p.start, p.end),
        ],
        ['revolución', 'vapor'],
      );
    });

    test('el resumen y la síntesis juntos: cada uno con su color, la síntesis '
        'después —encima— en la oración que está en los dos (F39), y ahí la '
        'línea verde del resumen, para que se vean los dos (F43, paso 15)', () {
      final first = study.of(StudyMarkKind.summary).single;
      final both = DocumentStudy(
        marks: [
          ...study.marks,
          StudyMark(
            id: 'y2',
            kind: StudyMarkKind.synthesis,
            origin: ContentOrigin.ai,
            start: first.start,
            end: first.end,
          ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
        analyzedUntil: content.length,
        complete: true,
      );

      final paints = studyPaints(
        both,
        const StudyView(summary: true, synthesis: true),
        light,
      );

      expect(
        [
          for (final p in paints)
            (content.substring(p.start, p.end), p.background),
        ],
        [
          ('La revolución industrial cambió todo.', light.summary),
          ('La revolución industrial cambió todo.', light.synthesis),
          ('Las fábricas usaban vapor.', light.synthesis),
          ('La revolución industrial cambió todo.', light.synthesis),
        ],
      );
      expect(
        [for (final p in paints) p.underline],
        [null, null, null, StudyPalette.summaryLine],
      );
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
      view().state = const StudyView(summary: true, keywords: true);
      await tester.pumpAndSettle();

      expect(
        pieces(tester).where((p) => p.$2 != null),
        isEmpty,
        reason: 'la primera página no tiene nada del resumen',
      );

      await nextPage(tester);

      // La palabra clave de una oración que no está en el resumen también se
      // ve: se estudian de punta a punta (F39).
      expect(pieces(tester), [
        ('La ', light.summary),
        ('revolución', light.keyword),
        (' industrial cambió todo.', light.summary),
        (' Las fábricas usaban ', null),
        ('vapor', light.keyword),
        ('.', null),
      ]);
    });

    testWidgets('la síntesis sola, sin el resumen; y los dos juntos, cada uno '
        'en lo suyo (F39)', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);

      view().state = const StudyView(synthesis: true);
      await tester.pumpAndSettle();

      expect(pieces(tester), [
        ('La revolución industrial cambió todo. ', null),
        ('Las fábricas usaban vapor.', light.synthesis),
      ]);

      view().state = const StudyView(summary: true, synthesis: true);
      await tester.pumpAndSettle();

      expect(pieces(tester), [
        ('La revolución industrial cambió todo.', light.summary),
        (' ', null),
        ('Las fábricas usaban vapor.', light.synthesis),
      ]);
    });

    testWidgets('eligiendo palabras clave, tocar una la agrega con su lugar '
        'en el texto entero, y tocarla de nuevo la saca', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(
        summary: true,
        pick: StudyMarkKind.keyword,
      );
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

    testWidgets('eligiendo el resumen a mano, tocar una oración la pone en '
        'el resumen —se pinta— y tocarla de nuevo la saca (F39)', (
      tester,
    ) async {
      repository = MemoryStudyRepository(DocumentStudy.notStarted);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          studyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(
        summary: true,
        pick: StudyMarkKind.summary,
      );
      await tester.pumpAndSettle();

      await tapAt(tester, pageTwo.indexOf('fábricas'));

      expect(repository.added, ['Las fábricas usaban vapor.']);
      expect(pieces(tester), [
        ('La revolución industrial cambió todo. ', null),
        ('Las fábricas usaban vapor.', light.summary),
      ]);

      await tapAt(tester, pageTwo.indexOf('vapor'));

      expect(repository.removed, ['new0']);
      expect(pieces(tester).where((p) => p.$2 != null), isEmpty);
    });

    testWidgets('sin elegir palabras clave, tocar no cambia nada', (
      tester,
    ) async {
      await pumpReader(tester);
      await nextPage(tester);
      view().state = const StudyView(summary: true);
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
      view().state = const StudyView(
        summary: true,
        pick: StudyMarkKind.keyword,
      );
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

    testWidgets('abajo no lleva «Resumir con IA»: las fichas van arriba, en '
        'el original (F45, paso 7b); y se abre como lo dejó la persona, con lo '
        'marcado a la vista', (tester) async {
      await pumpReader(tester);
      await nextPage(tester);

      expect(find.byType(SummarizeButton), findsNothing);
      expect(view().state, markedCopyStudyView());
      expect(pieces(tester).where((p) => p.$2 == light.summary), isNotEmpty);

      view().state = view().state.withLayer(StudyLayer.summary, on: false);
      await tester.pumpAndSettle();
      expect(pieces(tester).where((p) => p.$2 == light.summary), isEmpty);
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

    testWidgets('lo que se prende en un texto no se prende en otro', (
      tester,
    ) async {
      await pumpReader(tester, renditionId: 'otro');
      await nextPage(tester);
      container.read(studyViewProvider('otro').notifier).state =
          const StudyView();
      view().state = const StudyView(summary: true);
      await tester.pumpAndSettle();

      expect(pieces(tester).where((p) => p.$2 != null), isEmpty);
    });
  });

  group('ninguna capa tapa a otra (F43, paso 15)', () {
    const text = 'Roma fundó colonias. Cartago perdió la guerra.';
    StudyMark at(String id, StudyMarkKind kind, int start, int end) =>
        StudyMark(
          id: id,
          kind: kind,
          origin: ContentOrigin.ai,
          start: start,
          end: end,
        );
    final both = DocumentStudy(
      marks: [
        at('r1', StudyMarkKind.summary, 0, 20),
        at('s1', StudyMarkKind.synthesis, 0, 20),
        at('k1', StudyMarkKind.keyword, 5, 10),
        at('r2', StudyMarkKind.summary, 21, text.length),
      ],
      analyzedUntil: text.length,
      complete: true,
    );

    test('una oración del resumen y de la síntesis se ve celeste con la '
        'línea verde del resumen debajo; la palabra clave, rosa encima', () {
      final paints = studyPaints(
        both,
        const StudyView(summary: true, synthesis: true, keywords: true),
        light,
      );

      final lined = paints.where((p) => p.underline != null).toList();
      expect(lined, hasLength(1));
      expect((lined.single.start, lined.single.end), (0, 20));
      expect(lined.single.background, light.synthesis);
      expect(lined.single.underline, StudyPalette.summaryLine);
      expect(lined.single.aboveHighlights, isFalse);
      // Va encima del verde y del celeste, y debajo de la palabra clave.
      final index = paints.indexOf(lined.single);
      expect(
        paints.indexWhere((p) => p.background == light.summary),
        lessThan(index),
      );
      expect(
        paints.indexWhere((p) => p.background == light.synthesis),
        lessThan(index),
      );
      final keyword = paints.last;
      expect((keyword.start, keyword.end), (5, 10));
      expect(keyword.background, light.keyword);
      expect(keyword.aboveHighlights, isTrue);
      // La otra oración del resumen, sola, sin línea.
      expect(
        paints.where((p) => p.start == 21 && p.underline == null),
        hasLength(1),
      );
    });

    test('con uno solo a la vista, no hay línea', () {
      for (final view in const [
        StudyView(summary: true, keywords: true),
        StudyView(synthesis: true, keywords: true),
      ]) {
        expect(
          studyPaints(both, view, light).where((p) => p.underline != null),
          isEmpty,
        );
      }
    });

    test('donde se pisan a medias, la línea va solo en lo que comparten', () {
      final partial = DocumentStudy(
        marks: [
          at('r1', StudyMarkKind.summary, 0, 30),
          at('s1', StudyMarkKind.synthesis, 21, 40),
          at('r2', StudyMarkKind.summary, 32, 46),
        ],
        analyzedUntil: 46,
        complete: true,
      );

      final lined = [
        for (final p in studyPaints(
          partial,
          const StudyView(summary: true, synthesis: true),
          light,
        ))
          if (p.underline != null) (p.start, p.end),
      ];

      expect(lined, [(21, 30), (32, 40)]);
    });

    test('el original se abre con todo a la vista, menos lo que se dejó '
        'oculto en ese documento', () {
      expect(
        markedCopyStudyView(),
        const StudyView(summary: true, synthesis: true, keywords: true),
      );
      expect(
        markedCopyStudyView({StudyMarkKind.keyword}),
        const StudyView(summary: true, synthesis: true),
      );
      expect(
        markedCopyStudyView({StudyMarkKind.summary, StudyMarkKind.synthesis}),
        const StudyView(keywords: true),
      );
    });
  });
}
