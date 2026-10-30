import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_parts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El detalle de una fuente de la Biblioteca muestra solo su original (F45,
/// paso 3, decisión E): ni la tarjeta «Estudiar el documento», ni el texto que
/// se sacó de él, ni la fila Leer · Copiar · Más. El texto sigue guardado —lo
/// usan la búsqueda, el chat y los vínculos— y se lee, se marca y se estudia
/// en su documento procesado. Una nota propia no cambia.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 29, 10);
  const content = 'La primera frase del libro.';

  Future<LibraryHarness> pumpItem(
    WidgetTester tester, {
    required SourceKind kind,
  }) async {
    final harness = await LibraryHarness.create();
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
                content: content,
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

  for (final kind in [
    SourceKind.document,
    SourceKind.webPage,
    SourceKind.socialPost,
    SourceKind.image,
    SourceKind.audio,
    SourceKind.video,
    SourceKind.youtube,
    SourceKind.reference,
  ]) {
    testWidgets('${kind.name}: sin la tarjeta de estudiar, sin su texto y '
        'sin Leer · Copiar · Más; el texto sigue guardado', (tester) async {
      final harness = await pumpItem(tester, kind: kind);

      expect(find.byKey(const Key('study-document-card')), findsNothing);
      expect(find.byKey(const Key('study-extract-text')), findsNothing);
      expect(find.textContaining('La primera frase'), findsNothing);
      expect(find.byType(SourcePanelTile), findsNothing);
      for (final key in [
        'source-panel-read',
        'source-panel-copy',
        'source-panel-more',
        'source-panel-summarize',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      // Lista y sin audio, el panel no tiene nada que decir: no deja una
      // tarjeta vacía.
      expect(find.byKey(const Key('source-panel')), findsNothing);

      // De la Biblioteca nada se borra: sale lo que se muestra.
      final saved =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .findById('item-1'))
              .getRight()
              .toNullable()!;
      expect(
        saved.renditions.whereType<TextRendition>().single.content,
        content,
      );
    });
  }

  testWidgets('lo que está pasando con su texto se sigue diciendo: un fallo, '
      'con su «Reintentar»', (tester) async {
    final harness = await LibraryHarness.create();
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'item-1',
            title: 'Un audio',
            source: Source(
              id: 'src-1',
              kind: SourceKind.audio,
              capturedAt: now,
            ),
            processingState: ProcessingState.failed,
            createdAt: now,
            updatedAt: now,
          ),
        );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(const ItemDetailScreen(itemId: 'item-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-panel')), findsOneWidget);
    expect(find.byType(SourcePanelStatus), findsOneWidget);
    expect(find.text(es.detailRetry), findsOneWidget);
    expect(find.byType(SourcePanelTile), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SourcePanel),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
  });

  testWidgets('las fotos de una página van en «Contenido», con lo demás que '
      'trae: ya no hay tarjeta donde plegarlas', (tester) async {
    final harness = await pumpItem(tester, kind: SourceKind.webPage);
    final attachments = harness.container.read(attachmentRepositoryProvider);
    for (final (i, name) in ['coliseo.jpg', 'foro.jpg'].indexed) {
      await attachments.addAttachment(
        itemId: 'item-1',
        kind: RenditionKind.image,
        relativePath: 'originales/src-1/contenido/$name',
        position: i,
      );
    }
    await attachments.addAttachment(
      itemId: 'item-1',
      kind: RenditionKind.pdf,
      relativePath: 'originales/src-1/contenido/informe.pdf',
      position: 2,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study-extract-photos')), findsNothing);
    expect(find.text('${es.contentGroupImages} · 2'), findsOneWidget);
    expect(find.text('${es.contentGroupDocuments} · 1'), findsOneWidget);
  });

  testWidgets('una nota propia sigue mostrando su texto, con sus mosaicos', (
    tester,
  ) async {
    await pumpItem(tester, kind: SourceKind.manualNote);

    expect(find.textContaining('La primera frase'), findsOneWidget);
    expect(find.byKey(const Key('source-panel-read')), findsOneWidget);
    expect(find.byKey(const Key('source-panel-copy')), findsOneWidget);
    expect(find.byKey(const Key('study-document-card')), findsNothing);
  });
}
