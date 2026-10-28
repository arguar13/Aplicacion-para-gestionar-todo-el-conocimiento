import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_cut_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_triage_sheet.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/library_harness.dart';

const _content = 'La primera idea. La segunda idea es larga. La tercera.';

/// La hoja «¿Qué va a Procesado?» (F41): qué ofrece, la vista previa en vivo,
/// lo que arma para «Listo», el teclado y el contrato con «Volver a triar».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> seedSource({String id = 'fuente', bool summary = true}) async {
    final now = DateTime(2026, 10, 27, 9);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Historia de Roma',
            source: Source(
              id: 'src-$id',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/roma',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.plainText,
                content: _content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    if (summary) {
      await harness.container
          .read(studyRepositoryProvider)
          .addUserMark(
            renditionId: 'rend-$id',
            content: _content,
            kind: StudyMarkKind.summary,
            start: 0,
            end: 16,
          );
    }
  }

  /// Lo que recibió «Listo», y lo que contesta.
  final received = <Map<ProcessedSection, SectionEdit>>[];
  Failure? answer;
  bool? closedWith;

  setUp(() {
    received.clear();
    answer = null;
    closedWith = null;
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    Map<ProcessedSection, int> existing = const {},
    Map<ProcessedSection, SectionEdit> initial = const {},
    Set<ProcessedChange> changes = const {ProcessedChange.add},
    double textScale = 1,
    bool still = false,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(900, 1600),
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: still,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    closedWith = await showProcessedTriageSheet(
                      context,
                      sourceItemId: 'fuente',
                      existing: existing,
                      initial: initial,
                      changes: changes,
                      onDone: (edits) async {
                        received.add(edits);
                        return answer;
                      },
                    );
                  },
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

  ButtonStyleButton done(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.byKey(const Key('triage-done')));

  SwitchListTile switchOf(WidgetTester tester, ProcessedSection section) =>
      tester.widget<SwitchListTile>(
        find.byKey(Key('triage-switch-${section.name}')),
      );

  Future<void> toggle(WidgetTester tester, ProcessedSection section) async {
    final target = find.byKey(Key('triage-switch-${section.name}'));
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('processed-triage-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('ofrece lo de la fuente y lo tuyo, y sin nada elegido «Listo» '
      'está apagado y dice por qué', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    expect(find.text(es.processedTriageTitle), findsOneWidget);
    expect(find.text('Historia de Roma'), findsOneWidget);
    for (final section in ProcessedSection.values) {
      expect(
        find.byKey(Key('triage-section-${section.name}')),
        findsOneWidget,
        reason: section.name,
      );
    }
    expect(find.text(es.processedTriagePreviewEmpty), findsOneWidget);
    expect(done(tester).onPressed, isNull);
    expect(find.text(es.processedTriageNothingChosen), findsOneWidget);
    // La sección apagada dice lo que trae la fuente.
    expect(find.text(es.processedTriageSentenceCount(1)), findsOneWidget);
  });

  testWidgets('prender el texto y el resumen muestra, en vivo, cuántas partes '
      'y palabras va a tener cada uno, y «Listo» manda lo pedido y cierra', (
    tester,
  ) async {
    await seedSource();
    await pumpSheet(tester);

    await toggle(tester, ProcessedSection.text);
    expect(
      find.text(
        '${es.processedTriagePageCount(1)} · '
        '${es.processedTriageWordCount(10)}',
      ),
      findsOneWidget,
    );
    await toggle(tester, ProcessedSection.summary);
    expect(
      find.text(
        '${es.processedTriageSentenceCount(1)} · '
        '${es.processedTriageWordCount(3)}',
      ),
      findsOneWidget,
    );
    expect(find.text(es.processedTriageTotalWords(13)), findsOneWidget);
    expect(
      find.byKey(const Key('triage-preview-chip-summary')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();

    expect(received.single, {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      ProcessedSection.summary: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    });
    expect(closedWith, isTrue);
    expect(find.text(es.processedTriageTitle), findsNothing);
  });

  testWidgets('apagar una sección la saca de lo pedido y de la vista previa', (
    tester,
  ) async {
    await seedSource();
    await pumpSheet(tester);

    await toggle(tester, ProcessedSection.text);
    await toggle(tester, ProcessedSection.text);

    expect(find.text(es.processedTriagePreviewEmpty), findsOneWidget);
    expect(done(tester).onPressed, isNull);
  });

  testWidgets('sin síntesis todavía, ofrece los dos caminos de la tarjeta de '
      'estudiar y su interruptor espera', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    final synthesis = find.byKey(const Key('triage-section-synthesis'));
    expect(
      find.descendant(
        of: synthesis,
        matching: find.byKey(const Key('study-suggestion-synthesis')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: synthesis,
        matching: find.byKey(const Key('study-suggest-manual')),
      ),
      findsOneWidget,
    );
    expect(switchOf(tester, ProcessedSection.synthesis).onChanged, isNull);
    // El resumen ya tiene: no ofrece armarlo.
    expect(find.byKey(const Key('study-suggestion-summary')), findsNothing);
  });

  testWidgets('«Elegir a mano» prende la sección, pasa a elegir oraciones y '
      'abre el texto para tocarlas', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('triage-section-synthesis')),
        matching: find.byKey(const Key('study-suggest-manual')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedCutScreen), findsOneWidget);
    expect(
      harness.container.read(studyViewProvider('rend-fuente')).pick,
      StudyMarkKind.synthesis,
    );
    expect(
      harness.container
          .read(processedTriageProvider('fuente'))
          .includes(ProcessedSection.synthesis),
      isTrue,
    );
  });

  testWidgets('una nota escrita entra a la lista, se cuenta y se quita', (
    tester,
  ) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('triage-write-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('triage-note-field')),
      '  Roma creció por sus caminos.  ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('triage-note-add')));
    await tester.pumpAndSettle();

    expect(find.text('Roma creció por sus caminos.'), findsOneWidget);
    expect(
      find.text(
        '${es.processedTriageNoteCount(1)} · '
        '${es.processedTriageWordCount(5)}',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(es.processedCutRemove));
    await tester.pumpAndSettle();

    expect(find.text('Roma creció por sus caminos.'), findsNothing);
    expect(done(tester).onPressed, isNull);
  });

  testWidgets('una nota en blanco no se puede agregar', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('triage-write-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('triage-note-field')), '   ');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('triage-note-add')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('si «Listo» falla, la hoja queda abierta con lo elegido y dice '
      'por qué', (tester) async {
    await seedSource();
    answer = const Failure.validation(message: 'No se pudo guardar.');
    await pumpSheet(tester);

    await toggle(tester, ProcessedSection.text);
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();

    expect(find.text(es.processedTriageTitle), findsOneWidget);
    expect(find.byKey(const Key('triage-error')), findsOneWidget);
    expect(switchOf(tester, ProcessedSection.text).value, isTrue);
    expect(closedWith, isNull);
  });

  testWidgets('con el teclado: el número prende la sección, Ctrl+Enter es '
      '«Listo» y Escape cierra sin guardar', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    expect(switchOf(tester, ProcessedSection.text).value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(switchOf(tester, ProcessedSection.summary).value, isTrue);
    // La síntesis no tiene nada todavía: su número no la prende.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(switchOf(tester, ProcessedSection.synthesis).value, isFalse);
    expect(find.text(es.processedTriageKeysHint(3)), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(received.single.keys, {
      ProcessedSection.text,
      ProcessedSection.summary,
    });
    expect(closedWith, isTrue);
  });

  testWidgets('Escape cierra la hoja sin mandar nada', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text(es.processedTriageTitle), findsNothing);
    expect(received, isEmpty);
    expect(closedWith, isFalse);
  });

  testWidgets('C abre «Cortar del original»', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedCutScreen), findsOneWidget);
  });

  testWidgets('lo cortado vuelve con la hoja: se lista en Fragmentos y va '
      'en lo pedido', (tester) async {
    await seedSource();
    await pumpSheet(tester);

    harness.container
        .read(processedTriageProvider('fuente').notifier)
        .cut(
          const ProcessedAnchor(renditionId: 'rend-fuente', start: 17, end: 42),
          excerpt: _content.substring(17, 42),
        );
    await tester.pumpAndSettle();

    expect(find.text(_content.substring(17, 42)), findsOneWidget);
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();
    expect(received.single, {
      ProcessedSection.fragments: SectionEdit.add(
        const SectionInput.drafts([
          ProcessedDraft.cut(
            ProcessedAnchor(renditionId: 'rend-fuente', start: 17, end: 42),
          ),
        ]),
      ),
    });
  });

  group('el contrato con «Volver a triar» (paso 4)', () {
    testWidgets('con lo que el documento ya tiene, cada sección ofrece '
        'agregar, actualizar, reemplazar o quitar, y arranca con lo pedido', (
      tester,
    ) async {
      await seedSource();
      await pumpSheet(
        tester,
        existing: const {ProcessedSection.summary: 3},
        initial: {ProcessedSection.summary: SectionEdit.update()},
        changes: ProcessedChange.values.toSet(),
      );

      expect(switchOf(tester, ProcessedSection.summary).value, isTrue);
      final segmented = find.byKey(const Key('triage-change-summary'));
      expect(segmented, findsOneWidget);
      for (final label in [
        es.processedTriageChangeAdd,
        es.processedTriageChangeUpdate,
        es.processedTriageChangeReplace,
        es.processedTriageChangeRemove,
      ]) {
        expect(
          find.descendant(of: segmented, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      // Lo que no tiene nada todavía solo se agrega: no hay qué elegir.
      await toggle(tester, ProcessedSection.text);
      expect(find.byKey(const Key('triage-change-text')), findsNothing);

      await tester.tap(
        find.descendant(
          of: segmented,
          matching: find.text(es.processedTriageChangeReplace),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('triage-done')));
      await tester.pumpAndSettle();

      expect(
        received.single[ProcessedSection.summary],
        SectionEdit.replace(const SectionInput.fromSource()),
      );
    });

    testWidgets('los pasajes que trae sin su texto se leen de la fuente', (
      tester,
    ) async {
      await seedSource();
      await pumpSheet(
        tester,
        existing: const {ProcessedSection.fragments: 1},
        initial: {
          ProcessedSection.fragments: SectionEdit.add(
            const SectionInput.drafts([
              ProcessedDraft.cut(
                ProcessedAnchor(renditionId: 'rend-fuente', start: 43, end: 54),
              ),
            ]),
          ),
        },
        changes: ProcessedChange.values.toSet(),
      );

      expect(find.text('La tercera.'), findsOneWidget);
    });
  });

  group('se ve bien', () {
    testWidgets('con la letra al doble, en un teléfono angosto, sin '
        'desbordarse', (tester) async {
      await seedSource();
      await pumpSheet(tester, textScale: 2, size: const Size(360, 780));

      await toggle(tester, ProcessedSection.text);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('processed-triage-sheet')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('triage-preview')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('processed-triage-sheet')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('triage-preview-chip-text')), findsOneWidget);
    });

    testWidgets('sin animaciones y en modo oscuro', (tester) async {
      await seedSource();
      await pumpSheet(tester, still: true, themeMode: ThemeMode.dark);

      expect(find.text(es.processedTriageTitle), findsOneWidget);
      await toggle(tester, ProcessedSection.text);
      expect(tester.takeException(), isNull);
    });
  });
}
