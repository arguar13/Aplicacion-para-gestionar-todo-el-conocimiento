import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/time_growth.dart';

const _aftermath =
    ' Los historiadores que la estudiaron no se ponen de acuerdo en cuándo '
    'empezó ni cuándo terminó, pero sí en que nada volvió a ser igual en las '
    'fábricas, los campos ni las ciudades de entonces.';

/// La tarjeta de estudiar de un libro de millones de caracteres (la app dejaba
/// de responder): armarla no recorre el texto, y «Escuchar» el texto entero lo
/// parte en otro hilo recién al tocarlo.
void main() {
  /// Un libro de [paragraphs] párrafos de unos 700 caracteres, y lo estudiado
  /// de él: la misma cantidad de oraciones y palabras clave siempre —lo que
  /// crece es el libro, no lo estudiado—.
  ({String content, DocumentStudy study}) book(int paragraphs) {
    final buffer = StringBuffer();
    final marks = <StudyMark>[];
    for (var i = 0; i < paragraphs; i++) {
      final start = buffer.length;
      const sentence =
          'La revolución industrial cambió el mundo de forma profunda y '
          'duradera para todos los pueblos.';
      buffer.write(sentence);
      if (i < 150) {
        marks
          ..add(
            StudyMark(
              id: 's$i',
              kind: StudyMarkKind.summary,
              origin: ContentOrigin.ai,
              start: start,
              end: start + sentence.length,
            ),
          )
          ..add(
            StudyMark(
              id: 'k$i',
              kind: StudyMarkKind.keyword,
              origin: ContentOrigin.ai,
              start: start + 3,
              end: start + 13,
            ),
          );
      }
      buffer
        ..write(_aftermath * 3)
        ..write('\n\n');
    }
    final content = buffer.toString();
    return (
      content: content,
      study: DocumentStudy(
        marks: marks,
        analyzedUntil: content.length,
        complete: true,
      ),
    );
  }

  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    ({String content, DocumentStudy study}) book,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(
          FakeTextToSpeechService(),
        ),
        studyRepositoryProvider.overrideWithValue(
          MemoryStudyRepository(book.study),
        ),
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
                text: (
                  itemId: 'i1',
                  renditionId: 'r1',
                  content: book.content,
                  markdown: true,
                ),
                extractedText: (_) => const Text('el texto entero'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('armar la tarjeta', () {
    testWidgets('con lo estudiado a la vista, el tiempo no crece con el libro: '
        'cuatro veces más texto, el mismo tiempo (no cuatro veces)', (
      tester,
    ) async {
      final small = book(600);
      final big = book(2400);
      expect(big.content.length, greaterThan(small.content.length * 3.5));

      Future<int> build(({String content, DocumentStudy study}) book) async {
        final watch = Stopwatch()..start();
        await pump(tester, book);
        final micros = watch.elapsedMicroseconds;
        expect(find.byKey(const Key('study-document-card')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        return micros;
      }

      final growth = await timeGrowth(() => build(small), () => build(big));

      expect(growth, lessThan(2.2));
    });
  });

  group('«Escuchar» el texto entero', () {
    testWidgets('no se parte al armar la tarjeta: recién al tocar, en otro '
        'hilo, con el botón esperando', (tester) async {
      final long = book(300);
      expect(long.content.length, greaterThan(kSegmentsInlineChars));
      await pump(tester, long);

      final row = find.byKey(const Key('study-extract-text'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      // Nada se le ofreció al lector antes de tocar.
      expect(container.read(readAloudControllerProvider).document, isNull);

      final button = find.byKey(const Key('study-listen-all'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      // Esperando: el botón no se puede tocar de nuevo.
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);

      for (var i = 0; i < 400; i++) {
        if (container.read(readAloudControllerProvider).document != null) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }

      final state = container.read(readAloudControllerProvider);
      expect(state.scope, ReadScope.all);
      expect(
        state.document!.segments,
        buildReadableSegments(long.content, sourceKey: 'r1', markdown: true),
      );
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });
  });
}
