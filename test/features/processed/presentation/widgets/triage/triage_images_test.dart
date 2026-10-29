import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/stored_image.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_triage_sheet.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/triage_image_grid.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/library_harness.dart';

/// Las imágenes en la hoja «¿Qué va a Procesado?» (F41, decisión L): la
/// grilla, «Todas», «Ninguna», elegir de a una, lo que va a ocupar, de a
/// tandas, con el teclado y el lector de pantalla, y al volver a triar.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late List<String> photos;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Una imagen guardada —sin texto: una foto sin letras— con [extra] fotos
  /// más en su «Contenido», de 10 bytes cada una; la suya pesa 100.
  Future<void> seedImage({int extra = 2}) async {
    final now = DateTime(2026, 10, 28, 9);
    final own = await harness.files.save(
      bytes: Uint8List(100),
      suggestedName: 'foto.png',
      id: 'fuente',
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Una foto',
            source: Source(
              id: 'src-fuente',
              kind: SourceKind.image,
              capturedAt: now,
              originalFilePath: own,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    photos = [own];
    final db = harness.database;
    for (var i = 0; i < extra; i++) {
      final path = 'originales/fuente/contenido/f$i.jpg';
      await harness.files.saveStream(
        bytes: Stream.value(List.filled(10, 0)),
        suggestedName: 'f$i.jpg',
        id: 'fuente',
        folder: 'contenido',
      );
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'foto-$i',
              itemId: 'fuente',
              kind: RenditionKind.image,
              relativePath: Value(path),
              isPrimary: false,
              createdAt: now,
              position: Value(i),
              sizeBytes: const Value(10),
              title: Value('Foto $i'),
            ),
          );
      photos.add(path);
    }
  }

  final received = <Map<ProcessedSection, SectionEdit>>[];
  final receivedOriginals = <OriginalEdit?>[];
  setUp(() {
    received.clear();
    receivedOriginals.clear();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    Map<ProcessedSection, int> existing = const {},
    Map<ProcessedSection, SectionEdit> initial = const {},
    Set<ProcessedChange> changes = const {ProcessedChange.add},
    double textScale = 1,
    Size size = const Size(900, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showProcessedTriageSheet(
                    context,
                    sourceItemId: 'fuente',
                    existing: existing,
                    initial: initial,
                    changes: changes,
                    onDone: (edits, original) async {
                      received.add(edits);
                      receivedOriginals.add(original);
                      return null;
                    },
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Finder tile(String path) => find.byKey(Key('triage-image-$path'));

  /// Lleva [target] a la vista —la lista de la hoja arma solo lo que se ve—
  /// y lo toca.
  Future<void> tapFound(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('processed-triage-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, String path) =>
      tapFound(tester, tile(path));

  Future<void> tapKey(WidgetTester tester, String key) =>
      tapFound(tester, find.byKey(Key(key)));

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();
  }

  testWidgets('una foto sin letras ofrece sus imágenes —cuántas y cuánto '
      'pesan— y las notas, nada de texto', (tester) async {
    await seedImage();
    await pumpSheet(tester);

    expect(find.byKey(const Key('triage-section-images')), findsOneWidget);
    expect(
      find.text(es.processedTriageImagesOffer(3, '120 B')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('triage-section-notes')), findsOneWidget);
    expect(find.byKey(const Key('triage-section-text')), findsNothing);
    expect(find.text(es.processedTriageImagesChosen(0, 3)), findsOneWidget);
    for (final path in photos) {
      expect(tile(path), findsOneWidget);
    }
  });

  testWidgets('tocar una la elige, dice lo que va a ocupar, y «Listo» pide '
      'solo esa', (tester) async {
    await seedImage();
    await pumpSheet(tester);

    await tapTile(tester, photos[1]);

    expect(find.text(es.processedTriageImagesChosen(1, 3)), findsOneWidget);
    expect(
      find.text(
        es.processedTriageImagesSize(es.processedImageCount(1), '10 B'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(es.processedTriageTotalImages('10 B')),
      findsOneWidget,
    );
    await done(tester);

    expect(received.single, {
      ProcessedSection.images: SectionEdit.add(
        SectionInput.images(ImageChoice.only({photos[1]})),
      ),
    });
  });

  testWidgets('«Todas» y después soltar una pide todas menos esa; «Ninguna» '
      'no pide nada', (tester) async {
    await seedImage();
    await pumpSheet(tester);

    await tapKey(tester, 'triage-images-all');
    expect(find.text(es.processedTriageImagesChosen(3, 3)), findsOneWidget);
    await tapTile(tester, photos[0]);
    expect(find.text(es.processedTriageImagesChosen(2, 3)), findsOneWidget);
    expect(
      find.text(
        es.processedTriageImagesSize(es.processedImageCount(2), '20 B'),
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'triage-images-none');
    expect(find.text(es.processedTriageImagesChosen(0, 3)), findsOneWidget);
    final listo = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('triage-done')),
    );
    expect(listo.onPressed, isNull);

    await tapKey(tester, 'triage-images-all');
    await tapTile(tester, photos[0]);
    await done(tester);
    expect(received.single, {
      ProcessedSection.images: SectionEdit.add(
        SectionInput.images(ImageChoice.all(except: {photos[0]})),
      ),
    });
  });

  testWidgets('cada miniatura le dice al lector de pantalla cuál es y si '
      'está elegida', (tester) async {
    final semantics = tester.ensureSemantics();
    await seedImage();
    await pumpSheet(tester);

    final label = '${es.processedImagePosition(2, 3)}: Foto 0';
    expect(
      tester.getSemantics(tile(photos[1])),
      matchesSemantics(
        label: label,
        isButton: true,
        hasCheckedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tapTile(tester, photos[1]);
    expect(tester.getSemantics(tile(photos[1])), isSemantics(isChecked: true));
    semantics.dispose();
  });

  testWidgets('con el teclado: se enfoca una miniatura y se elige con '
      'Espacio', (tester) async {
    await seedImage();
    await pumpSheet(tester);

    // El foco de la miniatura es el de su `InkWell`: el más cercano por
    // encima de la imagen.
    Focus.of(
      tester.element(
        find.descendant(
          of: tile(photos[2]),
          matching: find.byType(StoredImage),
        ),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text(es.processedTriageImagesChosen(1, 3)), findsOneWidget);
  });

  testWidgets('con muchas, se arman de a tandas: la primera y «Mostrar más»', (
    tester,
  ) async {
    await seedImage(extra: 129);
    await pumpSheet(tester);

    const page = TriageImageGrid.pageSize;
    expect(tile(photos[page - 1]), findsOneWidget);
    expect(tile(photos[page]), findsNothing);
    expect(find.text(es.processedTriageImagesMore(130 - page)), findsOneWidget);

    await tapKey(tester, 'triage-images-more');
    expect(tile(photos[2 * page - 1]), findsOneWidget);
    expect(tile(photos[2 * page]), findsNothing);
    expect(
      find.text(es.processedTriageImagesMore(130 - 2 * page)),
      findsOneWidget,
    );
  });

  testWidgets('con la letra al doble en 360 de ancho no se desborda', (
    tester,
  ) async {
    await seedImage();
    await pumpSheet(tester, textScale: 2, size: const Size(360, 800));

    await tapKey(tester, 'triage-images-all');
    expect(tester.takeException(), isNull);
    expect(find.text(es.processedTriageImagesChosen(3, 3)), findsOneWidget);
  });

  testWidgets('al volver a triar: Agregar · Reemplazar · Quitar, sin '
      'Actualizar, y Quitar no necesita la grilla', (tester) async {
    await seedImage();
    await pumpSheet(
      tester,
      existing: const {ProcessedSection.images: 1},
      initial: {
        ProcessedSection.images: SectionEdit.add(
          SectionInput.images(ImageChoice.only({photos[2]})),
        ),
      },
      changes: ProcessedChange.values.toSet(),
    );

    final segmented = find.byKey(const Key('triage-change-images'));
    expect(segmented, findsOneWidget);
    expect(
      find.descendant(
        of: segmented,
        matching: find.text(es.processedTriageChangeUpdate),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: segmented,
        matching: find.text(es.processedTriageChangeRemove),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('triage-image-grid')), findsNothing);

    await done(tester);
    expect(received.single, {ProcessedSection.images: SectionEdit.remove()});
  });

  testWidgets('una página guardada ofrece su original y sus fotos: el '
      'conmutador del original, con su número, sigue a las secciones enteras, '
      'la grilla va al final, y «Va a quedar» y «Listo» llevan las dos', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 28, 9);
    final page = await harness.files.save(
      bytes: Uint8List(2048),
      suggestedName: 'pagina.html',
      id: 'fuente',
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Una página',
            source: Source(
              id: 'src-fuente',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/pagina',
              originalFilePath: page,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: 'El Senado. El foro.',
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    const photo = 'originales/fuente/contenido/foto.jpg';
    await harness.files.saveStream(
      bytes: Stream.value(List.filled(10, 0)),
      suggestedName: 'foto.jpg',
      id: 'fuente',
      folder: 'contenido',
    );
    await harness.database
        .into(harness.database.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'foto',
            itemId: 'fuente',
            kind: RenditionKind.image,
            relativePath: const Value(photo),
            isPrimary: false,
            createdAt: now,
            position: const Value(0),
            sizeBytes: const Value(10),
          ),
        );
    await pumpSheet(tester);

    final sheetList = find
        .descendant(
          of: find.byKey(const Key('processed-triage-sheet')),
          matching: find.byType(Scrollable),
        )
        .first;
    final original = find.byKey(const Key('triage-section-original'));
    final images = find.byKey(const Key('triage-section-images'));
    await tester.scrollUntilVisible(images, 120, scrollable: sheetList);
    await tester.pumpAndSettle();
    expect(original, findsOneWidget);
    expect(
      tester.getTopLeft(original).dy,
      lessThan(tester.getTopLeft(images).dy),
    );

    // El número del original es el que sigue a las secciones enteras: con
    // texto, la fuente ofrece la única que queda, el texto —el resumen, la
    // síntesis y las palabras clave ya no se trían (F43, decisión J)—.
    final whole = [
      for (final section in ProcessedSection.values)
        if (triageShapeOf(section) == TriageSectionShape.whole &&
            section == ProcessedSection.text)
          section,
    ];
    const numberKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    await tester.sendKeyEvent(numberKeys[whole.length]);
    await tester.pumpAndSettle();
    await tapTile(tester, photo);

    await tester.scrollUntilVisible(
      find.byKey(const Key('triage-preview')),
      120,
      scrollable: sheetList,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('triage-preview-chip-original')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('triage-preview-chip-images')), findsOneWidget);

    await done(tester);
    expect(received.single, {
      ProcessedSection.images: SectionEdit.add(
        const SectionInput.images(ImageChoice.only({photo})),
      ),
    });
    expect(receivedOriginals.single, const OriginalEdit(ProcessedChange.add));
  });
}
