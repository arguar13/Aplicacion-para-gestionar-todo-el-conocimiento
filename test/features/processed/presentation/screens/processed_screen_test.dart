import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../processed_ui_fixture.dart';

/// La pantalla «Procesado» (F41, paso 2): la lista como la Biblioteca, con sus
/// filtros, su orden, la selección de a varios y el vacío.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(tester, harness);
    await goAndSettle(tester, harness, RoutePaths.processed);
    expect(find.byType(ProcessedScreen), findsOneWidget);
  }

  /// Cierra el panel de filtros tocando afuera, arriba de la lista: no en el
  /// riel, que queda fuera de la barrera del panel.
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(600, 8));
    await tester.pumpAndSettle();
  }

  List<String> rowTitles(WidgetTester tester) => [
    for (final card in tester.widgetList<ProcessedDocumentCard>(
      find.byType(ProcessedDocumentCard),
    ))
      card.document.title,
  ];

  group('vacío', () {
    testWidgets('sin nada procesado lo dice y lleva a la Bandeja', (
      tester,
    ) async {
      await open(tester);

      expect(find.text(es.processedEmptyTitle), findsOneWidget);
      // Sin fuentes triadas de antes, no hay nada que volver a triar.
      expect(find.text(es.processedRetriage), findsNothing);

      await tester.tap(find.text(es.processedEmptyAction));
      await tester.pumpAndSettle();
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('con fuentes triadas antes de que existiera Procesado ofrece '
        '«Volver a triar» (paso 4: ver `retriage_test.dart`)', (tester) async {
      await insertItemRows(harness.database, id: 'a', title: 'Vieja');
      await insertItemRows(harness.database, id: 'b', title: 'Otra vieja');
      await harness.markTriaged('a');
      await harness.markTriaged('b');

      await open(tester);

      expect(find.text(es.processedEmptyPending(2)), findsOneWidget);
      // Debajo de «Ir a la Bandeja», con menos peso: de contorno.
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(es.processedRetriage),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('la lista', () {
    setUp(() async {
      await harness.saveTextSource('roma', title: 'Roma');
      await harness.saveTextSource('grecia', title: 'Grecia');
    });

    testWidgets('cada fila tiene su título, las partes que tiene y cuándo se '
        'actualizó; tocarla abre el documento', (tester) async {
      await harness.processTextAndNotes('roma', notes: ['Una idea mía']);
      await harness.processTextAndNotes('grecia');

      await open(tester);

      expect(rowTitles(tester).toSet(), {'Roma', 'Grecia'});
      final roma = find.ancestor(
        of: find.text('Roma'),
        matching: find.byType(ProcessedDocumentCard),
      );
      for (final part in [es.processedSectionText, es.processedSectionNotes]) {
        expect(
          find.descendant(of: roma, matching: find.text(part)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: roma, matching: find.textContaining('Actualizado')),
        findsOneWidget,
      );
      // Para el lector de pantalla, las partes en una frase.
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(es.processedRowParts('Texto, Notas'))),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Roma'));
      await tester.pumpAndSettle();
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('se filtra por las partes que tiene', (tester) async {
      await harness.processTextAndNotes('roma', notes: ['Una idea mía']);
      await harness.processTextAndNotes('grecia');
      await open(tester);

      await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilterChip, es.processedSectionNotes),
      );
      await tester.pumpAndSettle();
      await closeSheet(tester);
      await tester.pumpAndSettle();

      expect(rowTitles(tester), ['Roma']);
    });

    testWidgets('se busca en el texto de sus partes', (tester) async {
      await harness.processTextAndNotes('roma', notes: ['Los acueductos']);
      await harness.processTextAndNotes('grecia');
      await open(tester);

      await tester.enterText(find.byType(TextField), 'acueductos');
      await tester.pumpAndSettle();

      expect(rowTitles(tester), ['Roma']);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(es.processedSearchEmpty('zzz')), findsOneWidget);
    });

    testWidgets('se ordena por título', (tester) async {
      await harness.processTextAndNotes('grecia');
      await harness.processTextAndNotes('roma');
      await open(tester);
      // Lo último trabajado, arriba: el orden de siempre.
      expect(rowTitles(tester), ['Roma', 'Grecia']);

      await tester.tap(find.byKey(const Key('processed-sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<ProcessedSort>,
          es.processedSortTitle,
        ),
      );
      await tester.pumpAndSettle();

      expect(rowTitles(tester), ['Grecia', 'Roma']);
    });

    testWidgets('se eligen de a varios y se mandan a la papelera, con su '
        '«Deshacer»', (tester) async {
      await harness.processTextAndNotes('roma');
      await harness.processTextAndNotes('grecia');
      await open(tester);

      await tester.longPress(find.text('Roma'));
      await tester.pumpAndSettle();
      expect(find.text(es.librarySelectedCount(1)), findsOneWidget);

      await tester.tap(find.byTooltip(es.libraryBulkDeleteTooltip));
      await tester.pumpAndSettle();

      expect(rowTitles(tester), ['Grecia']);
      expect(find.text(es.trashMoved(1)), findsOneWidget);

      await tester.tap(find.text(es.trashUndo));
      await tester.pumpAndSettle();
      expect(rowTitles(tester).toSet(), {'Roma', 'Grecia'});
    });

    testWidgets('en un teléfono y con la letra al doble no desborda, ni la '
        'lista ni su panel de filtros', (tester) async {
      await harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('Una idea')]),
        ),
      });
      await pumpPhoneWithLargeText(tester, harness);
      await goAndSettle(tester, harness, RoutePaths.processed);

      expect(tester.takeException(), isNull);
      expect(find.byType(ProcessedDocumentCard), findsOneWidget);

      await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('con un filtro que no deja nada, ofrece limpiarlo', (
      tester,
    ) async {
      await harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      });
      await open(tester);

      await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilterChip, es.processedSectionFragments),
      );
      await tester.pumpAndSettle();
      await closeSheet(tester);
      await tester.pumpAndSettle();

      expect(find.text(es.processedFilterEmpty), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, es.libraryClearFilters),
      );
      await tester.pumpAndSettle();
      expect(rowTitles(tester), ['Roma']);
    });
  });
}
