import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_viewer.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/stored_image.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/library_harness.dart';
import '../../processed_ui_fixture.dart';

/// La galería del documento procesado (F41, decisión L): sus imágenes en
/// miniatura, a pantalla completa con zoom y pasando de una a otra, y quitar
/// una con «Deshacer».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late String documentId;

  setUp(() async {
    harness = await LibraryHarness.create();
    await harness.saveImageSource('foto');
    documentId = await harness.process('foto', {
      ProcessedSection.images: SectionEdit.add(
        const SectionInput.images(ImageChoice.all()),
      ),
    });
  });

  Future<List<ProcessedImage>> gallery() async =>
      (await harness.container
              .read(processedRepositoryProvider)
              .imagesOf(documentId))
          .getRight()
          .toNullable()!;

  Future<void> open(WidgetTester tester) async {
    await pumpApp(tester, harness);
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.processedDocument(documentId),
    );
  }

  Finder tile(ProcessedImage image) =>
      find.byKey(Key('processed-image-${image.renditionId}'));

  testWidgets('la sección Imágenes muestra la galería desplegada, en '
      'miniatura', (tester) async {
    final images = await gallery();
    await open(tester);

    final section = find.byKey(const Key('processed-section-images'));
    expect(section, findsOneWidget);
    expect(
      find.descendant(
        of: section,
        matching: find.text(es.processedImageCount(3)),
      ),
      findsOneWidget,
    );
    for (final image in images) {
      expect(tile(image), findsOneWidget);
    }
    // Cada una se decodifica al tamaño en que se ve, nunca entera.
    expect(find.byType(StoredImage), findsNWidgets(3));
    for (final widget in tester.widgetList<StoredImage>(
      find.byType(StoredImage),
    )) {
      expect(widget.decodeWidth, lessThan(1000));
    }
    final decoded = tester.widgetList<Image>(
      find.descendant(
        of: find.byType(StoredImage),
        matching: find.byType(Image),
      ),
    );
    expect(decoded, hasLength(3));
    for (final image in decoded) {
      expect(image.image, isA<ResizeImage>());
    }
  });

  testWidgets('tocar una la abre a pantalla completa; se pasa de una a otra '
      'con los botones y las flechas, y Escape vuelve', (tester) async {
    final images = await gallery();
    await open(tester);

    await tester.tap(tile(images[0]));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedImageViewerScreen), findsOneWidget);
    expect(find.text(es.processedImagePosition(1, 3)), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip(es.processedImageNext));
    await tester.pumpAndSettle();
    expect(find.text(es.processedImagePosition(2, 3)), findsOneWidget);
    expect(find.text('Foto 0'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text(es.processedImagePosition(3, 3)), findsOneWidget);
    // En la última no hay siguiente.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text(es.processedImagePosition(2, 3)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedImageViewerScreen), findsNothing);
  });

  testWidgets('quitar una desde la pantalla completa, con «Deshacer»', (
    tester,
  ) async {
    final before = await gallery();
    await open(tester);
    await tester.tap(tile(before[1]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('processed-image-remove')));
    await tester.pumpAndSettle();

    expect(find.text(es.processedImageRemoved), findsOneWidget);
    expect(await gallery(), hasLength(2));
    expect(find.text(es.processedImagePosition(2, 2)), findsOneWidget);

    await tester.tap(find.text(es.trashUndo));
    await tester.pumpAndSettle();
    expect(await gallery(), before);
    expect(find.text(es.processedImagePosition(2, 3)), findsOneWidget);
  });

  testWidgets('con el teclado: Suprimir sobre la miniatura enfocada la quita', (
    tester,
  ) async {
    final before = await gallery();
    await open(tester);

    Focus.of(
      tester.element(
        find.descendant(
          of: tile(before[2]),
          matching: find.byType(StoredImage),
        ),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(find.text(es.processedImageRemoved), findsOneWidget);
    expect(
      [for (final i in await gallery()) i.renditionId],
      [before[0].renditionId, before[1].renditionId],
    );
  });

  testWidgets('para el lector de pantalla, cada una dice cuál es y ofrece '
      '«Quitar de Procesado»', (tester) async {
    final semantics = tester.ensureSemantics();
    final images = await gallery();
    await open(tester);

    expect(
      tester.getSemantics(tile(images[1])),
      isSemantics(
        label: '${es.processedImagePosition(2, 3)}: Foto 0',
        isButton: true,
        hasTapAction: true,
        customActions: [CustomSemanticsAction(label: es.processedImageRemove)],
      ),
    );
    semantics.dispose();
  });

  testWidgets('quitar la última cierra la pantalla completa', (tester) async {
    await harness.process('foto', {
      ProcessedSection.images: SectionEdit.replace(
        SectionInput.images(
          ImageChoice.only({(await gallery()).first.sourceFilePath}),
        ),
      ),
    });
    final only = (await gallery()).single;
    await open(tester);
    await tester.tap(tile(only));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('processed-image-remove')));
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedImageViewerScreen), findsNothing);
    expect(find.byKey(const Key('processed-section-images')), findsNothing);
  });
}
