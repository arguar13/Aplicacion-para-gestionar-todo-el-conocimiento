import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/presentation/providers/content_trash_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Triar nunca suelta nada de la fuente (F41, decisión G): de la Biblioteca
/// nada se borra. La hoja de F30 —«Texto y libro / Solo el texto / Solo el
/// libro»— mandaba el archivo o el texto a la papelera de la app; ya no
/// existe, y lo que se soltó así antes sigue en la papelera, recuperable.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 1, 9);
  const text = 'Roma no se hizo en un día. Tardó siglos en hacerse imperio.';

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Un libro con su archivo y su texto, listo para triar.
  Future<String> seedBook({String id = 'libro'}) async {
    final path = await harness.files.save(
      bytes: Uint8List(3 * 1024 * 1024),
      suggestedName: '$id.pdf',
      id: id,
    );
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Historia de Roma',
            source: Source(
              id: id,
              kind: SourceKind.document,
              capturedAt: now,
              originalFilePath: path,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: '$id-texto',
                itemId: id,
                kind: RenditionKind.plainText,
                content: text,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    return id;
  }

  Future<KnowledgeSourceRow> sourceOf(String id) => (harness.database.select(
    harness.database.knowledgeSources,
  )..where((s) => s.itemId.equals(id))).getSingle();

  Future<int> textsOf(String id) async => (await (harness.database.select(
    harness.database.renditions,
  )..where((r) => r.itemId.equals(id))).get()).length;

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<List<TrashedContentRow>> contentTrash() =>
      harness.database.select(harness.database.trashedContents).get();

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  /// Que la fuente siga entera: su archivo en el disco y apuntado, su texto,
  /// sin la marca de «solo el libro», y nada en la papelera de la app.
  Future<void> expectWhole(String id, String path) async {
    final source = await sourceOf(id);
    expect(source.originalBlobPath, path);
    expect(source.onlyFile, isFalse);
    expect(harness.files.paths, contains(path));
    expect(harness.files.deleted, isEmpty);
    expect(await textsOf(id), 1);
    expect(await contentTrash(), isEmpty);
  }

  testWidgets('triar un libro no pregunta nada ni suelta nada: el archivo y '
      'el texto quedan, y la papelera de la app sigue vacía', (tester) async {
    final id = await seedBook();
    final path = (await sourceOf(id)).originalBlobPath!;
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(await stateOf(id), ItemState.triaged);
    expect(find.text(es.inboxTriagedSnack('Historia de Roma')), findsOneWidget);
    await expectWhole(id, path);
  });

  testWidgets('con la flecha y con el gesto, lo mismo', (tester) async {
    final id = await seedBook();
    final otro = await seedBook(id: 'otro');
    final path = (await sourceOf(id)).originalBlobPath!;
    final otherPath = (await sourceOf(otro)).originalBlobPath!;
    await pumpInbox(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Historia de Roma'), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.triaged);
    expect(await stateOf(otro), ItemState.triaged);
    expect(find.byType(BottomSheet), findsNothing);
    final source = await sourceOf(otro);
    expect(source.originalBlobPath, otherPath);
    await expectWhole(id, path);
  });

  testWidgets('deshacer lo devuelve a la Bandeja, entero', (tester) async {
    final id = await seedBook();
    final path = (await sourceOf(id)).originalBlobPath!;
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.inboxUndo).last);
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect(find.text('Historia de Roma'), findsOneWidget);
    await expectWhole(id, path);
  });

  testWidgets('lo que se soltó antes con la hoja de F30 sigue en la papelera '
      'de la app: triar no lo toca, y se recupera como siempre', (
    tester,
  ) async {
    final id = await seedBook();
    final path = (await sourceOf(id)).originalBlobPath!;
    final trash = harness.container.read(contentTrashRepositoryProvider);
    // Como lo dejaba «Solo el texto»: el archivo, en la papelera de la app.
    final dropped = (await trash.keepOnlyText(id)).getRight().toNullable()!;
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.triaged);
    expect((await contentTrash()).map((row) => row.id), [dropped.single.id]);

    final restored = await trash.restore(dropped.single.id);

    expect(restored.getRight().toNullable(), ContentRestoreOutcome.restored);
    expect((await sourceOf(id)).originalBlobPath, path);
  });
}
