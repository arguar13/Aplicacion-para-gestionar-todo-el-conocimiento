import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Triar un libro o un documento (F30, decisión 68): la hoja pregunta qué
/// pasa a la siguiente fase —el texto y el libro, solo el texto, solo el
/// libro—, lo soltado va a la papelera de la app, y «Deshacer» lo recupera.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 1, 9);
  const text = 'Roma no se hizo en un día. Tardó siglos en hacerse imperio.';

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Un libro con su archivo y su texto, listo para triar.
  Future<String> seedBook({
    String id = 'libro',
    SourceKind kind = SourceKind.document,
    int bytes = 3 * 1024 * 1024,
  }) async {
    final path = await harness.files.save(
      bytes: Uint8List(bytes),
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
              kind: kind,
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

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> triage(WidgetTester tester) async {
    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();
  }

  testWidgets('la hoja ofrece las tres, con cuánto libera la del texto', (
    tester,
  ) async {
    await seedBook();
    await pumpInbox(tester);

    await triage(tester);

    expect(find.text(es.inboxKeepTitle), findsOneWidget);
    expect(find.text(es.inboxKeepBoth), findsOneWidget);
    expect(find.text(es.inboxKeepOnlyText), findsOneWidget);
    expect(find.text(es.inboxKeepOnlyFile), findsOneWidget);
    expect(find.text(es.inboxKeepOnlyTextSizeHint('3.0')), findsOneWidget);
  });

  testWidgets('cerrarla sin elegir no tría ni suelta nada', (tester) async {
    final id = await seedBook();
    await pumpInbox(tester);

    await triage(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect((await sourceOf(id)).originalBlobPath, isNotNull);
    expect(await textsOf(id), 1);
    expect(find.text('Historia de Roma'), findsOneWidget);
  });

  testWidgets('texto y libro: se tría como siempre, sin soltar nada', (
    tester,
  ) async {
    final id = await seedBook();
    await pumpInbox(tester);

    await triage(tester);
    await tester.tap(find.byKey(const Key('inbox-keep-both')));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.triaged);
    expect((await sourceOf(id)).originalBlobPath, isNotNull);
    expect(await textsOf(id), 1);
    expect(find.text(es.inboxTriagedSnack('Historia de Roma')), findsOneWidget);
    expect(
      await harness.database.select(harness.database.trashedContents).get(),
      isEmpty,
    );
  });

  testWidgets('solo el texto: el archivo va a la papelera y no se borra del '
      'disco; deshacer lo devuelve', (tester) async {
    final id = await seedBook();
    final path = (await sourceOf(id)).originalBlobPath!;
    await pumpInbox(tester);

    await triage(tester);
    await tester.tap(find.byKey(const Key('inbox-keep-only-text')));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.triaged);
    expect((await sourceOf(id)).originalBlobPath, isNull);
    expect(harness.files.paths, contains(path));
    expect(harness.files.deleted, isEmpty);
    expect(await textsOf(id), 1);
    expect(
      find.text(es.inboxTriagedOnlyTextSnack('Historia de Roma')),
      findsOneWidget,
    );

    await tester.tap(find.text(es.inboxUndo).last);
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect((await sourceOf(id)).originalBlobPath, path);
    expect(
      await harness.database.select(harness.database.trashedContents).get(),
      isEmpty,
    );
  });

  testWidgets('solo el libro: el texto va a la papelera y el libro no se '
      'vuelve a extraer; deshacer devuelve el texto', (tester) async {
    final id = await seedBook();
    await pumpInbox(tester);

    await triage(tester);
    await tester.tap(find.byKey(const Key('inbox-keep-only-file')));
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.triaged);
    expect(await textsOf(id), 0);
    final source = await sourceOf(id);
    expect(source.onlyFile, isTrue);
    expect(source.originalBlobPath, isNotNull);
    expect(
      find.text(es.inboxTriagedOnlyFileSnack('Historia de Roma')),
      findsOneWidget,
    );

    await tester.tap(find.text(es.inboxUndo).last);
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect(await textsOf(id), 1);
    expect((await sourceOf(id)).onlyFile, isFalse);
    // Y vuelve al mazo, con su texto.
    expect(find.text('Historia de Roma'), findsOneWidget);
  });

  testWidgets('deshacer, si el archivo ya no estaba en el teléfono, lo dice y '
      'devuelve lo demás', (tester) async {
    final id = await seedBook();
    final path = (await sourceOf(id)).originalBlobPath!;
    await pumpInbox(tester);

    await triage(tester);
    await tester.tap(find.byKey(const Key('inbox-keep-only-text')));
    await tester.pumpAndSettle();
    await harness.files.delete(path);

    await tester.tap(find.text(es.inboxUndo).last);
    await tester.pumpAndSettle();

    expect(await stateOf(id), ItemState.processed);
    expect(find.text(es.contentTrashFileMissing), findsOneWidget);
  });

  testWidgets('lo que no es un libro se tría sin preguntar', (tester) async {
    final id = await seedBook(id: 'transcripcion', kind: SourceKind.audio);
    await pumpInbox(tester);

    await triage(tester);

    expect(find.text(es.inboxKeepTitle), findsNothing);
    expect(await stateOf(id), ItemState.triaged);
    expect((await sourceOf(id)).originalBlobPath, isNotNull);
  });
}
