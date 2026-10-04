import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/item_thumbnail.dart';
import 'package:sinapsis/core/domain/services/item_thumbnail_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';

import '../../../../support/library_harness.dart';

/// La miniatura de 40×40 de una fila de la Biblioteca se decodifica a su
/// tamaño: decodificar la foto entera eran unos 48 MB por fila con una foto
/// de 12 megapíxeles.
void main() {
  final item = KnowledgeItem(
    id: 'foto',
    title: 'Una foto',
    source: Source(
      id: 'src-foto',
      kind: SourceKind.image,
      capturedAt: DateTime(2026, 10, 4),
      originalFilePath: 'originales/src-foto/foto.jpg',
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 10, 4),
    updatedAt: DateTime(2026, 10, 4),
  );

  /// Un PNG válido de 1×1.
  final png = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  Future<ImageProvider> thumbnailImage(
    WidgetTester tester,
    ItemThumbnail thumbnail,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final harness = await LibraryHarness.create(
      extraOverrides: [
        itemThumbnailProvider.overrideWith((ref, item) async => thumbnail),
      ],
    );
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: LibraryItemCard(item: item, onTap: () {}),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<Image>(find.byType(Image)).image;
  }

  testWidgets('una foto del disco se decodifica al doble de su recuadro', (
    tester,
  ) async {
    final image = await thumbnailImage(
      tester,
      const ItemThumbnailFile('/disco/foto.jpg'),
    );

    // 40 puntos × 3 de densidad × 2.
    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 240);
  });

  testWidgets('una foto en memoria también', (tester) async {
    final image = await thumbnailImage(tester, ItemThumbnailBytes(png));

    expect(image, isA<ResizeImage>());
    expect((image as ResizeImage).width, 240);
  });
}
