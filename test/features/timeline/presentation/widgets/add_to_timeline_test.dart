import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_highlight_toolbar.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';

/// «A la línea de tiempo» en la barrita de resaltar (F40, paso 5): lo
/// seleccionado en un texto —el extraído, el del lector, el de un PDF o una
/// página web— pasa a ser un hecho con su cita puesta y, si trae una fecha, la
/// fecha cargada.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  late String location;

  final now = DateTime(2026, 10, 26, 10);

  const text =
      'Darwin nació en 1809. En 1859 publicó El origen de las especies. '
      'Hubo guerra de 1914 a 1918 y después paz. Eso fue en el siglo XX.';

  setUp(() async {
    harness = await LibraryHarness.create(now: now);
    db = harness.database;
    location = '';
    await insertItemRows(
      db,
      id: 'darwin',
      title: 'Darwin, una vida',
      kind: SourceKind.document,
    );
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto-darwin',
            itemId: 'darwin',
            kind: RenditionKind.plainText,
            content: const Value(text),
            isPrimary: true,
            createdAt: now,
          ),
        );
    // Su documento procesado (F41, paso 6): ahí van los hechos que se marcan
    // en la fuente, con la cita en ella.
    await insertProcessedDocument(
      db,
      id: processedDocumentIdFor('darwin'),
      title: 'Darwin, una vida',
      createdAt: now,
    );
    await (db.update(
      db.processedDocuments,
    )..where((d) => d.itemId.equals(processedDocumentIdFor('darwin')))).write(
      const ProcessedDocumentsCompanion(sourceItemId: Value('darwin')),
    );
  });

  Future<List<DatedEvent>> stored() async => [
    for (final row in await db.select(db.datedEvents).get())
      datedEventFromRow(row),
  ];

  Finder byKey(String key) => find.byKey(ValueKey(key));

  Widget host(Widget child) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: SingleChildScrollView(child: child)),
        ),
        GoRoute(
          path: RoutePaths.timeline,
          builder: (_, _) {
            location = RoutePaths.timeline;
            return const Scaffold(body: Text('línea de tiempo'));
          },
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  Future<void> selectExtracted(WidgetTester tester, String quote) async {
    final base = text.indexOf(quote);
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(
          baseOffset: base,
          extentOffset: base + quote.length,
        ),
      ),
      SelectionChangedCause.tap,
    );
    state.showToolbar();
    await tester.pumpAndSettle();
  }

  Future<void> pumpText(WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        const HighlightableText(
          itemId: 'darwin',
          renditionId: 'texto-darwin',
          content: text,
          markdown: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String yearField(WidgetTester tester) => tester
      .widget<TextField>(
        find.widgetWithText(TextField, es.datePickerYear).first,
      )
      .controller!
      .text;

  group('desde el texto extraído', () {
    testWidgets('una selección con fecha abre el formulario con la fecha '
        'cargada y la cita puesta', (tester) async {
      await pumpText(tester);
      await selectExtracted(
        tester,
        'En 1859 publicó El origen de las especies.',
      );

      expect(find.byTooltip(es.highlightAddToTimeline), findsOneWidget);
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(byKey('dated-event-form-heading'), findsOneWidget);
      expect(yearField(tester), '1859');
      expect(
        find.descendant(
          of: byKey('dated-event-form-quote'),
          matching: find.text('En 1859 publicó El origen de las especies.'),
        ),
        findsOneWidget,
      );
      // El documento es de donde sale la cita, y no se cambia.
      expect(find.text('Darwin, una vida'), findsOneWidget);
      expect(find.text(es.timelineFormDocumentFixed), findsOneWidget);
      // Solo falta confirmar el título, que ya viene propuesto.
      expect(
        tester
            .widget<TextField>(byKey('dated-event-form-title'))
            .controller!
            .text,
        'En 1859 publicó El origen de las especies.',
      );
    });

    testWidgets('la barrita se cierra al elegirla', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'En 1859 publicó');
      expect(find.byKey(const Key('highlight-toolbar-card')), findsOneWidget);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('highlight-toolbar-card')), findsNothing);
    });

    testWidgets('en un texto con formato, las posiciones son las del texto '
        'crudo y no las de lo que se ve', (tester) async {
      const raw = '# Darwin\n\nEn **1859** publicó su obra magna.';
      await tester.pumpWidget(
        host(
          const HighlightableText(
            itemId: 'darwin',
            renditionId: 'texto-darwin',
            content: raw,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final shown = state.textEditingValue.text;
      final base = shown.indexOf('En 1859');
      expect(base, isNonNegative);
      state.userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: TextSelection(
            baseOffset: base,
            extentOffset: base + 'En 1859'.length,
          ),
        ),
        SelectionChangedCause.tap,
      );
      state.showToolbar();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();
      expect(yearField(tester), '1859');
      await tester.enterText(byKey('dated-event-form-title'), 'Publica');
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      expect(fact.startOffset, raw.indexOf('En **1859'));
      final (start, end) = (fact.startOffset!, fact.endOffset!);
      expect(fact.excerpt, raw.substring(start, end));
      expect(fact.excerpt, startsWith('En **1859'));
      // Lo que se ve y lo guardado no empiezan en el mismo lugar.
      expect(fact.startOffset, isNot(base));
    });

    testWidgets('al confirmar, el hecho queda con su cita, su posición y la '
        'persona como autora', (tester) async {
      await pumpText(tester);
      const quote = 'En 1859 publicó El origen de las especies.';
      await selectExtracted(tester, quote);
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      await tester.enterText(
        byKey('dated-event-form-title'),
        'Publica El origen',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      final start = text.indexOf(quote);
      expect(fact.itemId, processedDocumentIdFor('darwin'));
      expect(fact.title, 'Publica El origen');
      expect(fact.date.year, 1859);
      expect(fact.end, isNull);
      expect(fact.renditionId, 'texto-darwin');
      expect(fact.startOffset, start);
      expect(fact.endOffset, start + quote.length);
      expect(fact.excerpt, quote);
      expect(fact.origin, ContentOrigin.user);
      expect(fact.hasAnchor, isTrue);
      // Y no se creó ninguna nota de hechos sueltos: es del documento.
      expect(
        await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.title.equals(es.timelineFormLooseNoteTitle))).get(),
        isEmpty,
      );
      expect(find.text(es.timelineFactAdded), findsOneWidget);
    });

    testWidgets('un rango trae su fin', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'guerra de 1914 a 1918 y después');
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(yearField(tester), '1914');
      expect(
        tester.widget<SwitchListTile>(byKey('dated-event-form-range')).value,
        isTrue,
      );
      final end = tester
          .widget<TextField>(
            find.widgetWithText(TextField, es.datePickerYear).last,
          )
          .controller!
          .text;
      expect(end, '1918');

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      expect(fact.date.year, 1914);
      expect(fact.end?.year, 1918);
    });

    testWidgets('«siglo XX» llega con su precisión', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'Eso fue en el siglo XX.');
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      expect(fact.date.label, '1901 – 2000');
    });

    testWidgets('una selección sin fecha abre el formulario con la fecha '
        'vacía, y no se guarda sin ella', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'El origen de las especies');
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(yearField(tester), isEmpty);
      expect(
        find.descendant(
          of: byKey('dated-event-form-quote'),
          matching: find.text('El origen de las especies'),
        ),
        findsOneWidget,
      );

      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();
      expect(find.text(es.timelineFormDateMissing), findsOneWidget);
      expect(await stored(), isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        '1859',
      );
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();
      expect((await stored()).single.date.year, 1859);
    });

    testWidgets('una selección larga no propone título: queda por escribir', (
      tester,
    ) async {
      await pumpText(tester);
      await selectExtracted(tester, text.substring(0, 120));
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(byKey('dated-event-form-title'))
            .controller!
            .text,
        isEmpty,
      );
      // Pero la cita sí queda puesta, entera.
      expect(byKey('dated-event-form-quote'), findsOneWidget);
    });

    testWidgets('cancelar no guarda nada ni avisa', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'En 1859 publicó');
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      await tester.tap(byKey('dated-event-form-cancel'));
      await tester.pumpAndSettle();

      expect(await stored(), isEmpty);
      expect(find.text(es.timelineFactAdded), findsNothing);
    });

    testWidgets('el aviso lleva a la línea de tiempo, recortada a ese '
        'documento', (tester) async {
      await pumpText(tester);
      await selectExtracted(tester, 'En 1859 publicó');
      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.timelineFactAddedSee));
      await tester.pumpAndSettle();

      expect(location, RoutePaths.timeline);
      final scope = harness.container.read(timelineFilterProvider).scope;
      expect(scope?.kind, TimelineScopeKind.document);
      expect(scope?.id, processedDocumentIdFor('darwin'));
      expect(scope?.label, 'Darwin, una vida');
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('de una fuente sin su documento procesado no abre el formulario: '
      'lo dice y lleva a la Bandeja (F41, paso 6)', (tester) async {
    await deleteItemRows(db, processedDocumentIdFor('darwin'));
    await pumpText(tester);

    await selectExtracted(tester, 'En 1859 publicó El origen de las especies.');
    await tester.tap(find.byTooltip(es.highlightAddToTimeline));
    await tester.pumpAndSettle();

    expect(byKey('dated-event-form-title'), findsNothing);
    expect(find.text(es.timelineFactSourceNotProcessed), findsOneWidget);
    expect(find.text(es.organizedGoToInbox), findsOneWidget);
    expect(await stored(), isEmpty);
  });

  group('desde un PDF o una página web', () {
    late _FakeSelection selection;

    Future<void> pumpToolbar(WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Consumer(
            builder: (context, ref, _) => SizedBox(
              height: 600,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: documentHighlightToolbar(
                      context,
                      ref,
                      anchors: const TextSelectionToolbarAnchors(
                        primaryAnchor: Offset(200, 300),
                        secondaryAnchor: Offset(200, 320),
                      ),
                      selection: selection,
                      text: (
                        itemId: 'darwin',
                        renditionId: 'texto-darwin',
                        content: text,
                        markdown: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    (int, int) at(String quote) {
      final start = text.indexOf(quote);
      return (start, start + quote.length);
    }

    testWidgets('lo seleccionado se ubica en el texto extraído, y la '
        'selección se quita', (tester) async {
      const quote = 'En 1859 publicó El origen de las especies.';
      final (start, end) = at(quote);
      selection = _FakeSelection(
        SelectionLocation.found([(start: start, end: end)]),
      );
      await pumpToolbar(tester);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(selection.clears, 1);
      expect(yearField(tester), '1859');
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      expect(fact.itemId, processedDocumentIdFor('darwin'));
      expect(fact.renditionId, 'texto-darwin');
      expect(fact.startOffset, start);
      expect(fact.endOffset, end);
      expect(fact.excerpt, quote);
      expect(fact.date.year, 1859);
    });

    testWidgets('una selección que cruza páginas va de la primera letra a la '
        'última', (tester) async {
      final (aStart, _) = at('En 1859');
      final (_, bEnd) = at('de 1914 a 1918');
      selection = _FakeSelection(
        SelectionLocation.found([
          (start: aStart, end: aStart + 20),
          (start: bEnd - 14, end: bEnd),
        ]),
      );
      await pumpToolbar(tester);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('dated-event-form-title'), 'Varias cosas');
      await tester.tap(byKey('dated-event-form-save'));
      await tester.pumpAndSettle();

      final fact = (await stored()).single;
      expect(fact.startOffset, aStart);
      expect(fact.endOffset, bEnd);
      expect(fact.excerpt, text.substring(aStart, bEnd));
      // La primera fecha de lo seleccionado.
      expect(fact.date.year, 1859);
    });

    testWidgets('sin fecha en lo seleccionado, el formulario abre vacío', (
      tester,
    ) async {
      final (start, end) = at('El origen de las especies');
      selection = _FakeSelection(
        SelectionLocation.found([(start: start, end: end)]),
      );
      await pumpToolbar(tester);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(yearField(tester), isEmpty);
      expect(byKey('dated-event-form-quote'), findsOneWidget);
    });

    testWidgets('lo que no se pudo ubicar se avisa y no abre nada', (
      tester,
    ) async {
      selection = _FakeSelection(
        const SelectionLocation.failed(HighlightIssue.scanned),
      );
      await pumpToolbar(tester);

      await tester.tap(find.byTooltip(es.highlightAddToTimeline));
      await tester.pumpAndSettle();

      expect(find.text(es.documentHighlightScanned), findsOneWidget);
      expect(byKey('dated-event-form-heading'), findsNothing);
      expect(selection.clears, 0);
      expect(await stored(), isEmpty);
    });
  });

  group('una selección que no es un tramo del texto', () {
    testWidgets('no abre el formulario', (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        host(
          Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return TextButton(onPressed: () {}, child: const Text('nada'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('nada'));

      for (final (start, end) in [
        (5, 5),
        (9, 3),
        (-1, 4),
        (0, text.length + 1),
      ]) {
        await addRangeToTimeline(
          context,
          captured,
          itemId: 'darwin',
          renditionId: 'texto-darwin',
          content: text,
          start: start,
          end: end,
        );
        await tester.pumpAndSettle();

        expect(
          byKey('dated-event-form-heading'),
          findsNothing,
          reason: '$start-$end',
        );
      }
      // Y el texto entero sí es un tramo.
      unawaited(
        addRangeToTimeline(
          context,
          captured,
          itemId: 'darwin',
          renditionId: 'texto-darwin',
          content: text,
          start: 0,
          end: text.length,
        ),
      );
      await tester.pumpAndSettle();
      expect(byKey('dated-event-form-heading'), findsOneWidget);
    });
  });
}

/// Lo seleccionado sobre un documento real, como lo da un visor.
class _FakeSelection implements DocumentSelection {
  _FakeSelection(this.location);

  final SelectionLocation location;
  int clears = 0;

  @override
  Future<String> text() async => 'seleccionado';

  @override
  Future<SelectionLocation> locate() async => location;

  @override
  Future<HighlightOutcome> highlight({
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  }) async => const HighlightOutcome.created([]);

  @override
  Future<void> clear() async => clears++;
}
