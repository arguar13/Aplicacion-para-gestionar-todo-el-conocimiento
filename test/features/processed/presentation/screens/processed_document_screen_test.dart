import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart'
    show StudyMarksCompanion;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organized_line.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/generate_quiz_button.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/usecases/drop_original_copy.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
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

    testWidgets('«Volver a triar» está al lado del enlace, prendido (paso 4: '
        'ver `retriage_test.dart`)', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(es.processedRetriage),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
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

  group('las palabras clave, de las dos formas', () {
    /// Dos oraciones con sus palabras clave: «república» y «Rubicón», y otra
    /// vez «república» en la segunda, que la lista compacta no repite.
    const keywordsText =
        'La república romana cayó. César cruzó el Rubicón y la república.';

    Future<String> processKeywords() async {
      await harness.saveTextSource(
        'claves',
        title: 'Claves',
        text: keywordsText,
      );
      for (final (word, from) in [
        ('república', 0),
        ('Rubicón', 0),
        ('república', 30),
      ]) {
        final start = keywordsText.indexOf(word, from);
        await harness.database
            .into(harness.database.studyMarks)
            .insert(
              StudyMarksCompanion.insert(
                id: 'clave-$start',
                renditionId: 'rend-claves',
                kind: StudyMarkKind.keyword,
                origin: ContentOrigin.ai,
                startOffset: start,
                endOffset: start + word.length,
                excerpt: word,
                createdAt: DateTime(2026, 10, 20, 12),
              ),
            );
      }
      return harness.process('claves', {
        ProcessedSection.keywords: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      });
    }

    Finder compact() => find.byKey(const Key('processed-keywords-compact'));

    testWidgets('arriba la lista compacta, en el orden del texto y sin '
        'repetir; plegadas, las oraciones', (tester) async {
      final id = await processKeywords();
      await open(tester, id);

      expect(
        [
          for (final chip in tester.widgetList<ActionChip>(
            find.descendant(of: compact(), matching: find.byType(ActionChip)),
          ))
            (chip.label as Text).data,
        ],
        ['república', 'Rubicón'],
      );
      // Las oraciones, plegadas hasta pedirlas.
      expect(find.text('La república romana cayó.'), findsNothing);
      await tester.tap(find.text(es.processedKeywordsSentences(2)));
      await tester.pumpAndSettle();
      expect(find.text('La república romana cayó.'), findsOneWidget);
    });

    testWidgets('cada oración lleva su clave marcada en el rosa de estudiar', (
      tester,
    ) async {
      final id = await processKeywords();
      await open(tester, id);
      await tester.tap(find.text(es.processedKeywordsSentences(2)));
      await tester.pumpAndSettle();

      final pink = StudyPalette.of(Brightness.light).keyword;
      final marked = <String>[];
      // Cada oración es un `SelectableText.rich`: se puede seleccionar.
      for (final selectable in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      )) {
        selectable.textSpan?.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.backgroundColor == pink &&
              span.text != null) {
            marked.add(span.text!);
          }
          return true;
        });
      }
      expect(marked, containsAll(['república', 'Rubicón']));
    });

    testWidgets('tocar una palabra la abre en su lugar de la fuente', (
      tester,
    ) async {
      final id = await processKeywords();
      await open(tester, id);

      await tester.tap(
        find.descendant(of: compact(), matching: find.text('Rubicón')),
      );
      await tester.pumpAndSettle();

      final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      final start = keywordsText.indexOf('Rubicón');
      expect(reading.itemId, 'claves');
      expect(reading.jump, (start: start, end: start + 'Rubicón'.length));
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
      // Arriba va la tarjeta de estudiar (decisión K): el texto, más abajo.
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text(es.processedSectionText),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.ensureVisible(find.text(es.processedSectionText));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.processedSectionText));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('processed-page-of')),
        find.byType(ListView),
        const Offset(0, -200),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('processed-page-of')), findsOneWidget);
    });

    testWidgets('uno que no existe lo dice', (tester) async {
      await open(tester, 'no-existe');

      expect(find.text(es.processedDocumentNotFound), findsOneWidget);
    });
  });

  group('se estudia acá (decisión K)', () {
    testWidgets('su Mapa y sus Tarjetas de repaso, las piezas de siempre '
        'sobre el documento, debajo de sus secciones', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      final map = find.byType(LocalGraphPanel);
      final cards = find.byType(FlashcardSection);
      expect(map, findsOneWidget);
      expect(cards, findsOneWidget);
      expect(tester.widget<LocalGraphPanel>(map).item.id, id);
      final flashcards = tester.widget<FlashcardSection>(cards);
      expect(flashcards.item.id, id);
      expect(flashcards.processed, isTrue);
      expect(flashcards.fromSourceItemId, 'roma');
      expect(
        tester.getTopLeft(map).dy,
        greaterThan(tester.getTopLeft(section(ProcessedSection.text)).dy),
      );
    });

    testWidgets('la tarjeta de estudiar sobre su texto propio, con el '
        'resumen, la síntesis y las palabras clave para leer: acá se estudia', (
      tester,
    ) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      expect(find.byKey(const Key('study-document-card')), findsOneWidget);
      for (final key in [
        'study-extract-summary',
        'study-extract-synthesis',
        'study-extract-keywords',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('sin texto propio —solo notas— no hay qué estudiar', (
      tester,
    ) async {
      final id = await harness.process('roma', {
        ProcessedSection.notes: SectionEdit.add(
          const SectionInput.drafts([ProcessedDraft.written('Una idea')]),
        ),
      });
      await open(tester, id);

      expect(find.byKey(const Key('study-document-card')), findsNothing);
    });

    testWidgets('«De la fuente»: las tarjetas que ya tenía, plegadas, sin '
        'moverse de ella', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: 'roma', front: '¿Quién cruzó?', back: 'César');
      await open(tester, id);

      final group = find.byKey(const Key('flashcards-from-source'));
      expect(group, findsOneWidget);
      expect(find.text(es.flashcardsFromSourceCount(1)), findsOneWidget);
      expect(find.text('¿Quién cruzó?'), findsNothing);

      await tester.tap(find.text(es.flashcardsFromSource));
      await tester.pumpAndSettle();

      expect(find.text('¿Quién cruzó?'), findsOneWidget);
      final rows = await harness.database
          .select(harness.database.flashcards)
          .get();
      expect(rows.single.itemId, 'roma');
    });

    testWidgets('arriba, el derivado ✨, el quiz y «Más» con organizar y '
        'buscar fechas sobre el documento; sin copia del original, no se '
        'ofrece borrarla', (tester) async {
      final queue = FakeAiOrganizeQueue();
      harness = await LibraryHarness.create(
        extraOverrides: [aiOrganizeQueueProvider.overrideWithValue(queue)],
      );
      await harness.saveTextSource('roma', title: 'Roma');
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      final bar = find.byType(AppBar);
      expect(
        find.descendant(
          of: bar,
          matching: find.byType(GenerateDerivedNoteButton),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.byType(GenerateQuizButton)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('processed-more')));
      await tester.pumpAndSettle();
      expect(find.text(es.sourcePanelOrganizeWithAi), findsOneWidget);
      expect(find.text(es.processedOrganizeWithAiHint), findsOneWidget);
      expect(find.text(es.sourcePanelFindDates), findsOneWidget);
      expect(find.text(es.processedDeleteOriginalCopy), findsNothing);

      await tester.tap(find.text(es.sourcePanelOrganizeWithAi));
      await tester.pumpAndSettle();
      expect(queue.organizeNowCalls, [id]);

      await tester.tap(find.byKey(const Key('processed-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.sourcePanelFindDates));
      await tester.pumpAndSettle();
      expect(queue.dateRequests, [
        [id],
      ]);
    });

    testWidgets('lo que la IA organizó con el documento, en su línea', (
      tester,
    ) async {
      harness = await LibraryHarness.create(
        extraOverrides: [
          aiItemSummaryProvider.overrideWith(
            (ref, itemId) => itemId == harness.documentOf('roma')
                ? const AiItemSummary(undone: true)
                : const AiItemSummary(),
          ),
        ],
      );
      await harness.saveTextSource('roma', title: 'Roma');
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      final line = find.byType(AiOrganizedLine);
      expect(line, findsOneWidget);
      expect(tester.widget<AiOrganizedLine>(line).itemId, id);
    });

    testWidgets('sin nada que contar de la IA, ni la línea', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await open(tester, id);

      expect(find.byType(AiOrganizedLine), findsNothing);
      expect(find.byKey(const Key('processed-ai-line')), findsNothing);
    });

    testWidgets('en la papelera se lee, pero no se estudia ni se le pide nada '
        'a la IA', (tester) async {
      final id = await harness.processTextAndNotes('roma');
      await trashItemRows(harness.database, id);
      await open(tester, id);

      expect(find.byType(LocalGraphPanel), findsNothing);
      expect(find.byType(FlashcardSection), findsNothing);
      expect(find.byType(GenerateQuizButton), findsNothing);
      expect(find.byType(GenerateDerivedNoteButton), findsNothing);
      expect(find.byKey(const Key('processed-more')), findsNothing);
    });
  });

  group(
    '«Borrar la copia del original, quedarme con el texto» (decisión K)',
    () {
      late _FakeDrop drop;
      late _UndoSpy process;

      Future<String> openWithCopy(
        WidgetTester tester, {
        bool keptText = true,
        Failure? failure,
      }) async {
        drop = _FakeDrop(keptText: keptText, failure: failure);
        harness = await LibraryHarness.create(
          extraOverrides: [
            processedOriginalProvider.overrideWith(
              (ref, id) => Stream.value(_copyOf(id)),
            ),
            dropOriginalCopyProvider.overrideWithValue(drop),
            processSourceUseCaseProvider.overrideWith(
              (ref) =>
                  process = _UndoSpy(ref.watch(processedRepositoryProvider)),
            ),
          ],
        );
        await harness.saveTextSource('roma', title: 'Roma');
        final id = await harness.processTextAndNotes('roma');
        await open(tester, id);
        await tester.tap(find.byKey(const Key('processed-more')));
        await tester.pumpAndSettle();
        return id;
      }

      testWidgets('con copia, «Más» la ofrece con lo que hace; sin preguntar, '
          'la suelta de la fuente viva y avisa que el texto quedó, con '
          '«Deshacer»', (tester) async {
        await openWithCopy(tester);

        expect(find.text(es.processedDeleteOriginalCopyHint), findsOneWidget);
        await tester.tap(find.text(es.processedDeleteOriginalCopy));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(drop.calls, ['roma']);
        expect(
          find.text(es.processedOriginalCopyDroppedKeptText),
          findsOneWidget,
        );

        await tester.tap(find.text(es.contentTrashUndo));
        await tester.pumpAndSettle();

        expect(process.undone, [drop.undo]);
      });

      testWidgets('si ya tenía su Texto, el aviso solo dice dónde quedó la '
          'copia', (tester) async {
        await openWithCopy(tester, keptText: false);
        await tester.tap(find.text(es.processedDeleteOriginalCopy));
        await tester.pumpAndSettle();

        expect(find.text(es.processedOriginalCopyDropped), findsOneWidget);
      });

      testWidgets('si no se pudo, dice por qué', (tester) async {
        const failure = Failure.validation(message: 'la fuente no está');
        await openWithCopy(tester, failure: failure);
        await tester.tap(find.text(es.processedDeleteOriginalCopy));
        await tester.pumpAndSettle();

        expect(find.text(failure.localizedMessage(es)), findsOneWidget);
        expect(find.text(es.contentTrashUndo), findsNothing);
      });

      testWidgets('sin copia no se ofrece', (tester) async {
        final id = await harness.processTextAndNotes('roma');
        await open(tester, id);
        await tester.tap(find.byKey(const Key('processed-more')));
        await tester.pumpAndSettle();

        expect(find.text(es.processedDeleteOriginalCopy), findsNothing);
      });

      testWidgets('con la fuente en la papelera tampoco: la copia es lo '
          'único que queda de su original', (tester) async {
        harness = await LibraryHarness.create(
          extraOverrides: [
            processedOriginalProvider.overrideWith(
              (ref, id) => Stream.value(_copyOf(id)),
            ),
          ],
        );
        await harness.saveTextSource('roma', title: 'Roma');
        final id = await harness.processTextAndNotes('roma');
        await trashItemRows(harness.database, 'roma');
        await open(tester, id);
        await tester.tap(find.byKey(const Key('processed-more')));
        await tester.pumpAndSettle();

        expect(find.text(es.sourcePanelOrganizeWithAi), findsOneWidget);
        expect(find.text(es.processedDeleteOriginalCopy), findsNothing);
      });
    },
  );
}

/// Una copia del original de [documentId], como la deja el paso 1b.
ProcessedOriginal _copyOf(String documentId) => ProcessedOriginal(
  documentId: documentId,
  renditionId: 'copia-$documentId',
  relativePath: 'originales/$documentId/original/roma.pdf',
  kind: RenditionKind.pdf,
  sizeBytes: 2048,
  copiedAt: DateTime(2026, 10, 28),
  sourceFilePath: 'originales/roma/roma.pdf',
);

/// Soltar la copia sin la base: lo que importa acá es lo que hace la pantalla.
class _FakeDrop implements DropOriginalCopy {
  _FakeDrop({required this.keptText, this.failure});

  final bool keptText;
  final Failure? failure;
  final calls = <String>[];
  final undo = const ProcessUndo(
    documentId: 'procesado',
    previousStatus: ProcessedDocumentStatus.active,
    previous: {},
  );

  @override
  Future<Either<Failure, DroppedOriginalCopy>> call(String sourceItemId) async {
    calls.add(sourceItemId);
    final failure = this.failure;
    if (failure != null) return left(failure);
    return right(
      DroppedOriginalCopy(
        outcome: ProcessOutcome(
          documentId: 'procesado',
          created: false,
          sections: const {},
          undo: undo,
          original: OriginalOutcome.removed,
        ),
        keptText: keptText,
      ),
    );
  }
}

/// El caso de uso de siempre, que anota lo que se deshace sin hacerlo.
class _UndoSpy extends ProcessSourceUseCase {
  _UndoSpy(super.repository);

  final undone = <ProcessUndo>[];

  @override
  Future<Either<Failure, Unit>> undo(ProcessUndo undo) async {
    undone.add(undo);
    return right(unit);
  }
}
