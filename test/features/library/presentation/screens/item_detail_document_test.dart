import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El detalle de un documento (F21, decisión A): lo principal es el
/// original; el texto extraído queda plegado, porque existe para la
/// búsqueda, el chat, las tarjetas y el quiz, no para leerlo ahí.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 29, 10);

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

  testWidgets('el texto extraído de un documento empieza plegado, y se '
      'abre si se lo pide', (tester) async {
    await pumpItem(tester, kind: SourceKind.document);

    expect(find.text(es.detailExtractedTextTitle), findsOneWidget);
    expect(find.textContaining('La primera frase'), findsNothing);

    await tester.tap(find.text(es.detailExtractedTextTitle));
    await tester.pumpAndSettle();

    expect(find.textContaining('La primera frase'), findsOneWidget);
  });

  testWidgets('lo que no es un documento se sigue mostrando entero', (
    tester,
  ) async {
    await pumpItem(tester, kind: SourceKind.webPage);

    expect(find.text(es.detailExtractedTextTitle), findsNothing);
    expect(find.textContaining('La primera frase'), findsOneWidget);
  });
}
