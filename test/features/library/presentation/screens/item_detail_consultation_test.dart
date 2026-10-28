import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organized_line.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/generate_quiz_button.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/features/processed/presentation/widgets/source_study_line.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// La fuente de la Biblioteca queda de consulta (F41, decisión K): su detalle
/// deja de ofrecer lo que es estudiarla —se estudia en su documento
/// procesado—. Una nota propia no cambia.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        // Lo que la IA ya organizó, a la vista donde corresponda.
        aiItemSummaryProvider.overrideWith(
          (ref, id) => const AiItemSummary(undone: true),
        ),
      ],
    );
  });

  Future<void> openDetail(WidgetTester tester, String id) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail(id));
    expect(find.byType(ItemDetailScreen), findsOneWidget);
  }

  Future<void> saveNote(String id) async {
    final at = DateTime(2026, 10, 28, 9);
    final saved = await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Mi nota',
            source: Source(id: id, kind: SourceKind.manualNote, capturedAt: at),
            processingState: ProcessingState.ready,
            createdAt: at,
            updatedAt: at,
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.plainText,
                content: 'Una idea mía sobre Roma.',
                isPrimary: true,
                createdAt: at,
              ),
            ],
          ),
        );
    saved.getOrElse((failure) => throw StateError('$failure'));
  }

  for (final kind in [
    SourceKind.webPage,
    SourceKind.document,
    SourceKind.video,
    SourceKind.audio,
    SourceKind.socialPost,
    SourceKind.image,
  ]) {
    testWidgets('${kind.name}: sin «Resumir», sin el resumen, la síntesis ni '
        'las palabras clave para leer, sin Mapa, sin tarjetas, sin lo de la '
        'IA, sin derivado ni quiz; con la línea que lleva a estudiarlo', (
      tester,
    ) async {
      await harness.saveTextSource('fuente', title: 'Roma', kind: kind);
      await openDetail(tester, 'fuente');

      expect(find.byKey(const Key('source-panel-summarize')), findsNothing);
      expect(find.byType(LocalGraphPanel), findsNothing);
      expect(find.byType(FlashcardSection), findsNothing);
      expect(find.byType(AiOrganizedLine), findsNothing);
      expect(find.byType(GenerateQuizButton), findsNothing);
      expect(find.byType(GenerateDerivedNoteButton), findsNothing);
      expect(find.byType(SourceStudyLine), findsOneWidget);

      // La tarjeta de estudiar sigue: marca el original y trae su texto.
      expect(find.byType(StudyDocumentCard), findsOneWidget);
      expect(find.byKey(const Key('study-toggle-summary')), findsOneWidget);
      expect(find.byKey(const Key('study-extract-text')), findsOneWidget);
      for (final key in [
        'study-extract-summary',
        'study-extract-synthesis',
        'study-extract-keywords',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(find.text(es.studyExtractSummary), findsNothing);
    });
  }

  testWidgets('una nota propia no cambia: «Resumir», sus tarjetas, lo de la '
      'IA, el derivado y el quiz; Mapa no tiene, porque el grafo lee solo lo '
      'procesado (F41, paso 6)', (tester) async {
    await saveNote('nota');
    await openDetail(tester, 'nota');

    expect(find.byKey(const Key('source-panel-summarize')), findsOneWidget);
    expect(find.byType(LocalGraphPanel), findsNothing);
    expect(find.byType(FlashcardSection), findsOneWidget);
    expect(find.byType(AiOrganizedLine), findsOneWidget);
    expect(find.byType(GenerateQuizButton), findsOneWidget);
    expect(find.byType(GenerateDerivedNoteButton), findsOneWidget);
    expect(find.text(es.sourceStudyTriage), findsNothing);
    expect(find.text(es.sourceStudyInProcessed), findsNothing);
  });
}
