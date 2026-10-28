import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/source_study_line.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/triage_sheet.dart';
import '../processed_ui_fixture.dart';

/// En el detalle de una fuente, dónde se la estudia (F41, decisión K): en su
/// documento procesado, o triándola primero.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> openDetail(WidgetTester tester, String id) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail(id));
    expect(find.byType(ItemDetailScreen), findsOneWidget);
  }

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<List<ProcessedDocumentRow>> documents() =>
      harness.database.select(harness.database.processedDocuments).get();

  Future<void> saveWaitingSource(String id, SourceKind kind) async {
    final at = DateTime(2026, 10, 28, 9);
    final saved = await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Sin texto',
            source: Source(id: id, kind: kind, capturedAt: at),
            processingState: kind == SourceKind.reference
                ? ProcessingState.ready
                : ProcessingState.pending,
            createdAt: at,
            updatedAt: at,
          ),
        );
    saved.getOrElse((failure) => throw StateError('$failure'));
  }

  final line = find.byType(SourceStudyLine);

  testWidgets('en la Bandeja, «Para estudiarlo, triálo»: «Triar» abre la '
      'hoja, con «Listo» queda triada con su documento, la línea lleva a él, '
      'y «Deshacer» deshace las dos cosas', (tester) async {
    await harness.saveTextSource('roma', title: 'Roma');
    await openDetail(tester, 'roma');

    expect(find.text(es.sourceStudyTriage), findsOneWidget);
    await tester.ensureVisible(find.text(es.sourceStudyTriageAction));
    await tester.tap(find.text(es.sourceStudyTriageAction));
    await tester.pumpAndSettle();
    expect(triageSheet, findsOneWidget);

    await finishTriageWithText(tester);

    expect(triageSheet, findsNothing);
    expect(await stateOf('roma'), ItemState.triaged);
    expect(await documents(), hasLength(1));
    expect(find.text(es.processedRetriageTriagedSnack('Roma')), findsOneWidget);
    expect(find.text(es.sourceStudyOpen), findsOneWidget);
    expect(find.text(es.sourceStudyTriage), findsNothing);

    await tester.tap(find.text(es.inboxUndo));
    await tester.pumpAndSettle();

    expect(await documents(), isEmpty);
    expect(await stateOf('roma'), ItemState.processed);
    expect(find.text(es.sourceStudyTriage), findsOneWidget);
  });

  testWidgets('cerrar la hoja sin «Listo» la deja como estaba', (tester) async {
    await harness.saveTextSource('roma');
    await openDetail(tester, 'roma');

    await tester.ensureVisible(find.text(es.sourceStudyTriageAction));
    await tester.tap(find.text(es.sourceStudyTriageAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(await documents(), isEmpty);
    expect(await stateOf('roma'), ItemState.processed);
  });

  testWidgets('con documento procesado, «Estudiarlo en Procesado» lo abre', (
    tester,
  ) async {
    await harness.saveTextSource('roma', title: 'Roma');
    final id = await harness.processTextAndNotes('roma');
    await openDetail(tester, 'roma');

    expect(find.text(es.sourceStudyInProcessed), findsOneWidget);
    await tester.ensureVisible(find.text(es.sourceStudyOpen));
    await tester.tap(find.text(es.sourceStudyOpen));
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    expect(
      tester
          .widget<ProcessedDocumentScreen>(find.byType(ProcessedDocumentScreen))
          .documentId,
      id,
    );
  });

  for (final state in [ItemState.triaged, ItemState.discarded]) {
    testWidgets('${state.name} y sin documento: «Volver a triar» abre la '
        'hoja', (tester) async {
      await harness.saveTextSource('roma');
      await (harness.database.update(harness.database.knowledgeEntries)
            ..where((e) => e.id.equals('roma')))
          .write(KnowledgeEntriesCompanion(state: Value(state)));
      await openDetail(tester, 'roma');

      expect(find.text(es.sourceStudyTriage), findsOneWidget);
      final retriage = find.descendant(
        of: line,
        matching: find.text(es.processedRetriage),
      );
      expect(retriage, findsOneWidget);
      expect(
        find.descendant(
          of: line,
          matching: find.text(es.sourceStudyTriageAction),
        ),
        findsNothing,
      );

      await tester.ensureVisible(retriage);
      await tester.tap(retriage);
      await tester.pumpAndSettle();
      expect(triageSheet, findsOneWidget);
    });
  }

  testWidgets('sin texto todavía, «Triar» espera apagado, con su motivo', (
    tester,
  ) async {
    await saveWaitingSource('espera', SourceKind.webPage);
    await openDetail(tester, 'espera');

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('source-study-triage-button')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: line,
        matching: find.byTooltip(es.sourcePanelNeedsText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('una referencia sin texto no tiene nada que estudiar: no dice '
      'nada', (tester) async {
    await saveWaitingSource('ref', SourceKind.reference);
    await openDetail(tester, 'ref');

    expect(line, findsOneWidget);
    expect(find.text(es.sourceStudyTriage), findsNothing);
    expect(find.text(es.sourceStudyInProcessed), findsNothing);
  });

  testWidgets('en un teléfono y con la letra al doble no desborda, triada o '
      'no', (tester) async {
    await harness.saveTextSource('roma');
    await harness.saveTextSource('grecia');
    await harness.processTextAndNotes('grecia');
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final id in ['roma', 'grecia']) {
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      await tester.pumpWidget(
        harness.wrap(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SourceStudyLine(item: item),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          Key(
            id == 'roma' ? 'source-study-triage-button' : 'source-study-open',
          ),
        ),
        findsOneWidget,
        reason: id,
      );
      expect(tester.takeException(), isNull, reason: id);
    }
  });
}
