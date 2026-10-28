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
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

const _content = 'La primera idea. La segunda idea es larga.';

/// «Texto extraído» mientras se corta del original para Procesado (F41): la
/// misma barrita, con «A Procesado», y lo cortado marcado encima. Contra la
/// base real del arnés.
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
            title: 'Roma',
            source: Source(id: 's', kind: SourceKind.document, capturedAt: now),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend',
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

  Future<void> pump(WidgetTester tester, {required bool cutting}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ProviderScope(
              overrides: [
                if (cutting)
                  processedCutSourceProvider.overrideWithValue('fuente'),
              ],
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(processedTriageProvider('fuente'));
                  return SingleChildScrollView(
                    child: HighlightableText(
                      itemId: 'fuente',
                      renditionId: 'rend',
                      content: _content,
                      markdown: false,
                      paints: watchStudyPaints(ref, context, 'rend'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  testWidgets('«A Procesado» corta lo seleccionado y lo marca encima', (
    tester,
  ) async {
    await pump(tester, cutting: true);

    await select(tester, 17, 42);
    await tester.tap(find.byKey(const Key('highlight-to-processed')));
    await tester.pumpAndSettle();

    final triage = harness.container.read(processedTriageProvider('fuente'));
    expect(
      triage.clipsOf(ProcessedSection.fragments).single.draft,
      const ProcessedDraft.cut(
        ProcessedAnchor(renditionId: 'rend', start: 17, end: 42),
      ),
    );
    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .cast<TextSpan>();
    expect(
      spans
          .firstWhere((span) => span.text == 'La segunda idea es larga.')
          .style
          ?.backgroundColor,
      ProcessedCutPalette.light,
    );
    // Encima de todo, con la letra oscura: se lee igual en cualquier tema.
    expect(
      spans
          .firstWhere((span) => span.text == 'La segunda idea es larga.')
          .style
          ?.color,
      ProcessedCutPalette.ink,
    );
    expect(find.text(es.processedCutRepeated), findsNothing);
  });

  testWidgets('sin cortar, la barrita es la de siempre', (tester) async {
    await pump(tester, cutting: false);

    await select(tester, 17, 42);

    expect(find.byKey(const Key('highlight-toolbar-card')), findsOneWidget);
    expect(find.byKey(const Key('highlight-to-processed')), findsNothing);
  });
}
