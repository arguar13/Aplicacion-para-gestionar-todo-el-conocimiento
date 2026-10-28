import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/widgets/retriage/retriage_picker.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/item_rows.dart';
import '../../../../../support/library_harness.dart';
import '../../../../../support/triage_sheet.dart';
import '../../processed_ui_fixture.dart';

/// Si el selector de «Volver a triar» está abierto.
final picker = find.byKey(const Key('retriage-picker'));

/// La lista del selector: la última de sus partes desplazables —antes está el
/// campo del buscador—.
final pickerList = find
    .descendant(of: picker, matching: find.byType(Scrollable))
    .last;

/// Espera a que se abra la hoja «¿Qué va a Procesado?», ya con lo que el
/// documento tiene.
Future<void> opensSheet(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(triageSheet, findsOneWidget);
}

/// «Volver a triar» (F41, paso 4): el selector con toda la Biblioteca, la
/// misma hoja con lo que el documento ya tiene —agregar, actualizar,
/// reemplazar o quitar—, el aviso con «Deshacer», y los accesos desde la
/// Bandeja, el documento procesado, el vacío de «Procesado» y el detalle.
/// Contra la base real del arnés.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<Map<ProcessedSection, List<String>>> partsOf(String sourceId) async {
    final rows =
        await (harness.database.select(harness.database.processedParts)
              ..where((p) => p.documentId.equals(harness.documentOf(sourceId)))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    return {
      for (final section in ProcessedSection.values)
        if (rows.any((row) => row.section == section))
          section: [
            for (final row in rows)
              if (row.section == section) row.content,
          ],
    };
  }

  List<String> candidates(WidgetTester tester) => [
    for (final tile in tester.widgetList<RetriageCandidateTile>(
      find.byType(RetriageCandidateTile),
    ))
      tile.item.title,
  ];

  Finder candidate(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(RetriageCandidateTile),
  );

  Future<void> openInboxPicker(WidgetTester tester) async {
    await pumpApp(tester, harness);
    await goAndSettle(tester, harness, RoutePaths.inbox);
    await tester.tap(find.byKey(const Key('inbox-retriage')));
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);
  }

  Future<void> choose(WidgetTester tester, String title) async {
    await tester.tap(candidate(title));
    await opensSheet(tester);
    expect(picker, findsNothing);
  }

  Future<void> pickChange(
    WidgetTester tester,
    ProcessedSection section,
    String label,
  ) async {
    final segmented = find.byKey(Key('triage-change-${section.name}'));
    await tester.ensureVisible(segmented);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: segmented, matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('triage-done')));
    await tester.pumpAndSettle();
  }

  group('el selector', () {
    setUp(() async {
      await harness.saveTextSource('roma', title: 'Roma');
      await harness.saveTextSource('grecia', title: 'Grecia');
      await insertItemRows(
        harness.database,
        id: 'nota',
        title: 'Mi nota',
        kind: SourceKind.manualNote,
      );
      await harness.processTextAndNotes('roma');
      await harness.markTriaged('roma');
    });

    testWidgets('está arriba en la Bandeja y lista todas las fuentes —no las '
        'notas propias ni lo procesado—, con lo ya procesado marcado', (
      tester,
    ) async {
      await openInboxPicker(tester);

      expect(candidates(tester).toSet(), {'Roma', 'Grecia'});
      expect(find.text('Mi nota'), findsNothing);
      expect(
        find.descendant(
          of: candidate('Roma'),
          matching: find.byKey(const Key('retriage-processed-chip')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: candidate('Grecia'),
          matching: find.byKey(const Key('retriage-processed-chip')),
        ),
        findsNothing,
      );
      // Para el lector de pantalla, la fila es un botón con todo en una
      // frase.
      expect(
        tester.getSemantics(candidate('Roma')),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          label:
              'Roma, ${SourceKind.webPage.label(es)}, '
              '${es.processedRetriageProcessedChip}',
        ),
      );
    });

    testWidgets('el buscador y el filtro de la Bandeja acotan la lista', (
      tester,
    ) async {
      await openInboxPicker(tester);

      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'Grecia',
      );
      await tester.pumpAndSettle();
      expect(candidates(tester), ['Grecia']);

      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retriage-filter-triaged')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(600, 8));
      await tester.pumpAndSettle();

      expect(candidates(tester), ['Roma']);
    });

    testWidgets('con la R también se abre, y Escape lo cierra sin elegir', (
      tester,
    ) async {
      await pumpApp(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.inbox);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(triageSheet, findsNothing);
    });
  });

  testWidgets('trae de a cien: «Cargar más» suma la tanda siguiente', (
    tester,
  ) async {
    for (var i = 0; i < 101; i++) {
      await insertItemRows(
        harness.database,
        id: 'f$i',
        title: 'Fuente $i',
        createdAt: DateTime(2026, 9, 2).add(Duration(minutes: i)),
      );
    }
    await openInboxPicker(tester);
    final more = find.text(es.libraryLoadMore);

    /// Todas las fuentes de la lista, recorriéndola hasta el final.
    Future<Set<String>> scrollAll() async {
      final seen = <String>{};
      for (var i = 0; i < 80; i++) {
        final before = seen.length;
        seen.addAll(candidates(tester));
        if (before == seen.length && i > 0) break;
        await tester.drag(pickerList, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      return seen;
    }

    final first = await scrollAll();
    expect(first, hasLength(100));
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect({...first, ...await scrollAll()}, hasLength(101));
    expect(more, findsNothing);
  });

  group('al elegir', () {
    setUp(() async {
      await harness.saveTextSource('roma', title: 'Roma');
      await harness.saveTextSource('grecia', title: 'Grecia');
    });

    testWidgets('una ya triada abre la hoja con lo que tiene: quitar sus notas '
        'las saca, su estado no se toca, y «Deshacer» las devuelve', (
      tester,
    ) async {
      await harness.processTextAndNotes('roma', notes: ['Una idea mía']);
      await harness.markTriaged('roma');
      await openInboxPicker(tester);
      await choose(tester, 'Roma');

      expect(find.text(es.processedTriageExisting(1)), findsWidgets);
      await pickChange(
        tester,
        ProcessedSection.notes,
        es.processedTriageChangeRemove,
      );
      await done(tester);

      expect(await partsOf('roma'), {
        ProcessedSection.text: [
          'La república romana cayó. César cruzó el Rubicón.',
        ],
      });
      expect(await stateOf('roma'), ItemState.triaged);
      expect(
        find.text(es.processedRetriageUpdatedSnack('Roma')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
      await tester.pumpAndSettle();

      expect((await partsOf('roma'))[ProcessedSection.notes], ['Una idea mía']);
      expect(await stateOf('roma'), ItemState.triaged);
    });

    testWidgets('una que espera queda triada con su documento, «Ver» lo abre, '
        'y «Deshacer» la devuelve a la Bandeja sin él', (tester) async {
      await openInboxPicker(tester);
      await choose(tester, 'Grecia');

      await finishTriageWithText(tester);

      expect(await stateOf('grecia'), ItemState.triaged);
      expect((await partsOf('grecia')).keys, [ProcessedSection.text]);
      expect(
        find.text(es.processedRetriageTriagedSnack('Grecia')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
      await tester.pumpAndSettle();

      expect(await partsOf('grecia'), isEmpty);
      expect(await stateOf('grecia'), ItemState.processed);
    });

    testWidgets('«Ver» abre el documento procesado', (tester) async {
      await openInboxPicker(tester);
      await choose(tester, 'Grecia');
      await finishTriageWithText(tester);

      await tester.tap(find.byKey(const Key('retriage-view')));
      await tester.pumpAndSettle();

      expect(find.text(es.processedOpenSource), findsOneWidget);
    });

    testWidgets(
      'pedir lo que ya está avisa que no cambió nada, sin «Deshacer»',
      (tester) async {
        await harness.processTextAndNotes('roma');
        await harness.markTriaged('roma');
        await openInboxPicker(tester);
        await choose(tester, 'Roma');

        await tester.tap(find.byKey(const Key('triage-switch-text')));
        await tester.pumpAndSettle();
        // La vista previa ya lo dice antes de «Listo».
        expect(
          find.textContaining(es.processedTriageTallyNone),
          findsOneWidget,
        );
        await done(tester);

        expect(
          find.text(es.processedRetriageUnchangedSnack('Roma')),
          findsOneWidget,
        );
        expect(find.widgetWithText(SnackBarAction, es.inboxUndo), findsNothing);
      },
    );

    testWidgets('una que espera y ya tenía eso mismo igual queda triada, y '
        'eso sí se deshace', (tester) async {
      await harness.processTextAndNotes('grecia');
      await openInboxPicker(tester);
      await choose(tester, 'Grecia');

      await finishTriageWithText(tester);

      expect(await stateOf('grecia'), ItemState.triaged);
      expect(
        find.text(es.processedRetriageTriagedSnack('Grecia')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(SnackBarAction, es.inboxUndo));
      await tester.pumpAndSettle();
      expect(await stateOf('grecia'), ItemState.processed);
      expect((await partsOf('grecia')).keys, [ProcessedSection.text]);
    });

    testWidgets('cerrar la hoja no cambia nada', (tester) async {
      await openInboxPicker(tester);
      await choose(tester, 'Grecia');

      await tester.tap(find.byKey(const Key('triage-switch-text')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await partsOf('grecia'), isEmpty);
      expect(await stateOf('grecia'), ItemState.processed);
    });
  });

  testWidgets(
    'decisión J: triar en la Bandeja una fuente que ya tiene su '
    'documento —por una nota extraída antes— lo muestra y no lo pisa: agrega',
    (tester) async {
      await harness.saveTextSource('roma', title: 'Roma');
      await harness.process('roma', {
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([
            ProcessedDraft.written('La nota de antes'),
          ]),
        ),
      });
      await pumpApp(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.inbox);

      await tester.tap(find.text(es.inboxActionTriage));
      await tester.pumpAndSettle();

      expect(triageSheet, findsOneWidget);
      expect(find.text(es.processedTriageExisting(1)), findsOneWidget);
      // Las notas que ya tiene se pueden quitar o reemplazar, pero arrancan en
      // «Agregar».
      final notes = tester.widget<SegmentedButton<ProcessedChange>>(
        find.byKey(const Key('triage-change-notes')),
      );
      expect(notes.selected, {ProcessedChange.add});

      await finishTriageWithText(tester);

      expect(await stateOf('roma'), ItemState.triaged);
      expect(await partsOf('roma'), {
        ProcessedSection.text: [
          'La república romana cayó. César cruzó el Rubicón.',
        ],
        ProcessedSection.notes: ['La nota de antes'],
      });
    },
  );

  group('los otros accesos', () {
    setUp(() async {
      await harness.saveTextSource('roma', title: 'Roma');
    });

    testWidgets('el documento procesado vuelve a triar su fuente', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await harness.markTriaged('roma');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));

      await tester.tap(find.text(es.processedRetriage));
      await tester.pumpAndSettle();

      expect(picker, findsNothing);
      expect(triageSheet, findsOneWidget);
      expect(
        find.textContaining(es.processedTriageExisting(1)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('triage-switch-text')));
      await tester.pumpAndSettle();
      await pickChange(
        tester,
        ProcessedSection.text,
        es.processedTriageChangeRemove,
      );
      await done(tester);

      expect(await partsOf('roma'), isEmpty);
      // Ya se está mirando el documento: el aviso no ofrece «Ver».
      expect(find.byKey(const Key('retriage-view')), findsNothing);
    });

    testWidgets('con la fuente en la papelera está apagado, y dice por qué', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await trashItemRows(harness.database, 'roma');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(es.processedRetriage),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.byTooltip(es.processedRetriageSourceInTrash), findsOneWidget);
    });

    testWidgets('el vacío de «Procesado», con fuentes triadas de antes, abre '
        'el selector (decisión D)', (tester) async {
      await harness.markTriaged('roma');
      await pumpApp(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.processed);

      await tester.tap(find.text(es.processedRetriage));
      await tester.pumpAndSettle();

      expect(picker, findsOneWidget);
      await choose(tester, 'Roma');
      await finishTriageWithText(tester);
      expect((await partsOf('roma')).keys, [ProcessedSection.text]);
      expect(await stateOf('roma'), ItemState.triaged);
    });

    testWidgets('el detalle de una fuente triada lo ofrece; el de una que '
        'espera, no —tiene «Triar ahora»—', (tester) async {
      await harness.saveTextSource('grecia', title: 'Grecia');
      await harness.markTriaged('roma');
      await pumpApp(tester, harness);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail('grecia'));
      expect(find.byKey(const Key('detail-retriage')), findsNothing);
      expect(find.text(es.inboxTriageNow), findsOneWidget);

      await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));
      await tester.tap(find.byKey(const Key('detail-retriage')));
      await tester.pumpAndSettle();
      expect(triageSheet, findsOneWidget);
      await finishTriageWithText(tester);

      expect((await partsOf('roma')).keys, [ProcessedSection.text]);
      expect(await stateOf('roma'), ItemState.triaged);
    });
  });

  group('se ve bien', () {
    setUp(() async {
      await harness.saveTextSource(
        'roma',
        title: 'Un título larguísimo para ver si la fila se desborda o no',
      );
      await harness.processTextAndNotes('roma', notes: ['Una idea mía']);
      await harness.markTriaged('roma');
    });

    testWidgets('con la letra al doble, en un teléfono angosto: el selector y '
        'la hoja con las cuatro opciones, sin desbordarse', (tester) async {
      await pumpPhoneWithLargeText(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.inbox);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('inbox-retriage')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(picker, findsOneWidget);

      await tester.tap(find.byType(RetriageCandidateTile));
      await tester.pumpAndSettle();
      expect(triageSheet, findsOneWidget);
      final text = find.byKey(const Key('triage-switch-text'));
      await tester.scrollUntilVisible(
        text,
        120,
        scrollable: find.descendant(
          of: triageSheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(text);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('triage-change-text')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('triage-change-notes')),
        120,
        scrollable: find.descendant(
          of: triageSheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin animaciones, el selector aparece sin deslizarse', (
      tester,
    ) async {
      await pumpApp(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.inbox);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('inbox-retriage')));
      await tester.pump();
      // En el primer cuadro ya está donde queda: no sube desde abajo.
      expect(picker, findsOneWidget);
      final first = tester.getTopLeft(picker).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(picker).dy, first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con animaciones, sube desde abajo', (tester) async {
      await pumpApp(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.inbox);

      await tester.tap(find.byKey(const Key('inbox-retriage')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final early = tester.getTopLeft(picker).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(picker).dy, lessThan(early));
    });
  });
}
