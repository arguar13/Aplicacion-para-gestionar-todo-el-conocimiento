import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_tidy_queue.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_tidy_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_tidy_notice_listener.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_triage_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/library_harness.dart';

/// Lo que la IA de mentira contesta: los renglones de cada párrafo unidos.
class _FakeTidier implements TextTidier {
  final asked = <String>[];

  @override
  int get tidyPartChars => 3000;

  @override
  Future<String> tidyPart(String text) async {
    asked.add(text);
    return text.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), ' ');
  }
}

class _MemoryStore implements ProcessedTidyStore {
  final jobs = <ProcessedTidyJob>[];
  final saved = <String>[];

  @override
  Future<List<ProcessedTidyJob>> pending() async => [...jobs];

  @override
  Future<void> save(ProcessedTidyJob job) async {
    saved.add(job.documentId);
    final index = jobs.indexWhere((j) => j.documentId == job.documentId);
    if (index < 0) {
      jobs.add(job);
    } else {
      jobs[index] = job;
    }
  }

  @override
  Future<void> remove(String documentId) async =>
      jobs.removeWhere((j) => j.documentId == documentId);
}

const _extracted =
    'La república romana\ncayó cuando César\ncruzó el Rubicón.\n\n'
    'El Senado lo declaró\nenemigo público.';

