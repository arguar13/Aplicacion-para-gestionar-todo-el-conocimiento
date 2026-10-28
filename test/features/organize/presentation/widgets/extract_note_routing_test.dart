import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

const _content = 'La primera idea. La segunda idea es larga.';

/// «Extraer como nota» desde el texto de cualquier pantalla (F41, decisión
/// J): adónde va lo decide qué es el elemento. Contra la base real del arnés.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 27, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> save(String id, SourceKind kind) => harness.container
      .read(libraryRepositoryProvider)
      .save(
        KnowledgeItem(
          id: id,
          title: 'Elemento $id',
          source: Source(id: 's-$id', kind: kind, capturedAt: now),
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

  Future<void> pumpText(WidgetTester tester, String id) async {
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: HighlightableText(
              itemId: id,
              renditionId: 'rend-$id',
              content: _content,
              markdown: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> extract(WidgetTester tester, int base, int extent) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: base, extentOffset: extent),
      ),
      SelectionChangedCause.tap,
    );
    state.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(es.detailExtractSelection));
    await tester.pumpAndSettle();
  }

  Future<int> documents() async =>
      (await harness.database.select(harness.database.processedDocuments).get())
          .length;

  testWidgets('de una fuente en la papelera no guarda nada: lo dice y ofrece '
      'restaurarla', (tester) async {
    await save('fuente', SourceKind.document);
    await harness.container.read(libraryRepositoryProvider).delete('fuente');
    await pumpText(tester, 'fuente');

    await extract(tester, 0, 16);

    expect(await documents(), 0);
    expect(find.text(es.processedNoteSourceInTrash), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, es.trashRestore));
    await tester.pumpAndSettle();

    expect(find.text(es.processedNoteSourceRestored), findsOneWidget);
    final entry = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..where((e) => e.id.equals('fuente'))).getSingle();
    expect(entry.deletedAt, isNull);

    // Restaurada, ya acepta la nota.
    await extract(tester, 0, 16);
    expect(await documents(), 1);
    expect(find.text(es.processedNoteSaved), findsOneWidget);
  });

  testWidgets('de una nota propia sigue saliendo una nota suelta vinculada, '
      'como siempre: no tiene documento procesado', (tester) async {
    await save('mia', SourceKind.manualNote);
    await pumpText(tester, 'mia');

    await extract(tester, 17, 42);

    expect(await documents(), 0);
    final relation = await harness.database
        .select(harness.database.relations)
        .getSingle();
    expect(relation.kind, RelationKind.extractedFrom);
    expect(relation.toItemId, 'mia');
    expect((relation.sourceCharStart, relation.sourceCharEnd), (17, 42));
    expect(find.text(es.processedNoteSaved), findsNothing);
  });

  testWidgets('de una fuente, el documento procesado nace con esa sola nota', (
    tester,
  ) async {
    await save('fuente', SourceKind.document);
    await pumpText(tester, 'fuente');

    await extract(tester, 17, 42);

    final parts = await harness.database
        .select(harness.database.processedParts)
        .get();
    expect(parts.map((part) => part.section), [ProcessedSection.notes]);
    expect(parts.single.content, 'La segunda idea es larga.');
    expect(
      await harness.database.select(harness.database.relations).get(),
      isEmpty,
    );
  });
}
