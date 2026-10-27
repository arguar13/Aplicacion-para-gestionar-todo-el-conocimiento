import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/domain/usecases/fill_study_keywords.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/memory_study_repository.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Completar las palabras clave de lo ya analizado al prender «Palabras
/// clave» (sin IA, sin red).
void main() {
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

  // Analizado "como antes": una palabra en la primera oración y nada más.
  final analyzed = DocumentStudy(
    marks: [mark('k1', StudyMarkKind.keyword, 'revolución')],
    analyzedUntil: content.length,
    complete: true,
  );

  late ProviderContainer container;
  late MemoryStudyRepository repository;
  late FakeStudyAnalysis analysis;
  late _MockTelemetry telemetry;
  late List<StudyFillJob> jobs;

  /// Muestra los botones de [shown] en la sesión de ahora.
  Future<void> show(WidgetTester tester, StudyText shown) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudyToggles(text: shown)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    DocumentStudy study = DocumentStudy.notStarted,
    StudyFillRunner? runner,
    StudyText shown = text,
  }) async {
    repository = MemoryStudyRepository(study);
    analysis = FakeStudyAnalysis();
    telemetry = _MockTelemetry();
    jobs = [];
    container = ProviderContainer(
      overrides: [
        studyRepositoryProvider.overrideWithValue(repository),
        studyAnalysisProvider.overrideWith((ref, id) => analysis),
        telemetryServiceProvider.overrideWithValue(telemetry),
        studyFillRunnerProvider.overrideWithValue(
          runner ??
              (job) async {
                jobs.add(job);
                return missingKeywordsOfText(job);
              },
        ),
      ],
    );
    addTearDown(container.dispose);
    await show(tester, shown);
  }

  Future<void> tapKeywords(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('study-toggle-keywords')));
    await tester.pumpAndSettle();
  }

  test('por debajo de ciertos caracteres corre en el momento; el límite es '
      'el de un libro', () {
    expect(kStudyFillIsolateChars, greaterThan(content.length));
    expect(kStudyFillIsolateChars, lessThanOrEqualTo(100000));
  });

  test('el corredor por defecto: un libro largo va a otro hilo y da lo mismo '
      'que en el momento', () async {
    final big = List.filled(
      kStudyFillIsolateChars ~/ 30 + 50,
      'El vapor movía la fábrica de Manchester.\n\n',
    ).join();
    expect(big.length, greaterThanOrEqualTo(kStudyFillIsolateChars));
    final job = StudyFillJob(
      content: big,
      markdown: true,
      keywordRanges: const [],
      until: big.length,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final viaRunner = await container.read(studyFillRunnerProvider)(job);

    expect(viaRunner, isNotEmpty);
    expect(viaRunner, missingKeywordsOfText(job));
  });

  testWidgets('prender «Palabras clave» en un texto analizado de antes '
      'completa las oraciones que no tenían, y no pide nada a la IA', (
    tester,
  ) async {
    await pump(tester, study: analyzed);

    await tapKeywords(tester);

    expect(jobs, hasLength(1));
    expect(jobs.single.content, content);
    expect(jobs.single.until, content.length);
    final keywords = repository
        .read('r1')
        .then((s) => s.of(StudyMarkKind.keyword));
    final words = [
      for (final k in await keywords) content.substring(k.start, k.end),
    ];
    expect(words, contains('revolución'));
    // «Nada más.» y «Las fábricas usaban vapor.» ahora tienen las suyas.
    expect(words.where((w) => 'Nada más.'.contains(w)), isNotEmpty);
    expect(words.where((w) => w == 'fábricas' || w == 'vapor'), isNotEmpty);
    expect(analysis.starts, isEmpty);
  });

  testWidgets('una vez por texto en la sesión: apagar y volver a prender no '
      'lo vuelve a mirar', (tester) async {
    await pump(tester, study: analyzed);

    await tapKeywords(tester);
    await tapKeywords(tester);
    await tapKeywords(tester);

    expect(jobs, hasLength(1));
  });

  testWidgets('un texto que se vuelve a extraer —otro largo, la misma forma— '
      'se mira de nuevo en la misma sesión', (tester) async {
    await pump(tester, study: analyzed);
    await tapKeywords(tester);
    expect(jobs, hasLength(1));

    await show(tester, (
      itemId: 'i1',
      renditionId: 'r1',
      content: '$content Y un renglón más.',
      markdown: true,
    ));
    await tapKeywords(tester); // apaga
    await tapKeywords(tester); // prende
    expect(jobs, hasLength(2));
  });

  testWidgets('mientras se está analizando no completa: lo hace el propio '
      'análisis', (tester) async {
    await pump(tester, study: analyzed);
    analysis.shown = const StudyAnalysisRunning(null);

    await tapKeywords(tester);

    expect(jobs, isEmpty);
  });

  testWidgets('si falla se registra, no se nota, y la próxima vez se '
      'reintenta', (tester) async {
    var attempts = 0;
    await pump(
      tester,
      study: analyzed,
      runner: (job) async {
        attempts++;
        if (attempts == 1) throw StateError('se cortó');
        return missingKeywordsOfText(job);
      },
    );

    await tapKeywords(tester); // prende: falla
    verify(
      () => telemetry.recordError(
        any<dynamic>(),
        any(),
        hint: any(named: 'hint'),
      ),
    ).called(1);
    expect(repository.filled, isEmpty);

    await tapKeywords(tester); // apaga
    await tapKeywords(tester); // prende: ahora sí
    expect(attempts, 2);
    expect(repository.filled, isNotEmpty);
  });
}
