import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// La vista de lectura con el lector flotante (F25): ofrece su texto, con
/// la línea que se lee en amarillo.
void main() {
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

  Future<String> save(SourceKind kind, String content) async {
    const id = 'f25-lectura';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Un ensayo',
            source: Source(id: id, kind: kind, capturedAt: now),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: '$id-texto',
                itemId: id,
                kind: RenditionKind.plainText,
                content: content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    return id;
  }

  testWidgets('ofrece su texto, línea por línea, y la que se lee se ve en '
      'amarillo', (tester) async {
    final id = await save(SourceKind.webPage, 'El primero.\nEl **segundo**.');
    await tester.pumpWidget(harness.wrap(ReadingScreen(itemId: id)));
    await tester.pumpAndSettle();

    final document = offered()!;
    expect(document.id, 'reading:$id');
    expect(document.title, 'Un ensayo');
    expect(document.segments, [
      ReadableSegment(
        sourceKey: '$id-texto',
        start: 0,
        end: 11,
        spoken: 'El primero.',
      ),
      ReadableSegment(
        sourceKey: '$id-texto',
        start: 12,
        end: 27,
        spoken: 'El segundo.',
      ),
    ]);

    (harness.container.read(readAloudControllerProvider.notifier)
            as FakeReadAloudController)
        .readAt(document, 1);
    await tester.pump();
    expect(readAloudHighlights(tester), ['El segundo.']);
  });

  testWidgets('una transcripción se ofrece sin las marcas de tiempo', (
    tester,
  ) async {
    final id = await save(SourceKind.youtube, '[0:00] hola\n[1:02:07] chau');
    await tester.pumpWidget(harness.wrap(ReadingScreen(itemId: id)));
    await tester.pumpAndSettle();

    expect(offered()!.segments.map((s) => s.spoken), ['hola', 'chau']);
  });

  // «Leer» en una nota propia de bloques (F46, paso 5j): «Escuchar» la lee
  // bloque por bloque, como su detalle.
  testWidgets('una nota de bloques se ofrece bloque por bloque, sin sus '
      'marcas, y lo que suena se ve', (tester) async {
    const id = 'f46-nota';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Mis apuntes',
            source: Source(
              id: id,
              kind: SourceKind.manualNote,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: '$id-bloques',
                itemId: id,
                kind: RenditionKind.blocks,
                content: encodeContentBlocks(const [
                  ContentBlock.heading(text: 'Roma'),
                  ContentBlock.paragraph(text: 'Fue **fundada** en el 753.'),
                ]),
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    await tester.pumpWidget(harness.wrap(const ReadingScreen(itemId: id)));
    await tester.pumpAndSettle();

    final document = offered()!;
    expect(document.id, 'reading:$id');
    expect(
      [for (final s in document.segments) (s.sourceKey, s.spoken)],
      [
        ('blocks:$id-bloques:0', 'Roma'),
        ('blocks:$id-bloques:1', 'Fue fundada en el 753.'),
      ],
    );

    (harness.container.read(readAloudControllerProvider.notifier)
            as FakeReadAloudController)
        .readAt(document, 1);
    await tester.pump();
    expect(readAloudHighlights(tester), ['Fue fundada en el 753.']);
  });
}
