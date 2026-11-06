import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/index/presentation/screens/index_screen.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// El Índice (F46, paso 3) sobre la base de verdad, en memoria, con el router
/// de la app: lo que se procesa aparece con sus capítulos, y tocar uno abre
/// el lector único entero —encima en un teléfono, al costado en una pantalla
/// ancha—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    await harness.saveTextSource(
      'roma',
      title: 'Historia de Roma',
      text:
          '# La República\n\nLa república romana cayó.\n\n'
          '## César\n\nCésar cruzó el Rubicón.',
    );
    await harness.processTextAndNotes('roma');
  });

  Finder document() => find.byWidgetPredicate(
    (w) => w is IndexDocumentRow && w.document.title == 'Historia de Roma',
  );

  Future<void> openIndex(WidgetTester tester, Size size) async {
    await pumpApp(tester, harness);
    tester.view.physicalSize = size;
    await goAndSettle(tester, harness, RoutePaths.index);
    expect(find.byType(IndexScreen), findsOneWidget);
    await tester.tap(document());
    await tester.pumpAndSettle();
  }

  testWidgets('lo procesado aparece con sus capítulos, leídos al guardarse '
      'el texto', (tester) async {
    await openIndex(tester, const Size(420, 900));

    expect(find.text(es.f46P3Untopiced.toUpperCase()), findsOneWidget);
    final titles = [
      for (final line in tester.widgetList<IndexLeaderLine>(
        find.byType(IndexLeaderLine),
      ))
        line.plainTitle,
    ];
    expect(titles, isNotEmpty);
  });

  testWidgets('en un teléfono, tocar una entrada abre el lector único encima, '
      'con ←', (tester) async {
    await openIndex(tester, const Size(420, 900));

    await tester.tap(find.byType(IndexEntryRow).first);
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedReaderScreen), findsOneWidget);
    expect(find.byKey(const Key('reading-frame-back')), findsOneWidget);
    expect(find.byKey(const Key('processed-reader-close')), findsNothing);
  });

  testWidgets('en una pantalla ancha, el lector entero se abre al costado, '
      'con ✕ en vez de ←, y ✕ lo cierra sin dejar el Índice', (tester) async {
    await openIndex(tester, const Size(1400, 1000));

    await tester.tap(find.byType(IndexEntryRow).first);
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsOneWidget);
    expect(find.byType(ProcessedReaderScreen), findsOneWidget);
    expect(find.byKey(const Key('reading-frame-back')), findsNothing);

    await tester.tap(find.byKey(const Key('processed-reader-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedReaderScreen), findsNothing);
    expect(find.text(es.f46P3PaneEmptyTitle), findsOneWidget);
  });

  testWidgets('al costado, otra parte del documento —el resumen— se abre '
      'encima, y «atrás» vuelve a los dos paneles con el texto abierto', (
    tester,
  ) async {
    // Uno con su resumen, escrito directo en las tablas con su entrada del
    // Índice: el resumen lo escribe la IA, fuera de esta prueba.
    final db = harness.database;
    await insertProcessedRows(
      db,
      id: 'resumido',
      title: 'Con resumen',
      parts: {
        ProcessedSection.text: ['Un texto sin títulos.'],
        ProcessedSection.summary: ['Una oración que lo resume.'],
      },
    );
    await db
        .into(db.processedHeadings)
        .insert(
          ProcessedHeadingsCompanion.insert(
            documentId: 'resumido',
            origin: IndexEntryOrigin.wholeText,
            level: 1,
            position: 0,
            title: '',
            textStart: const Value(0),
            textEnd: const Value(21),
            textPage: const Value(1),
          ),
        );
    await pumpApp(tester, harness);
    tester.view.physicalSize = const Size(1400, 1000);
    await goAndSettle(tester, harness, RoutePaths.index);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IndexDocumentRow && w.document.id == 'resumido',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IndexEntryRow).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading-frame-contents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('processed-reader-open-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('processed-reader-summary')), findsOneWidget);

    harness.container.read(goRouterProvider).pop();
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsOneWidget);
    expect(find.byKey(const Key('processed-reader-close')), findsOneWidget);
  });

  testWidgets('al costado, mandarlo a la papelera cierra el panel, y el '
      'Índice lo saca en vivo', (tester) async {
    await openIndex(tester, const Size(1400, 1000));
    await tester.tap(find.byType(IndexEntryRow).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reading-frame-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('processed-reader-trash')));
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedReaderScreen), findsNothing);
    expect(find.text(es.f46P3PaneEmptyTitle), findsOneWidget);
    expect(document(), findsNothing);
    expect(find.text(es.f46P3EmptyTitle), findsOneWidget);
  });
}
