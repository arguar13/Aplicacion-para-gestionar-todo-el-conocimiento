import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';

/// «Escuchar» en las filas de «Extraer» de la tarjeta de estudiar (F39): con
/// el lector en voz alta de verdad y un motor de voz de mentira.
void main() {
  final es = AppLocalizationsEs();
  const content =
      'La revolución industrial cambió todo. Nada más.\n\n'
      'Las fábricas usaban vapor.';
  const text = (
    itemId: 'i1',
    renditionId: 'r1',
    content: content,
    markdown: true,
  );

  StudyMark mark(String id, StudyMarkKind kind, String part) {
    final start = content.indexOf(part);
    return StudyMark(
      id: id,
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + part.length,
    );
  }

  final analyzed = DocumentStudy(
    marks: [
      mark(
        's1',
        StudyMarkKind.summary,
        'La revolución industrial cambió todo.',
      ),
      mark('s2', StudyMarkKind.summary, 'Nada más.'),
      mark('k1', StudyMarkKind.keyword, 'revolución'),
      mark('y1', StudyMarkKind.synthesis, 'Las fábricas usaban vapor.'),
      mark('k2', StudyMarkKind.keyword, 'vapor'),
    ]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );

  late ProviderContainer container;
  late FakeTextToSpeechService tts;

  Future<void> pump(
    WidgetTester tester, {
    DocumentStudy study = DocumentStudy.notStarted,
    bool listenToText = true,
    bool withText = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        studyRepositoryProvider.overrideWithValue(MemoryStudyRepository(study)),
        studyAnalysisProvider.overrideWith((ref, id) => FakeStudyAnalysis()),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudyDocumentCard(
                text: text,
                listenToText: listenToText,
                extractedText: withText
                    ? (_) => const Text('el texto entero')
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReadAloudState state() => container.read(readAloudControllerProvider);

  Future<void> unfold(WidgetTester tester, String row) async {
    final finder = find.byKey(Key(row));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> listen(WidgetTester tester, String scope) async {
    final button = find.byKey(Key('study-listen-$scope'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> sentenceDone(WidgetTester tester) async {
    tts.completeCurrent();
    await tester.pumpAndSettle();
  }

  group('dónde está «Escuchar»', () {
    testWidgets('en cada fila con algo, junto a «Copiar»; en el texto, '
        'arriba', (tester) async {
      await pump(tester, study: analyzed);

      for (final row in const [
        'study-extract-summary',
        'study-extract-synthesis',
        'study-extract-keywords',
      ]) {
        await unfold(tester, row);
      }
      await unfold(tester, 'study-extract-text');

      expect(find.text(es.studyListen), findsNWidgets(4));
      expect(find.text(es.studyCopy), findsNWidgets(3));
      for (final scope in const ['summary', 'synthesis', 'keywords', 'all']) {
        expect(find.byKey(Key('study-listen-$scope')), findsOneWidget);
      }
    });

    testWidgets('una fila vacía no la trae: ofrece armarlo', (tester) async {
      await pump(tester);

      await unfold(tester, 'study-extract-summary');
      await unfold(tester, 'study-extract-keywords');

      expect(find.byKey(const Key('study-listen-summary')), findsNothing);
      expect(find.byKey(const Key('study-listen-keywords')), findsNothing);
    });

    testWidgets('el texto de un audio o un video, que ya suena en su propio '
        'audio, no la trae; lo estudiado sí', (tester) async {
      await pump(tester, study: analyzed, listenToText: false);

      await unfold(tester, 'study-extract-text');
      await unfold(tester, 'study-extract-summary');

      expect(find.byKey(const Key('study-listen-all')), findsNothing);
      expect(find.byKey(const Key('study-listen-summary')), findsOneWidget);
    });
  });

  group('el resumen y la síntesis', () {
    testWidgets('suenan oración por oración, en el orden del texto, con la '
        'voz del lector', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-summary');

      await listen(tester, 'summary');

      expect(state().scope, ReadScope.summary);
      expect(state().document?.id, studyReadableId('r1'));
      expect(state().playing, isTrue);
      expect(tts.spoken, ['La revolución industrial cambió todo.']);

      await sentenceDone(tester);
      expect(tts.spoken, [
        'La revolución industrial cambió todo.',
        'Nada más.',
      ]);
    });

    testWidgets('lo que suena lleva sus posiciones en el texto entero: el '
        'texto se resalta en su lugar', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-summary');
      await listen(tester, 'summary');

      final segment = state().currentSegment!;
      expect(segment.sourceKey, 'r1');
      expect(
        content.substring(segment.start, segment.end),
        'La revolución industrial cambió todo.',
      );
      expect(container.read(readAloudHighlightProvider('r1')), (
        segment.start,
        segment.end,
      ));
    });

    testWidgets('la oración que suena se ve en amarillo en la misma fila, y '
        'pasa a la que sigue', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-summary');
      final row = find.byKey(const Key('study-extract-summary'));
      expect(readAloudHighlights(tester, within: row), isEmpty);

      await listen(tester, 'summary');
      expect(readAloudHighlights(tester, within: row), [
        'La revolución industrial cambió todo.',
      ]);

      await sentenceDone(tester);
      expect(readAloudHighlights(tester, within: row), ['Nada más.']);
    });

    testWidgets('la síntesis suena aparte, con lo suyo', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-synthesis');

      await listen(tester, 'synthesis');

      expect(state().scope, ReadScope.synthesis);
      expect(tts.spoken, ['Las fábricas usaban vapor.']);
    });

    testWidgets('mientras suena dice «Pausar» y pausa; en pausa vuelve a '
        '«Escuchar» y retoma', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-summary');
      expect(find.text(es.studyListen), findsOneWidget);

      await listen(tester, 'summary');
      expect(find.text(es.mediaPlayerPause), findsOneWidget);

      await listen(tester, 'summary');
      expect(state().playing, isFalse);
      expect(find.text(es.studyListen), findsOneWidget);

      await listen(tester, 'summary');
      expect(state().playing, isTrue);
      expect(find.text(es.mediaPlayerPause), findsOneWidget);
    });

    testWidgets('leer otra fila no cambia el botón de esta', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-summary');
      await unfold(tester, 'study-extract-synthesis');

      await listen(tester, 'synthesis');

      final summary = find.byKey(const Key('study-listen-summary'));
      expect(
        find.descendant(of: summary, matching: find.text(es.studyListen)),
        findsOneWidget,
      );
      final synthesis = find.byKey(const Key('study-listen-synthesis'));
      expect(
        find.descendant(
          of: synthesis,
          matching: find.text(es.mediaPlayerPause),
        ),
        findsOneWidget,
      );
    });
  });

  group('las palabras clave y el texto entero', () {
    testWidgets('las palabras clave se leen una tras otra, y la que suena '
        'se ve en amarillo', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-keywords');

      Color? chipColor(String word) =>
          tester.widget<Chip>(find.widgetWithText(Chip, word)).backgroundColor;

      await listen(tester, 'keywords');
      expect(state().scope, ReadScope.keywords);
      expect(tts.spoken, ['revolución']);
      expect(chipColor('revolución'), RenderedMarkdown.playingColor);
      expect(chipColor('vapor'), isNot(RenderedMarkdown.playingColor));

      await sentenceDone(tester);
      expect(tts.spoken, ['revolución', 'vapor']);
      expect(chipColor('revolución'), isNot(RenderedMarkdown.playingColor));
      expect(chipColor('vapor'), RenderedMarkdown.playingColor);
    });

    testWidgets('«Extraer texto» lee todo el texto, línea por línea, con '
        'las posiciones del texto', (tester) async {
      await pump(tester, study: analyzed);
      await unfold(tester, 'study-extract-text');

      await listen(tester, 'all');

      expect(state().scope, ReadScope.all);
      expect(tts.spoken, ['La revolución industrial cambió todo. Nada más.']);
      final document = state().document!;
      expect(document.segments.map((s) => s.spoken), [
        'La revolución industrial cambió todo. Nada más.',
        'Las fábricas usaban vapor.',
      ]);
      // El reproductor ofrece las tres capas junto al texto.
      expect(document.offers(ReadScope.summary), isTrue);
      expect(document.offers(ReadScope.synthesis), isTrue);
      expect(document.offers(ReadScope.keywords), isTrue);
    });

    testWidgets('el texto de un audio, sin su propia voz, no se ofrece en el '
        'documento; lo estudiado sí', (tester) async {
      await pump(tester, study: analyzed, listenToText: false);
      await unfold(tester, 'study-extract-summary');

      await listen(tester, 'summary');

      final document = state().document!;
      expect(document.segments, isEmpty);
      expect(document.offers(ReadScope.summary), isTrue);
    });
  });
}
