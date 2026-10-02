import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// El editor de notas con el lector flotante (F25): ofrece lo escrito, tal
/// como está, un rato después de la última letra.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 2, 10);
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
  });

  ReadableDocument? offered() =>
      harness.container.read(currentReadableProvider);

  /// Cierra el editor y deja que retire lo que ofrecía —lo retira después
  /// del cuadro en que se desmonta—: la prueba no termina con eso pendiente.
  Future<void> closeEditor(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(offered(), isNull);
  }

  testWidgets('una nota nueva, vacía, no ofrece nada; lo escrito se ofrece '
      'un rato después de la última letra', (tester) async {
    await tester.pumpWidget(harness.wrap(const BlockEditorScreen()));
    await tester.pumpAndSettle();
    expect(offered(), isNull);

    await tester.enterText(
      find.widgetWithText(TextField, es.blocksTitleHint),
      'Mi nota',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.blocksParagraphHint),
      'Algo **dicho** así.',
    );
    await tester.pump();
    expect(offered(), isNull);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    final document = offered()!;
    expect(document.id, startsWith('editor:'));
    expect(document.title, 'Mi nota');
    expect(document.segments.map((s) => (s.start, s.end, s.spoken)), [
      (0, 19, 'Algo dicho así.'),
    ]);

    await closeEditor(tester);
  });

  testWidgets('una nota que ya existe se ofrece con sus bloques, cada uno '
      'aparte', (tester) async {
    final note = KnowledgeItem(
      id: 'f25-nota',
      title: 'Una nota',
      source: Source(
        id: 'f25-nota',
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'f25-nota-bloques',
          itemId: 'f25-nota',
          kind: RenditionKind.blocks,
          content: encodeContentBlocks(const [
            ContentBlock.heading(text: 'Primero'),
            ContentBlock.bulletItem(text: 'Después'),
          ]),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    await tester.pumpWidget(
      harness.wrap(BlockEditorScreen(existingItem: note)),
    );
    await tester.pumpAndSettle();

    final document = offered()!;
    expect(document.id, 'editor:f25-nota');
    expect(document.title, 'Una nota');
    expect(document.segments.map((s) => (s.sourceKey, s.spoken)), [
      ('editor:f25-nota:0', 'Primero'),
      ('editor:f25-nota:1', 'Después'),
    ]);

    await closeEditor(tester);
  });
}
