import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/content_trash/presentation/providers/content_trash_providers.dart';
import 'package:sinapsis/features/content_trash/presentation/widgets/content_trash_section.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Lo que se soltó de un elemento, en su detalle (F30, decisión 68): qué es,
/// cuánto pesa, hasta cuándo, y «Recuperar».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 1, 9);

  setUp(() async {
    harness = await LibraryHarness.create(now: now);
  });

  Future<void> seedBook() async {
    final path = await harness.files.save(
      bytes: Uint8List(2 * 1024 * 1024),
      suggestedName: 'roma.pdf',
      id: 'libro',
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'libro',
            title: 'Historia de Roma',
            source: Source(
              id: 'libro',
              kind: SourceKind.document,
              capturedAt: now,
              originalFilePath: path,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'texto',
                itemId: 'libro',
                kind: RenditionKind.plainText,
                content: 'Roma no se hizo en un día.',
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(const Scaffold(body: ContentTrashSection(itemId: 'libro'))),
    );
    await tester.pumpAndSettle();
  }

  Future<int> trashedRows() async =>
      (await harness.database.select(harness.database.trashedContents).get())
          .length;

  testWidgets('sin nada en la papelera no dibuja nada', (tester) async {
    await seedBook();

    await pumpSection(tester);

    expect(find.byKey(const Key('content-trash-section')), findsNothing);
  });

  testWidgets('el archivo soltado: cuánto pesa, hasta cuándo, y se recupera', (
    tester,
  ) async {
    await seedBook();
    await harness.container
        .read(contentTrashRepositoryProvider)
        .keepOnlyText('libro');
    await pumpSection(tester);

    expect(find.text(es.contentTrashTitle), findsOneWidget);
    expect(find.text(es.contentTrashFile), findsOneWidget);
    // Treinta días después de hoy, 1 de octubre: el 31.
    expect(find.textContaining('2,0 MB'), findsOneWidget);
    expect(find.textContaining('31'), findsOneWidget);

    await tester.tap(find.text(es.contentTrashRestoreFile));
    await tester.pumpAndSettle();

    expect(find.text(es.contentTrashFileRestored), findsOneWidget);
    expect(find.byKey(const Key('content-trash-section')), findsNothing);
    expect(await trashedRows(), 0);
  });

  testWidgets('el texto soltado se recupera con su botón', (tester) async {
    await seedBook();
    await harness.container
        .read(contentTrashRepositoryProvider)
        .keepOnlyFile('libro');
    await pumpSection(tester);

    expect(find.text(es.contentTrashText), findsOneWidget);
    expect(find.text(es.contentTrashRestoreText), findsOneWidget);
    expect(find.text(es.contentTrashRestoreFile), findsNothing);

    await tester.tap(find.text(es.contentTrashRestoreText));
    await tester.pumpAndSettle();

    expect(find.text(es.contentTrashTextRestored), findsOneWidget);
    expect(await trashedRows(), 0);
  });

  testWidgets('el archivo y el texto a la vez: cada uno con lo suyo', (
    tester,
  ) async {
    await seedBook();
    final trash = harness.container.read(contentTrashRepositoryProvider);
    await trash.keepOnlyFile('libro');
    // Con el texto afuera ya no se puede soltar el archivo (quedaría vacío):
    // la papelera nunca tiene las dos mitades de un mismo elemento.
    expect((await trash.keepOnlyText('libro')).isLeft(), isTrue);
    await pumpSection(tester);

    expect(find.byKey(const Key('content-trash-text')), findsOneWidget);
    expect(find.byKey(const Key('content-trash-file')), findsNothing);
  });
}
