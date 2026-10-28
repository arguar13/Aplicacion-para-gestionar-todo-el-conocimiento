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
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_cut_screen.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/library_harness.dart';

const _content = 'La primera idea. La segunda idea es larga. La tercera.';

/// «Cortar del original» (F41): la barrita de siempre con «A Procesado», lo
/// cortado marcado en el texto y en la lista viva, y «Extraer como nota» que
/// va a las notas del documento procesado y no a la Biblioteca.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    final now = DateTime(2026, 10, 27, 9);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Historia de Roma',
            source: Source(
              id: 'src-fuente',
              kind: SourceKind.document,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: _content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  });

  Future<int> itemCount() async =>
      (await harness.database.select(harness.database.knowledgeEntries).get())
          .length;

  ProcessedTriageController triage() =>
      harness.container.read(processedTriageProvider('fuente').notifier);

  Future<void> pumpCut(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => openProcessedCutScreen(context, 'fuente'),
                child: const Text('Cortar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cortar'));
    await tester.pumpAndSettle();
  }

  /// Selecciona `[base, extent)` del texto y abre la barrita.
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

  /// El color de fondo con que se ve cada tramo del texto.
  Map<String, Color?> backgrounds(WidgetTester tester) => {
    for (final span
        in tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .children!
            .cast<TextSpan>())
      span.text!: span.style?.backgroundColor,
  };

  testWidgets('abre el texto con la lista vacía que explica cómo se corta', (
    tester,
  ) async {
    await pumpCut(tester);

    expect(find.text(es.processedCutTitle), findsOneWidget);
    expect(find.byKey(const Key('processed-cut-text')), findsOneWidget);
    expect(find.text(es.processedCutHint), findsOneWidget);
  });

  testWidgets('«A Procesado» manda lo seleccionado a los fragmentos: se marca '
      'en el texto y aparece en la lista viva', (tester) async {
    await pumpCut(tester);

    await select(tester, 17, 42);
    expect(find.byKey(const Key('highlight-to-processed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('highlight-to-processed')));
    await tester.pumpAndSettle();

    expect(
      triage().triage.clipsOf(ProcessedSection.fragments).single.draft,
      const ProcessedDraft.cut(
        ProcessedAnchor(renditionId: 'rend-fuente', start: 17, end: 42),
      ),
    );
    final tray = find.byKey(const Key('processed-cut-tray'));
    expect(
      find.descendant(
        of: tray,
        matching: find.text('La segunda idea es larga.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tray,
        matching: find.text(
          '${es.processedTriageFragmentCount(1)} · '
          '${es.processedTriageNoteCount(0)}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      backgrounds(tester)['La segunda idea es larga.'],
      ProcessedCutPalette.light,
    );
  });

  testWidgets('el mismo pasaje no se corta dos veces, y lo avisa', (
    tester,
  ) async {
    await pumpCut(tester);

    for (var i = 0; i < 2; i++) {
      await select(tester, 17, 42);
      await tester.tap(find.byKey(const Key('highlight-to-processed')));
      await tester.pumpAndSettle();
    }

    expect(triage().triage.clipsOf(ProcessedSection.fragments), hasLength(1));
    expect(find.text(es.processedCutRepeated), findsOneWidget);
  });

  testWidgets('«Extraer como nota» va a las notas del documento procesado y '
      'no crea nada en la Biblioteca (decisión C)', (tester) async {
    await pumpCut(tester);
    final before = await itemCount();

    await select(tester, 0, 16);
    await tester.tap(find.byTooltip(es.detailExtractSelection));
    await tester.pumpAndSettle();

    expect(await itemCount(), before);
    expect(
      triage().triage.clipsOf(ProcessedSection.notes).single.draft,
      const ProcessedDraft.cut(
        ProcessedAnchor(renditionId: 'rend-fuente', start: 0, end: 16),
      ),
    );
    expect(find.text(es.processedCutNoteAdded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('processed-cut-tray')),
        matching: find.text('La primera idea.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('quitar un corte de la lista lo saca también del texto', (
    tester,
  ) async {
    await pumpCut(tester);
    await select(tester, 43, 54);
    await tester.tap(find.byKey(const Key('highlight-to-processed')));
    await tester.pumpAndSettle();
    final clip = triage().triage.clipsOf(ProcessedSection.fragments).single;

    await tester.tap(find.byKey(ValueKey('triage-clip-remove-${clip.id}')));
    await tester.pumpAndSettle();

    expect(triage().triage.clipsOf(ProcessedSection.fragments), isEmpty);
    expect(find.text(es.processedCutHint), findsOneWidget);
    expect(backgrounds(tester).values.whereType<Color>(), isEmpty);
  });

  testWidgets('«Listo» y Escape vuelven, y lo cortado queda en la hoja', (
    tester,
  ) async {
    await pumpCut(tester);
    await select(tester, 43, 54);
    await tester.tap(find.byKey(const Key('highlight-to-processed')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('processed-cut-done')));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedCutScreen), findsNothing);

    await tester.tap(find.text('Cortar'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedCutScreen), findsNothing);
  });

  testWidgets('fuera de «Cortar del original» la barrita es la de siempre: '
      'sin «A Procesado» y sin marcar nada', (tester) async {
    // Aunque la hoja de esa fuente tenga cortes.
    triage().cut(
      const ProcessedAnchor(renditionId: 'rend-fuente', start: 17, end: 42),
      excerpt: 'La segunda idea es larga.',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(processedTriageProvider('fuente'));
              return const DocumentReaderScreen(
                title: 'Historia de Roma',
                content: _content,
                study: (
                  itemId: 'fuente',
                  renditionId: 'rend-fuente',
                  content: _content,
                  markdown: true,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await select(tester, 0, 16);
    expect(find.byKey(const Key('highlight-toolbar-card')), findsOneWidget);
    expect(find.byKey(const Key('highlight-to-processed')), findsNothing);
    expect(backgrounds(tester).values.whereType<Color>(), isEmpty);
  });
}
