import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/design/app_theme.dart';
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
import '../processed_ui_fixture.dart';

/// Cualquier botón de Material —relleno, tonal, con borde, de texto—:
/// `find.byType` busca el tipo exacto, y cada uno es una subclase.
final Finder _anyButton = find.byWidgetPredicate(
  (widget) => widget is ButtonStyleButton,
  description: 'un botón',
);

/// En el detalle de una fuente, dónde se la estudia (F41, decisión K): en su
/// documento procesado. Sin él la línea no dibuja nada: a triarla se llega
/// por la tarjeta «Bandeja» (F45, paso 7c), y sus pruebas están con ella.
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

  Future<KnowledgeItem> itemOf(String id) async =>
      (await harness.container.read(libraryRepositoryProvider).findById(id))
          .getRight()
          .toNullable()!;

  final line = find.byType(SourceStudyLine);
  final processedLine = find.byKey(const Key('source-study-processed'));

  /// La línea sola, como la pone el detalle.
  Future<void> pumpLine(
    WidgetTester tester,
    String id, {
    double width = 900,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final item = await itemOf(id);
    await tester.pumpWidget(
      harness.wrap(
        Theme(
          data: theme ?? AppTheme.lightTheme,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SourceStudyLine(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con documento procesado, solo «Estudiarlo en Procesado», que '
      'lo abre', (tester) async {
    await harness.saveTextSource('roma', title: 'Roma');
    final id = await harness.processTextAndNotes('roma');
    await openDetail(tester, 'roma');

    expect(find.text(es.sourceStudyInProcessed), findsOneWidget);
    // Nada de triar en la línea: eso está en la tarjeta «Bandeja».
    expect(find.descendant(of: line, matching: _anyButton), findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.text(es.processedRetriage)),
      findsNothing,
    );

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

  testWidgets('sin documento, en la Bandeja, no dibuja nada —ni su espacio—', (
    tester,
  ) async {
    await harness.saveTextSource('roma');
    await pumpLine(tester, 'roma');

    expect(line, findsOneWidget);
    expect(processedLine, findsNothing);
    expect(find.descendant(of: line, matching: _anyButton), findsNothing);
    expect(tester.getSize(line).height, 0);
  });

  for (final state in [ItemState.triaged, ItemState.discarded]) {
    testWidgets('${state.name} y sin documento: no dibuja nada', (
      tester,
    ) async {
      await harness.saveTextSource('roma');
      await (harness.database.update(harness.database.knowledgeEntries)
            ..where((e) => e.id.equals('roma')))
          .write(KnowledgeEntriesCompanion(state: Value(state)));
      await pumpLine(tester, 'roma');

      expect(processedLine, findsNothing);
      expect(tester.getSize(line).height, 0);
    });
  }

  testWidgets('sin texto todavía, tampoco: no hay qué estudiar', (
    tester,
  ) async {
    await saveWaitingSource('espera', SourceKind.webPage);
    await pumpLine(tester, 'espera');

    expect(processedLine, findsNothing);
    expect(tester.getSize(line).height, 0);
  });

  testWidgets('una referencia sin texto no tiene nada que estudiar: no dice '
      'nada', (tester) async {
    await saveWaitingSource('ref', SourceKind.reference);
    await pumpLine(tester, 'ref');

    expect(processedLine, findsNothing);
    expect(tester.getSize(line).height, 0);
  });

  for (final (name, theme) in [
    ('claro', AppTheme.lightTheme),
    ('oscuro', AppTheme.darkTheme),
  ]) {
    testWidgets('a 360 dp con la letra al doble, tema $name, no desborda', (
      tester,
    ) async {
      await harness.saveTextSource('grecia');
      await harness.processTextAndNotes('grecia');
      await pumpLine(tester, 'grecia', width: 360, textScale: 2, theme: theme);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('source-study-open')), findsOneWidget);
      expect(tester.getRect(processedLine).right, lessThanOrEqualTo(360 - 24));
      expect(
        tester.getRect(find.byKey(const Key('source-study-open'))).right,
        lessThanOrEqualTo(360 - 24),
      );
    });
  }

  testWidgets('el lector de pantalla lee qué pasa y su botón', (tester) async {
    final handle = tester.ensureSemantics();
    await harness.saveTextSource('grecia');
    await harness.processTextAndNotes('grecia');
    await pumpLine(tester, 'grecia');

    expect(find.bySemanticsLabel(es.sourceStudyInProcessed), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('source-study-open'))),
      isSemantics(
        label: es.sourceStudyOpen,
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
