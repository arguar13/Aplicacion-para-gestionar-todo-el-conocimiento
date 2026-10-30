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
import 'package:sinapsis/features/create_hub/presentation/widgets/create_button.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/source_study_line.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// Cualquier botón de Material —relleno, tonal, con borde, de texto—:
/// `find.byType` busca el tipo exacto, y cada uno es una subclase.
final Finder _anyButton = find.byWidgetPredicate(
  (widget) => widget is ButtonStyleButton,
  description: 'un botón',
);

/// La fuente de la Biblioteca queda de consulta (F41, decisión K): su detalle
/// deja de ofrecer lo que es estudiarla —se estudia en su documento
/// procesado—, y muestra solo su original (F45, paso 3). Una nota propia no
/// cambia.
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
    testWidgets('${kind.name}: sin «Resumir», sin la tarjeta de estudiar, sin '
        'Mapa, sin tarjetas, sin lo de la IA, sin derivado ni quiz; con la '
        'línea que lleva a estudiarlo, que sin documento no dibuja nada', (
      tester,
    ) async {
      await harness.saveTextSource('fuente', title: 'Roma', kind: kind);
      await openDetail(tester, 'fuente');

      expect(find.byKey(const Key('source-panel-summarize')), findsNothing);
      expect(find.byType(LocalGraphPanel), findsNothing);
      expect(find.byType(FlashcardSection), findsNothing);
      expect(find.byType(AiOrganizedLine), findsNothing);
      // Ni «Crear» (F45, paso 7b): lo que se crea sale de su procesado.
      expect(find.byType(CreateButton), findsNothing);
      expect(find.byType(SourceStudyLine), findsOneWidget);

      // Ni la tarjeta de estudiar (F45, paso 3): se marca y se estudia en
      // Procesado.
      expect(find.byKey(const Key('study-document-card')), findsNothing);
      expect(find.byKey(const Key('study-toggle-summary')), findsNothing);
      expect(find.byKey(const Key('source-panel-read')), findsNothing);
    });
  }

  testWidgets('una cita sigue llevando al pasaje: la lectura de una fuente ya '
      'no se abre desde su detalle, pero sí desde lo que la cita', (
    tester,
  ) async {
    const text = 'La república romana cayó. César cruzó el Rubicón.';
    await harness.saveTextSource('fuente', title: 'Roma');
    await pumpApp(tester, harness);
    final start = text.indexOf('César');
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.reading('fuente', start: start, end: start + 5),
    );

    expect(find.byType(ReadingScreen), findsOneWidget);
    expect(find.textContaining('Rubicón'), findsWidgets);
  });

  testWidgets('una nota propia no cambia: «Resumir», sus tarjetas, lo de la '
      'IA y «Crear» —el derivado, el quiz y lo demás, en un solo lugar (F45, '
      'paso 7b)—; Mapa no tiene, porque el grafo lee solo lo procesado (F41, '
      'paso 6)', (tester) async {
    await saveNote('nota');
    await openDetail(tester, 'nota');

    expect(find.byKey(const Key('source-panel-summarize')), findsOneWidget);
    expect(find.byType(LocalGraphPanel), findsNothing);
    expect(find.byType(FlashcardSection), findsOneWidget);
    expect(find.byType(AiOrganizedLine), findsOneWidget);
    final create = find.byType(CreateButton);
    expect(create, findsOneWidget);
    expect(tester.widget<CreateButton>(create).target.processed, isFalse);
    expect(find.byKey(const Key('inbox-standing-card')), findsNothing);
    expect(find.text(es.sourceStudyInProcessed), findsNothing);
  });

  group('triar se ofrece una sola vez, en la tarjeta «Bandeja» (F45, paso '
      '7c)', () {
    final card = find.byKey(const Key('inbox-standing-card'));
    final line = find.byType(SourceStudyLine);

    /// Cuántos botones del detalle llevan a triar la fuente, y dónde.
    void expectTriageOnceInCard(String label) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
      for (final other in [es.inboxTriageNow, es.processedRetriage]) {
        if (other == label) continue;
        expect(find.text(other), findsNothing, reason: other);
      }
      expect(find.descendant(of: line, matching: _anyButton), findsNothing);
    }

    testWidgets('en la Bandeja y sin documento: solo «Triar ahora»', (
      tester,
    ) async {
      await harness.saveTextSource('fuente', title: 'Roma');
      await openDetail(tester, 'fuente');

      expectTriageOnceInCard(es.inboxTriageNow);
      expect(find.text(es.sourceStudyInProcessed), findsNothing);
    });

    testWidgets('triada y sin documento: «Volver a triar» una sola vez', (
      tester,
    ) async {
      await harness.saveTextSource('fuente', title: 'Roma');
      await harness.markTriaged('fuente');
      await openDetail(tester, 'fuente');

      expectTriageOnceInCard(es.processedRetriage);
      expect(find.text(es.sourceStudyInProcessed), findsNothing);
    });

    testWidgets('con documento: la línea, solo «Estudiarlo en Procesado»; '
        'triar, en la tarjeta', (tester) async {
      await harness.saveTextSource('fuente', title: 'Roma');
      await harness.processTextAndNotes('fuente');
      await harness.markTriaged('fuente');
      await openDetail(tester, 'fuente');

      expect(find.text(es.processedRetriage), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text(es.processedRetriage)),
        findsOneWidget,
      );
      expect(find.descendant(of: line, matching: _anyButton), findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.text(es.sourceStudyOpen)),
        findsOneWidget,
      );
    });
  });
}
