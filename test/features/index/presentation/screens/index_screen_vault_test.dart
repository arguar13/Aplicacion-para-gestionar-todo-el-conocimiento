import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/index/presentation/screens/index_screen.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
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

  /// Un libro de [chapters] capítulos de nivel 1, cada uno con varios
  /// párrafos: el último queda a muchas pantallas del comienzo.
  Future<void> book({int chapters = 30}) async {
    final text = StringBuffer();
    for (var i = 1; i <= chapters; i++) {
      if (i > 1) text.write('\n\n');
      text.write('# Capítulo $i\n\n');
      for (var p = 0; p < 6; p++) {
        if (p > 0) text.write('\n\n');
        text.write(
          'Párrafo $p del capítulo $i, con texto suficiente para ocupar '
          'algunos renglones del lector y que el libro sea largo de verdad.',
        );
      }
    }
    await harness.saveTextSource(
      'libro',
      title: 'Un libro largo',
      text: text.toString(),
    );
    await harness.processTextAndNotes('libro');
  }

  /// La lista del Índice, la que se desplaza: no la del buscador.
  Finder indexList() => find
      .descendant(
        of: find.descendant(
          of: find.byType(IndexScreen),
          matching: find.byType(CustomScrollView),
        ),
        matching: find.byType(Scrollable),
      )
      .first;

  Finder bookRow() => find.byWidgetPredicate(
    (w) => w is IndexDocumentRow && w.document.title == 'Un libro largo',
  );

  /// Los pedazos del lector pintados con el resalte de ir a un lugar —el de
  /// «Notas (N)»—.
  List<String> flashed(WidgetTester tester) {
    final flash = Theme.of(
      tester.element(find.byType(ProcessedReaderScreen)),
    ).colorScheme.tertiaryContainer;
    final found = <String>[];
    for (final rich in tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const Key('extract-viewer-list')),
        matching: find.byType(RichText),
      ),
    )) {
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text != null &&
            span.style?.backgroundColor == flash) {
          found.add(span.text!);
        }
        return true;
      });
    }
    return found;
  }

  /// Si el renglón donde empieza [text] se ve en la pantalla: un bloque del
  /// lector puede tener varios párrafos, así que se mide el renglón, no el
  /// bloque.
  bool onScreen(WidgetTester tester, String text) {
    final rich = find.descendant(
      of: find.byKey(const Key('extract-viewer-list')),
      matching: find.textContaining(text, findRichText: true),
    );
    if (rich.evaluate().isEmpty) return false;
    final paragraph = tester.renderObject<RenderParagraph>(rich.first);
    final at = paragraph.text.toPlainText().indexOf(text);
    final line = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + text.length),
        )
        .first
        .toRect()
        .shift(paragraph.localToGlobal(Offset.zero));
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    return line.top >= 0 && line.bottom <= height;
  }

  testWidgets('en un teléfono, tocar un capítulo lejano abre el lector justo '
      'en ese título, que se resalta un momento; «atrás» vuelve al Índice con '
      'lo desplegado y la posición', (tester) async {
    await book(chapters: 40);
    await pumpApp(tester, harness);
    tester.view.physicalSize = const Size(420, 900);
    await goAndSettle(tester, harness, RoutePaths.index);
    await tester.tap(bookRow());
    await tester.pumpAndSettle();

    final far = find.byWidgetPredicate(
      (w) => w is IndexLeaderLine && w.plainTitle == 'Capítulo 36',
    );
    await tester.scrollUntilVisible(far, 200, scrollable: indexList());
    await tester.ensureVisible(far);
    await tester.pumpAndSettle();
    final indexScroll = tester.state<ScrollableState>(indexList()).position;
    final before = indexScroll.pixels;
    expect(before, greaterThan(0));

    await tester.tap(far);
    // Hasta que el lector lee el texto y va al lugar: menos que lo que dura
    // el resalte.
    await tester.pumpAndSettle();

    expect(find.byType(ProcessedReaderScreen), findsOneWidget);
    expect(flashed(tester), ['Capítulo 36']);
    expect(onScreen(tester, 'Párrafo 0 del capítulo 36'), isTrue);
    expect(onScreen(tester, 'Párrafo 0 del capítulo 1,'), isFalse);

    // El resalte se apaga solo.
    await tester.pump(const Duration(seconds: 3));
    expect(flashed(tester), isEmpty);

    // «Seguir escuchando» vuelve a la lectura, no a este capítulo.
    final offered = harness.container.read(currentReadableProvider);
    expect(offered?.location, isNotNull);
    expect(offered!.location, isNot(contains('at=')));

    harness.container.read(goRouterProvider).pop();
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsOneWidget);
    expect(far, findsOneWidget);
    expect(tester.state<ScrollableState>(indexList()).position.pixels, before);
  });

  testWidgets('al costado, otro capítulo del mismo documento lleva el mismo '
      'lector a su lugar, y volver a tocar uno vuelve a llevar ahí', (
    tester,
  ) async {
    await book(chapters: 12);
    await pumpApp(tester, harness);
    tester.view.physicalSize = const Size(1400, 1000);
    await goAndSettle(tester, harness, RoutePaths.index);
    await tester.tap(bookRow());
    await tester.pumpAndSettle();

    Finder chapter(int n) => find.byWidgetPredicate(
      (w) => w is IndexLeaderLine && w.plainTitle == 'Capítulo $n',
    );
    await tester.tap(chapter(10));
    // Hasta que el lector lee el texto y va al lugar: menos que lo que dura
    // el resalte.
    await tester.pumpAndSettle();
    final reader = tester.state(find.byType(ProcessedReaderScreen).first);
    expect(flashed(tester), ['Capítulo 10']);
    expect(onScreen(tester, 'Párrafo 0 del capítulo 10'), isTrue);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(chapter(2));
    // Hasta que el lector lee el texto y va al lugar: menos que lo que dura
    // el resalte.
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(ProcessedReaderScreen).first),
      same(reader),
      reason: 'el mismo lector, no uno nuevo',
    );
    expect(flashed(tester), ['Capítulo 2']);
    expect(onScreen(tester, 'Párrafo 0 del capítulo 2,'), isTrue);
    await tester.pump(const Duration(seconds: 3));

    // Se baja a leer hasta el final, y el mismo capítulo vuelve a llevar a
    // su título.
    final reading = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('extract-viewer-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    reading.jumpTo(reading.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(onScreen(tester, 'Párrafo 0 del capítulo 2,'), isFalse);
    await tester.tap(chapter(2));
    await tester.pumpAndSettle();
    expect(flashed(tester), ['Capítulo 2']);
    expect(onScreen(tester, 'Párrafo 0 del capítulo 2,'), isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

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
