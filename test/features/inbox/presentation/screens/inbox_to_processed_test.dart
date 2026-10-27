import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/triage/processed_cut_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/triage_sheet.dart';

const _content = 'La primera idea. La segunda idea es larga. La tercera.';

/// La Bandeja que tría a Procesado (F41): «Triado» abre la hoja, «Pasar todo
/// sin modificar» lo hace de un toque, «Extraer nota» corta del original
/// hacia las notas del documento procesado, y «Deshacer» deshace las dos
/// cosas. Contra la base real del arnés.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    final now = DateTime(2026, 10, 27, 9);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente',
            title: 'Historia de Roma',
            source: Source(
              id: 'src-fuente',
              kind: SourceKind.document,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-fuente',
                itemId: 'fuente',
                kind: RenditionKind.plainText,
                content: _content,
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  });

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<List<ProcessedPartRow>> parts() =>
      harness.database.select(harness.database.processedParts).get();

  Future<int> documents() async =>
      (await harness.database.select(harness.database.processedDocuments).get())
          .length;

  Future<int> items() async =>
      (await harness.database.select(harness.database.knowledgeEntries).get())
          .length;

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> undo(WidgetTester tester) async {
    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
    await tester.pumpAndSettle();
  }

  testWidgets('«Pasar todo sin modificar» guarda el texto original entero, '
      'sin abrir la hoja, y la deja triada', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.byKey(const Key('inbox-pass-unchanged')));
    await tester.pumpAndSettle();

    expect(triageSheet, findsNothing);
    expect(await stateOf('fuente'), ItemState.triaged);
    final saved = await parts();
    expect(saved.map((part) => part.section), [ProcessedSection.text]);
    expect(saved.single.content, _content);
    expect(
      find.text(es.inboxPassedUnchangedSnack('Historia de Roma')),
      findsOneWidget,
    );
  });

  testWidgets('Shift+→ también pasa todo, y «Deshacer» deshace las dos '
      'cosas: el documento procesado se va y la fuente vuelve', (tester) async {
    await pumpInbox(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(triageSheet, findsNothing);
    expect(await documents(), 1);

    await undo(tester);

    expect(await documents(), 0);
    expect(await stateOf('fuente'), ItemState.processed);
    expect(find.text('Historia de Roma'), findsOneWidget);
  });

  testWidgets('cerrar la hoja sin «Listo» deja la fuente en la Bandeja, sin '
      'documento procesado', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('triage-switch-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(triageSheet, findsNothing);
    expect(await stateOf('fuente'), ItemState.processed);
    expect(await documents(), 0);
    expect(find.text('Historia de Roma'), findsOneWidget);
  });

  testWidgets('«Listo» arma el documento con lo elegido, y «Deshacer» desde '
      'el aviso lo deshace junto con el triado', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionTriage));
    await tester.pumpAndSettle();
    await finishTriageWithText(tester);

    expect(await stateOf('fuente'), ItemState.triaged);
    expect((await parts()).single.content, _content);

    await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
    await tester.pumpAndSettle();

    expect(await documents(), 0);
    expect(await stateOf('fuente'), ItemState.processed);
  });

  testWidgets('«Extraer nota» abre el original: lo extraído y lo cortado van '
      'a las notas y los fragmentos del documento procesado, no a la '
      'Biblioteca', (tester) async {
    final before = await items();
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionExtract));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedCutScreen), findsOneWidget);

    Future<void> select(int base, int extent) async {
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: TextSelection(baseOffset: base, extentOffset: extent),
        ),
        SelectionChangedCause.tap,
      );
      state.showToolbar();
      await tester.pumpAndSettle();
    }

    await select(0, 16);
    await tester.tap(find.byTooltip(es.detailExtractSelection));
    await tester.pumpAndSettle();
    await select(17, 42);
    await tester.tap(find.byKey(const Key('highlight-to-processed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('processed-cut-done')));
    await tester.pumpAndSettle();

    // De vuelta en la hoja, con lo cortado en sus listas (más abajo, quizás
    // fuera de la vista: las listas van después de lo de la fuente).
    expect(triageSheet, findsOneWidget);
    expect(find.text('La primera idea.', skipOffstage: false), findsOneWidget);
    expect(
      find.text('La segunda idea es larga.', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();

    expect(await stateOf('fuente'), ItemState.triaged);
    final saved = {for (final part in await parts()) part.section: part};
    expect(saved.keys, {ProcessedSection.notes, ProcessedSection.fragments});
    expect(saved[ProcessedSection.notes]!.content, 'La primera idea.');
    expect(
      saved[ProcessedSection.fragments]!.content,
      'La segunda idea es larga.',
    );
    // Una sola fila nueva de `item`: el documento procesado. Ninguna nota
    // suelta en la Biblioteca (decisión C).
    expect(await items(), before + 1);
  });
}