/// «Texto extraído» con la IA de turno en la hoja «¿Qué va a Procesado?»
/// (F45, decisión B): qué dice, qué pide al tocar «Listo» y el aviso de
/// cómo terminó. Con una IA de mentira: sin red ni modelos.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late _FakeTidier tidier;
  late _MemoryStore store;
  final docId = processedDocumentIdFor('fuente');

  Future<void> setUpWith({bool modelReady = true}) async {
    tidier = _FakeTidier();
    store = _MemoryStore();
    harness = await LibraryHarness.create(
      chatModelReady: modelReady,
      extraOverrides: [
        textTidierProvider.overrideWithValue(tidier),
        processedTidyStoreProvider.overrideWithValue(store),
      ],
    );
  }

  /// Un PDF —texto tal cual, sin Markdown— o, con [kind], otra fuente.
  Future<void> seedSource({SourceKind kind = SourceKind.document}) async {
    final now = DateTime(2026, 10, 30, 9);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Historia de Roma',
            source: Source(
              id: 'src-fuente',
              kind: kind,
              capturedAt: now,
              url: kind == SourceKind.webPage ? 'https://ejemplo.org' : null,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: _extracted,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  Failure? answer;
  setUp(() => answer = null);

  Future<void> pumpSheet(
    WidgetTester tester, {
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(900, 1600),
    Map<ProcessedSection, int>? existing,
    Set<ProcessedChange> changes = const {ProcessedChange.add},
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showProcessedTriageSheet(
                    context,
                    sourceItemId: 'fuente',
                    existing: existing,
                    changes: changes,
                    // Lo que hace la Bandeja: procesar de verdad.
                    onDone: (edits, original) async {
                      if (answer case final failure?) return failure;
                      final processed = await harness.container
                          .read(processSourceUseCaseProvider)
                          .call('fuente', edits, original: original);
                      return processed.getLeft().toNullable();
                    },
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('processed-triage-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();
  }

  /// Deja que la cola termine: trabaja con la base de verdad, fuera de los
  /// cuadros de la prueba.
  Future<void> letQueueFinish(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (store.saved.isNotEmpty && store.jobs.isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<List<ProcessedPart>> pages() async =>
      (await harness.container
              .read(processedRepositoryProvider)
              .partsOf(docId, sections: const {ProcessedSection.text}))
          .toNullable()!;

  final gemma = modelLabel(ChatModelOption.gemma4E4b.name);

  group('al prender el texto', () {
    testWidgets('dice qué IA lo va a ordenar y que cada palabra se comprueba', (
      tester,
    ) async {
      await setUpWith();
      await seedSource();
      await pumpSheet(tester);

      expect(find.byKey(const Key('triage-tidy')), findsNothing);
      await tapKey(tester, const Key('triage-switch-text'));

      final tidy = tester.widget<CheckboxListTile>(
        find.byKey(const Key('triage-tidy')),
      );
      expect(tidy.value, isTrue);
      expect(find.text(es.f45S2TidyToggle), findsOneWidget);
      expect(find.text(es.f45S2TidyByDevice(gemma)), findsOneWidget);
    });

    testWidgets('con «Listo», la IA lo ordena en segundo plano y la página '
        'queda ordenada, palabra por palabra igual', (tester) async {
      await setUpWith();
      await seedSource();
      await pumpSheet(tester);

      await tapKey(tester, const Key('triage-switch-text'));
      await done(tester);
      await letQueueFinish(tester);

      expect(store.saved.toSet(), {docId});
      expect(tidier.asked, isNotEmpty);
      final page = (await pages()).single;
      expect(page.edited, isTrue);
      expect(
        page.content,
        'La república romana cayó cuando César cruzó el Rubicón.\n\n'
        'El Senado lo declaró enemigo público.',
      );
      expect(checkTidiedText(_extracted, page.content).isFaithful, isTrue);
      expect(store.jobs, isEmpty);
    });

    testWidgets('con la casilla apagada, va como se extrajo y no se le pide '
        'nada a la IA', (tester) async {
      await setUpWith();
      await seedSource();
      await pumpSheet(tester);

      await tapKey(tester, const Key('triage-switch-text'));
      await tapKey(tester, const Key('triage-tidy'));
      expect(find.text(es.f45S2TidyOff), findsOneWidget);
      await done(tester);
      await tester.pumpAndSettle();

      expect(store.saved, isEmpty);
      expect(tidier.asked, isEmpty);
      expect((await pages()).single.content, _extracted);
    });

    testWidgets('si «Listo» falla, no se le pide nada a la IA', (tester) async {
      await setUpWith();
      await seedSource();
      await pumpSheet(tester);
      answer = const Failure.validation(message: 'No se pudo.');

      await tapKey(tester, const Key('triage-switch-text'));
      await done(tester);

      expect(find.byKey(const Key('triage-error')), findsOneWidget);
      expect(store.saved, isEmpty);
    });

    testWidgets('sin una IA lista, dice que va como se extrajo y cómo '
        'tenerla', (tester) async {
      await setUpWith(modelReady: false);
      await seedSource();
      await pumpSheet(tester);

      await tapKey(tester, const Key('triage-switch-text'));
      expect(find.byKey(const Key('triage-tidy')), findsNothing);
      expect(find.text(es.f45S2TidyUnavailableHint), findsOneWidget);
      await done(tester);
      await tester.pumpAndSettle();

      expect(store.saved, isEmpty);
    });

    testWidgets('lo que ya viene ordenado —una página web— va como se '
        'extrajo', (tester) async {
      await setUpWith();
      await seedSource(kind: SourceKind.webPage);
      await pumpSheet(tester);

      await tapKey(tester, const Key('triage-switch-text'));
      expect(find.byKey(const Key('triage-tidy')), findsNothing);
      expect(find.text(es.f45S2TidyNotNeeded), findsOneWidget);
      await done(tester);
      await tester.pumpAndSettle();

      expect(store.saved, isEmpty);
    });

    testWidgets('quitar el texto al volver a triar no lo ordena', (
      tester,
    ) async {
      await setUpWith();
      await seedSource();
      await harness.container.read(processSourceUseCaseProvider).call(
        'fuente',
        {
          ProcessedSection.text: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        },
      );
      await pumpSheet(
        tester,
        existing: const {ProcessedSection.text: 1},
        changes: ProcessedChange.values.toSet(),
      );

      await tapKey(tester, const Key('triage-switch-text'));
      expect(find.byKey(const Key('triage-tidy')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('triage-change-text')),
          matching: find.text(es.processedTriageChangeRemove),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('triage-tidy')), findsNothing);
      await done(tester);
      await tester.pumpAndSettle();

      expect(store.saved, isEmpty);
    });
  });

  group('se ve bien', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('con la letra al doble en 360 de ancho, en ${mode.name}, '
          'sin desbordarse', (tester) async {
        await setUpWith();
        await seedSource();
        await pumpSheet(
          tester,
          textScale: 2,
          size: const Size(360, 780),
          themeMode: mode,
        );
        await tapKey(tester, const Key('triage-switch-text'));
        await tester.ensureVisible(find.byKey(const Key('triage-tidy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(es.f45S2TidyByDevice(gemma)), findsOneWidget);
      });
    }

    testWidgets('el lector de pantalla lee la casilla con quién ordena', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setUpWith();
      await seedSource();
      await pumpSheet(tester);
      await tapKey(tester, const Key('triage-switch-text'));

      expect(
        tester.getSemantics(find.byKey(const Key('triage-tidy'))),
        isSemantics(
          label: '${es.f45S2TidyToggle}\n${es.f45S2TidyByDevice(gemma)}',
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('el aviso de cómo terminó', () {
    ProcessedTidyOutcome outcome({
      ProcessedTidyEnd end = ProcessedTidyEnd.done,
      int tidied = 0,
      Map<TidyProblem, int> kept = const {},
      int unanswered = 0,
    }) => ProcessedTidyOutcome(
      documentId: docId,
      title: 'Roma',
      end: end,
      tidied: tidied,
      kept: kept,
      unanswered: unanswered,
    );

    test('todo ordenado, una parte, nada, o sin IA', () {
      expect(
        tidyOutcomeMessage(es, outcome(tidied: 4)),
        es.f45S2TidyDone('Roma'),
      );
      expect(
        tidyOutcomeMessage(
          es,
          outcome(tidied: 3, kept: {TidyProblem.invented: 1}),
        ),
        es.f45S2TidyPartly(3, 4, 'Roma', es.f45S2ProblemInvented),
      );
      expect(
        tidyOutcomeMessage(
          es,
          outcome(kept: {TidyProblem.rewritten: 3, TidyProblem.missing: 1}),
        ),
        es.f45S2TidyKept('Roma', es.f45S2ProblemRewritten),
      );
      expect(
        tidyOutcomeMessage(es, outcome(kept: {TidyProblem.reordered: 1})),
        es.f45S2TidyKept('Roma', es.f45S2ProblemReordered),
      );
      expect(
        tidyOutcomeMessage(es, outcome(kept: {TidyProblem.missing: 2})),
        es.f45S2TidyKept('Roma', es.f45S2ProblemMissing),
      );
      expect(
        tidyOutcomeMessage(es, outcome(unanswered: 2)),
        es.f45S2TidyKept('Roma', es.f45S2ProblemNoReply),
      );
      expect(
        tidyOutcomeMessage(es, outcome(end: ProcessedTidyEnd.unavailable)),
        es.f45S2TidyUnavailable('Roma'),
      );
      // Sin ninguna página de la fuente que ordenar, no hay nada que decir.
      expect(tidyOutcomeMessage(es, outcome()), isNull);
    });

    testWidgets('se ve esté donde esté la persona, y «Ver» abre el documento', (
      tester,
    ) async {
      await setUpWith();
      await seedSource();
      final opened = <String>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                ProcessedTidyNoticeListener(onOpen: opened.add, child: child!),
            home: const Scaffold(body: Text('En otra pantalla')),
          ),
        ),
      );
      await harness.container.read(processSourceUseCaseProvider).call(
        'fuente',
        {
          ProcessedSection.text: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        },
      );

      await harness.container.read(processedTidyQueueProvider).enqueue(docId);
      await letQueueFinish(tester);

      expect(find.byKey(const Key('tidy-snack')), findsOneWidget);
      expect(find.text(es.f45S2TidyDone('Historia de Roma')), findsOneWidget);
      // Lleva su ✕ (F43, M1): tiene un botón.
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.text(es.inboxView));
      await tester.pumpAndSettle();
      expect(opened, [docId]);
    });
  });
}
