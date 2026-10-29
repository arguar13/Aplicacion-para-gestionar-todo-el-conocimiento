import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../../../support/memory_study_repository.dart';

/// «Escuchar» en «Extraer texto» de la tarjeta de estudiar (F39): con el
/// lector en voz alta de verdad y un motor de voz de mentira. Lo que el texto
/// ofrece al lector lleva también lo estudiado —el resumen, la síntesis y las
/// palabras clave—, que se eligen en el reproductor.
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
    SourceKind kind = SourceKind.document,
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
                kind: kind,
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

  group('dónde está «Escuchar»', () {
    testWidgets('arriba del texto desplegado, y solo ahí', (tester) async {
      await pump(tester, study: analyzed);

      await unfold(tester, 'study-extract-text');

      expect(find.text(es.studyListen), findsOneWidget);
      expect(find.byKey(const Key('study-listen-all')), findsOneWidget);
      for (final scope in const ['summary', 'synthesis', 'keywords']) {
        expect(find.byKey(Key('study-listen-$scope')), findsNothing);
      }
    });

    testWidgets('la transcripción de un audio o un video también trae '
        '«Escuchar» (F40)', (tester) async {
      await pump(tester, study: analyzed, kind: SourceKind.audio);

      await unfold(tester, 'study-extract-text');

      expect(find.byKey(const Key('study-listen-all')), findsOneWidget);
    });
  });

  group('el texto entero', () {
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

    testWidgets('al escuchar la transcripción de un audio, lo estudiado '
        'también se ofrece: el resumen se puede elegir (F40)', (tester) async {
      await pump(tester, study: analyzed, kind: SourceKind.audio);
      await unfold(tester, 'study-extract-text');

      await listen(tester, 'all');

      final document = state().document!;
      expect(document.offers(ReadScope.all), isTrue);
      expect(document.offers(ReadScope.summary), isTrue);
    });
  });
}
