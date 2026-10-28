import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../processed_ui_fixture.dart';

/// El documento procesado abierto (F41, paso 2): su fuente, sus secciones
/// plegables y editables con «Deshacer», el texto de a una página, los
/// fragmentos que abren el original y el lector en voz alta.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  const text = 'La república romana cayó. César cruzó el Rubicón.';

  setUp(() async {
    harness = await LibraryHarness.create();
    await harness.saveTextSource('roma', title: 'Roma');
  });

  Future<void> open(WidgetTester tester, String documentId) async {
    await pumpApp(tester, harness);
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.processedDocument(documentId),
    );
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
  }

  Finder section(ProcessedSection section) =>
      find.byKey(Key('processed-section-${section.name}'));

  group('la fuente', () {
    testWidgets('«Ver el original en la Biblioteca» abre la fuente', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      await tester.tap(find.text(es.processedOpenSource));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Roma')),
        findsWidgets,
      );
    });

    testWidgets('si la fuente está en la papelera lo dice y lleva a ella', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await trashItemRows(harness.database, 'roma');
      await open(tester, id);

      expect(find.text(es.processedSourceInTrash), findsOneWidget);
      expect(find.text(es.processedOpenSource), findsNothing);

      await tester.tap(find.text(es.processedOpenTrash));
      await tester.pumpAndSettle();
      expect(find.byType(TrashScreen), findsOneWidget);
    });

    testWidgets('si la fuente se borró de verdad lo dice, sin enlace ni '
        '«Volver a triar»', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await harness.container.read(libraryRepositoryProvider).deleteMany([
        'roma',
      ]);
      await harness.container.read(libraryRepositoryProvider).purge(['roma']);
      await open(tester, id);

      expect(find.text(es.processedSourceGone), findsOneWidget);
      expect(find.text(es.processedOpenSource), findsNothing);
      expect(find.text(es.processedRetriage), findsNothing);
    });

    testWidgets('«Volver a triar» está, apagado y con su motivo, hasta el '
        'paso 4', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(es.processedRetriage),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.byTooltip(es.processedRetriageSoon), findsOneWidget);
    });
  });

  group('las secciones', () {
    testWidgets('se ven las que tiene, en orden; lo elegido desplegado y el '
        'texto entero plegado', (tester) async {
      final id = await harness.processTextAndNotes(
        'roma',
        notes: ['Una idea mía'],
      );
      await open(tester, id);

      expect(section(ProcessedSection.text), findsOneWidget);
      expect(section(ProcessedSection.notes), findsOneWidget);
      expect(section(ProcessedSection.summary), findsNothing);
      expect(
        tester.getTopLeft(section(ProcessedSection.text)).dy,
        lessThan(tester.getTopLeft(section(ProcessedSection.notes)).dy),
      );
      expect(find.text('Una idea mía'), findsOneWidget);
      // El texto, plegado: no se pidió a la base.
      expect(find.text(text), findsNothing);

      await tester.tap(find.text(es.processedSectionText));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
    });

    testWidgets('solo con el texto, el texto se abre desplegado', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      expect(find.text(text), findsOneWidget);
    });

    testWidgets('el resumen se ve con sus oraciones', (tester) async {
      await harness.addSummarySentence('roma', text, 'César cruzó el Rubicón.');
      final id = await harness.process('roma', {
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });
      await open(tester, id);

      expect(section(ProcessedSection.summary), findsOneWidget);
      expect(find.text('César cruzó el Rubicón.'), findsOneWidget);
      expect(find.text(es.studySentenceCount(1)), findsOneWidget);
    });

    testWidgets('editar una parte la guarda, dice «con cambios tuyos» en la '
        'sección y «Deshacer» la devuelve', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      await tester.tap(find.byTooltip(es.processedPartMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.processedPartEdit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('processed-part-editor')),
        'La república cayó.',
      );
      await tester.tap(find.text(es.processedPartSave));
      await tester.pumpAndSettle();

      expect(find.text('La república cayó.'), findsOneWidget);
      expect(find.text(es.processedPartEdited), findsOneWidget);
      expect(find.textContaining(es.processedEditedCount(1)), findsOneWidget);

      await tester.tap(find.text(es.trashUndo));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.text(es.processedPartEdited), findsNothing);
    });

    testWidgets('una parte vacía no se guarda', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      await tester.tap(find.byTooltip(es.processedPartMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.processedPartEdit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('processed-part-editor')),
        '   ',
      );
      await tester.pump();

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, es.processedPartSave),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('quitar una nota la saca y «Deshacer» la devuelve en su '
        'lugar', (tester) async {
      final id = await harness.processTextAndNotes(
        'roma',
        notes: ['Primera', 'Segunda'],
      );
      await open(tester, id);

      final menus = find.descendant(
        of: section(ProcessedSection.notes),
        matching: find.byTooltip(es.processedPartMenu),
      );
      await tester.tap(menus.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.processedPartRemove));
      await tester.pumpAndSettle();

      expect(find.text('Primera'), findsNothing);
      expect(find.text(es.processedPartRemoved), findsOneWidget);

      await tester.tap(find.text(es.trashUndo));
      await tester.pumpAndSettle();
      expect(find.text('Primera'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Primera')).dy,
        lessThan(tester.getTopLeft(find.text('Segunda')).dy),
      );
    });

    testWidgets('un fragmento abre el original justo en su lugar', (
      tester,
    ) async {
      final id = await harness.process('roma', {
        ProcessedSection.fragments: harness.fragmentOf(
          'roma',
          text,
          'César cruzó el Rubicón.',
        ),
      });
      await open(tester, id);

      await tester.tap(find.text(es.processedOpenInOriginal));
      await tester.pumpAndSettle();

      final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      final start = text.indexOf('César');
      expect(reading.itemId, 'roma');
      expect(reading.jump, (start: start, end: start + 23));
    });

    testWidgets('con la fuente en la papelera, un fragmento no ofrece abrir '
        'el original', (tester) async {
      final id = await harness.process('roma', {
        ProcessedSection.fragments: harness.fragmentOf(
          'roma',
          text,
          'César cruzó el Rubicón.',
        ),
      });
      await trashItemRows(harness.database, 'roma');
      await open(tester, id);

      expect(find.text('César cruzó el Rubicón.'), findsOneWidget);
      expect(find.text(es.processedOpenInOriginal), findsNothing);
    });
  });

  group('el texto, de a una página', () {
    // Unas tres páginas de 8.000 caracteres, cada oración con su número.
    final long = [
      for (var i = 0; i < 1200; i++) 'Oración número $i del libro.',
    ].join(' ');

    setUp(() async {
      await harness.saveTextSource('libro', title: 'Libro', text: long);
    });

    testWidgets('se ve una página, se pasa a la siguiente y se salta a una', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('libro');
      await open(tester, id);

      expect(
        find.textContaining('Oración número 0 del libro.'),
        findsOneWidget,
      );
      expect(find.textContaining('Oración número 1199 '), findsNothing);
      // Se pidió a la base esa página sola, no un tramo más largo: abrir un
      // libro cuesta lo que cuesta una página.
      expect(
        harness.container.exists(
          processedPartsProvider((
            documentId: id,
            section: ProcessedSection.text,
            offset: 0,
            limit: 1,
          )),
        ),
        isTrue,
      );
      final pageOf = find.byKey(const Key('processed-page-of'));
      expect(
        find.descendant(
          of: pageOf,
          matching: find.textContaining('Página 1 de'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(es.processedPageNext));
      await tester.pumpAndSettle();
      expect(find.textContaining('Oración número 0 del libro.'), findsNothing);
      expect(
        find.descendant(
          of: pageOf,
          matching: find.textContaining('Página 2 de'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(es.processedPageLast));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Oración número 1199 del libro.'),
        findsOneWidget,
      );

      await tester.tap(pageOf);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('processed-page-jump')), '1');
      await tester.tap(find.text(es.processedPageJumpGo));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Oración número 0 del libro.'),
        findsOneWidget,
      );
    });

    testWidgets('el salto no acepta una página que no existe', (tester) async {
      final id = await harness.processTextAndNotes('libro');
      await open(tester, id);

      await tester.tap(find.byKey(const Key('processed-page-of')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('processed-page-jump')),
        '999',
      );
      await tester.pump();

      final go = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, es.processedPageJumpGo),
      );
      expect(go.onPressed, isNull);
    });
  });

  group('escuchar', () {
    testWidgets('el documento se ofrece entero al lector en voz alta, cada '
        'parte con su nombre, y el resumen también solo', (tester) async {
      await harness.addSummarySentence('roma', text, 'César cruzó el Rubicón.');
      final id = await harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });
      await open(tester, id);

      final readable = harness.container.read(currentReadableProvider);
      expect(readable, isNotNull);
      expect(readable!.title, 'Roma');
      expect(
        [for (final s in readable.segmentsOf(ReadScope.all)) s.spoken],
        [
          'La república romana cayó. César cruzó el Rubicón.',
          'César cruzó el Rubicón.',
        ],
      );
      expect(
        [for (final s in readable.segmentsOf(ReadScope.summary)) s.spoken],
        ['César cruzó el Rubicón.'],
      );
      expect(readable.offers(ReadScope.synthesis), isFalse);
      // Cada pedazo, en su parte: así se resalta en su lugar.
      expect(readable.segments.map((s) => s.sourceKey).toSet(), hasLength(2));
      expect(find.byKey(const Key('processed-listen-summary')), findsOneWidget);
      // El del texto, al desplegarlo.
      await tester.tap(find.text(es.processedSectionText));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('processed-listen-all')), findsOneWidget);
    });
  });

  group('el documento', () {
    testWidgets('en la papelera se lee igual, lo dice y se restaura', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await trashItemRows(harness.database, id);
      await open(tester, id);

      expect(find.text(es.processedDocumentInTrash), findsOneWidget);
      expect(find.text(text), findsOneWidget);

      await tester.tap(find.byKey(const Key('processed-restore')));
      await tester.pumpAndSettle();
      expect(find.text(es.processedDocumentInTrash), findsNothing);
    });

    testWidgets('mandarlo a la papelera vuelve, con «Deshacer»', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      await tester.tap(find.byTooltip(es.detailDelete));
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedDocumentScreen), findsNothing);
      expect(find.text(es.trashMoved(1)), findsOneWidget);
    });

    testWidgets('en un teléfono y con la letra al doble no desborda', (
      tester,
    ) async {
      final long = [
        for (var i = 0; i < 600; i++) 'Oración número $i del libro.',
      ].join(' ');
      await harness.saveTextSource('libro', title: 'Libro', text: long);
      final id = await harness.process('libro', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('Una idea')]),
        ),
        ProcessedSection.fragments: harness.fragmentOf(
          'libro',
          long,
          'Oración número 3 del libro.',
        ),
      });
      await pumpPhoneWithLargeText(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.text(es.processedSectionText));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('processed-page-of')), findsOneWidget);
    });

    testWidgets('uno que no existe lo dice', (tester) async {
      await open(tester, 'no-existe');

      expect(find.text(es.processedDocumentNotFound), findsOneWidget);
    });
  });
}
