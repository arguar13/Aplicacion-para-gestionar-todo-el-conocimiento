import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/memory_study_repository.dart';

/// El detalle de un documento (F21, decisión A): lo principal es el
/// original; el texto extraído queda plegado, porque existe para la
/// búsqueda, el chat, las tarjetas y el quiz, no para leerlo ahí.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 29, 10);

  Future<LibraryHarness> pumpItem(
    WidgetTester tester, {
    required SourceKind kind,
    List<Override> extraOverrides = const [],
  }) async {
    final harness = await LibraryHarness.create(extraOverrides: extraOverrides);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'item-1',
            title: 'Un libro',
            source: Source(id: 'src-1', kind: kind, capturedAt: now),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'r1',
                itemId: 'item-1',
                kind: RenditionKind.markdown,
                content: 'La primera frase del libro.',
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'item-1')),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('el texto extraído de un documento empieza plegado, en el '
      '«Extraer texto» de la tarjeta de estudiar (F36), y se abre si se lo '
      'pide', (tester) async {
    await pumpItem(tester, kind: SourceKind.document);

    expect(find.text(es.detailExtractedTextTitle), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('study-document-card')),
        matching: find.text(es.studyExtractText),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('La primera frase'), findsNothing);

    await tester.tap(find.text(es.studyExtractText));
    await tester.pumpAndSettle();

    expect(find.textContaining('La primera frase'), findsOneWidget);
  });

  testWidgets('"Resumir" del panel prende el resumen de la tarjeta de '
      'estudiar (F36) y analiza lo que falta, sin el diálogo del párrafo', (
    tester,
  ) async {
    final analysis = FakeStudyAnalysis();
    final harness = await pumpItem(
      tester,
      kind: SourceKind.document,
      extraOverrides: [
        studyRepositoryProvider.overrideWithValue(
          MemoryStudyRepository(DocumentStudy.notStarted),
        ),
        studyAnalysisProvider.overrideWith((ref, id) => analysis),
        languageModelStatusCheckProvider.overrideWithValue(
          ({bool background = false}) async =>
              const LanguageModelReady(provider: AiProvider.gemma),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('source-panel-summarize')));
    await tester.pumpAndSettle();

    expect(
      harness.container.read(studyViewProvider('r1')).layer,
      StudyLayer.summary,
    );
    expect(analysis.starts, [
      (content: 'La primera frase del libro.', markdown: false),
    ]);
    expect(find.byType(AlertDialog), findsNothing);
    final summary = tester.widget<FilterChip>(
      find
          .descendant(
            of: find.byKey(const Key('study-toggle-summary')),
            matching: find.byType(FilterChip),
          )
          .first,
    );
    expect(summary.selected, isTrue);
  });

  testWidgets('lo que no es un documento se sigue mostrando entero', (
    tester,
  ) async {
    await pumpItem(tester, kind: SourceKind.webPage);

    expect(find.text(es.detailExtractedTextTitle), findsNothing);
    expect(find.text(es.studyExtractText), findsNothing);
    expect(find.textContaining('La primera frase'), findsOneWidget);
    // Una página web también se estudia, con su propia tarjeta.
    expect(find.text(es.studyCardTitleWebPage), findsOneWidget);
  });
}
