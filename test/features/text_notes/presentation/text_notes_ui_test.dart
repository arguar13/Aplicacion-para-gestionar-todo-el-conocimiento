import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/screens/transcript_follow_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/repositories/text_note_repository.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/library_harness.dart';
import '../../creations/report/support/report_harness.dart';
import '../../creations/report/support/sample_reports.dart';
import '../../processed/presentation/processed_ui_fixture.dart';

/// Las notas en el texto, la interfaz (F45, paso 8b): ponerlas sobre lo
/// elegido o sobre el texto entero, verlas —el punteado y el globito en el
/// margen—, abrirlas, editarlas, cambiarles el color, borrarlas con
/// «Deshacer», y «Notas (N)» con «Sin lugar» al final e ir a su lugar. En un
/// original de la Biblioteca (el libro) y en el texto de un procesado.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  const text =
      'La república romana cayó. César cruzó el Rubicón. '
      'Su concilio votó la ley.';
  const library = TextNoteTarget.sourceOriginal(
    sourceId: 'roma',
    renditionId: 'rend-roma',
  );

  setUp(() async => harness = await LibraryHarness.create());

  TextNoteRepository notes() =>
      harness.container.read(textNoteRepositoryProvider);

  /// Las notas de [target], leídas con el reloj de verdad: la consulta que
  /// se mira espera un cuadro de la base, que el reloj falso de la prueba no
  /// deja pasar.
  Future<List<TextNote>> notesOf(
    WidgetTester tester,
    TextNoteTarget target,
  ) async => (await tester.runAsync(() => notes().watchNotes(target).first))!;

  Future<TextNote> noteOn(
    TextNoteTarget target,
    String excerpt, {
    String note = 'Una nota',
    HighlightColor color = HighlightColor.lime,
  }) async {
    final start = text.indexOf(excerpt);
    return (await notes().create(
      target: target,
      start: start,
      end: start + excerpt.length,
      excerpt: excerpt,
      note: note,
      color: color,
    )).getRight().toNullable()!;
  }

  Future<void> saveBook() => harness.saveTextSource(
    'roma',
    title: 'Roma',
    text: text,
    kind: SourceKind.document,
    originalName: 'roma.txt',
    originalBytes: text.codeUnits,
  );

  /// El libro de la fuente, en el marco: lo que abre «Ampliar» en la
  /// Biblioteca.
  Future<void> openLibraryBook(WidgetTester tester) async {
    await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));
    await tester.tap(find.byKey(const Key('embedded-viewer-read-as-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reading-frame')), findsOneWidget);
  }

  /// Elige [excerpt] en el texto del libro y abre la barrita.
  Future<void> select(WidgetTester tester, String excerpt) async {
    final editable = tester.state<EditableTextState>(
      find.byType(EditableText).first,
    );
    final start = editable.textEditingValue.text.indexOf(excerpt);
    editable
      ..hideToolbar()
      ..userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(
          selection: const TextSelection.collapsed(offset: 0),
        ),
        SelectionChangedCause.drag,
      )
      ..userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + excerpt.length,
          ),
        ),
        SelectionChangedCause.drag,
      )
      ..showToolbar();
    await tester.pumpAndSettle();
  }

  /// Toca el texto del libro en la letra [offset] de lo que se ve.
  Future<void> tapAt(WidgetTester tester, int offset) async {
    final editable = tester.state<EditableTextState>(
      find.byType(EditableText).first,
    );
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: offset),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();
  }

  /// Los pedazos del texto pintados con el punteado de una nota.
  /// Los pedazos pintados con [style] que cumplen [paints], en todo el texto
  /// que se ve: el de un `Text` y el de un `SelectableText`, que no arma un
  /// `RichText` sino que pinta su `RenderEditable`.
  List<String> painted(WidgetTester tester, bool Function(TextStyle) paints) {
    final out = <String>[];
    bool visit(InlineSpan span) {
      final style = span.style;
      if (span is TextSpan &&
          style != null &&
          paints(style) &&
          (span.text ?? '').isNotEmpty) {
        out.add(span.text!);
      }
      return true;
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren(visit);
    }
    for (final editable
        in tester.allRenderObjects.whereType<RenderEditable>()) {
      editable.text?.visitChildren(visit);
    }
    return out;
  }

  /// Los pedazos con el punteado de una nota.
  List<String> dotted(WidgetTester tester) => painted(
    tester,
    (style) => style.decorationStyle == TextDecorationStyle.dotted,
  );

  Future<void> openNotesList(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reading-frame-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-more-notes')));
    await tester.pumpAndSettle();
  }

  group('en el original de la Biblioteca (el libro)', () {
    testWidgets('«Nota» sobre lo elegido: el color, nunca en blanco, y se ve '
        'con el punteado y el globito, que dice qué es', (tester) async {
      final semantics = tester.ensureSemantics();
      await saveBook();
      await pumpApp(tester, harness);
      await openLibraryBook(tester);

      await select(tester, 'César cruzó');
      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('text-note-editor')), findsOneWidget);
      expect(find.text('«César cruzó»'), findsOneWidget);

      // En blanco no se guarda: lo dice y la hoja queda.
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bEditorBlank), findsOneWidget);
      expect(await notesOf(tester, library), isEmpty);

      await tester.tap(find.byKey(const Key('text-note-color-coral')));
      await tester.enterText(
        find.byKey(const Key('text-note-field')),
        '  Cruzó en el 49  ',
      );
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();

      final [note] = await notesOf(tester, library);
      expect(note.note, 'Cruzó en el 49');
      expect(note.excerpt, 'César cruzó');
      expect(note.color, HighlightColor.coral);
      expect(text.substring(note.start!, note.end), 'César cruzó');
      expect(note.renditionId, 'rend-roma');

      expect(dotted(tester), ['César cruzó']);
      final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
      expect(bubble, findsOneWidget);
      expect(
        tester.getSemantics(bubble).label,
        es.f45S8bBubble('Cruzó en el 49', 'César cruzó'),
      );
      // Al costado del texto, sin taparlo.
      expect(
        tester.getRect(bubble).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(EditableText)).right),
      );
      semantics.dispose();
    });

    testWidgets('cancelar no pone nada; cerrar la hoja con algo escrito la '
        'guarda', (tester) async {
      await saveBook();
      await pumpApp(tester, harness);
      await openLibraryBook(tester);

      await select(tester, 'Rubicón');
      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('text-note-field')), 'No');
      await tester.tap(find.byKey(const Key('text-note-cancel')));
      await tester.pumpAndSettle();
      expect(await notesOf(tester, library), isEmpty);

      await select(tester, 'Rubicón');
      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('text-note-field')), 'Sí');
      // Se cierra tocando afuera, sin «Listo».
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect([for (final n in await notesOf(tester, library)) n.note], ['Sí']);
    });

    testWidgets('el globito y el pedazo abren la nota: editar, cambiar de '
        'color y borrar con «Deshacer», sin tocar el documento', (
      tester,
    ) async {
      await saveBook();
      final note = await noteOn(library, 'concilio', note: 'El Senado');
      await pumpApp(tester, harness);
      await openLibraryBook(tester);

      // Tocar el pedazo.
      await tapAt(tester, text.indexOf('concilio') + 2);
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
      expect(find.text('«concilio»'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Tocar el globito.
      await tester.tap(find.byKey(Key('text-note-bubble-${note.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);

      // Editar: en blanco no; con algo, sí.
      await tester.tap(find.byKey(const Key('text-note-card-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('text-note-card-field')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('text-note-card-save')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bEditorBlank), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('text-note-card-field')),
        'El Senado, en realidad',
      );
      await tester.tap(find.byKey(const Key('text-note-card-save')));
      await tester.pumpAndSettle();
      expect(find.text('El Senado, en realidad'), findsOneWidget);
      expect(
        (await notesOf(tester, library)).single.note,
        'El Senado, en realidad',
      );

      // El color, en el acto.
      await tester.tap(find.byKey(const Key('text-note-card-color-violet')));
      await tester.pumpAndSettle();
      expect(
        (await notesOf(tester, library)).single.color,
        HighlightColor.violet,
      );

      // Borrar, y «Deshacer».
      await tester.tap(find.byKey(const Key('text-note-card-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${note.id}')), findsNothing);
      expect(find.text(es.f45S8bDeleted), findsOneWidget);
      expect(await notesOf(tester, library), isEmpty);
      expect(dotted(tester), isEmpty);
      await tester.tap(find.byKey(const Key('text-note-undo')));
      await tester.pumpAndSettle();
      final [back] = await notesOf(tester, library);
      expect(back.id, note.id);
      expect(back.note, 'El Senado, en realidad');
      expect(dotted(tester), ['concilio']);

      // El documento no cambió.
      final rendition = await (harness.database.select(
        harness.database.renditions,
      )..where((r) => r.id.equals('rend-roma'))).getSingle();
      expect(rendition.content, text);
    });

    testWidgets('«Notas (N)»: en el orden del texto —con la de un resaltado '
        'de antes mezclada— y «Sin lugar» al final; tocar una va a su lugar '
        'y la abre; «Nota sobre el texto entero» va a «Sin lugar»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await saveBook();
      final last = await noteOn(library, 'ley', note: 'La última');
      final first = await noteOn(library, 'romana', note: 'La primera');
      final lost = await noteOn(library, 'votó', note: 'Perdida');
      // Su pedazo ya no está en el texto.
      await harness.database.customStatement(
        "UPDATE text_notes SET excerpt = 'no está', start_offset = NULL, "
        "end_offset = NULL WHERE id = '${lost.id}'",
      );
      // Un resaltado de antes, con su nota (F38).
      final cesar = text.indexOf('César');
      await harness.container
          .read(organizeRepositoryProvider)
          .createHighlight(
            renditionId: 'rend-roma',
            startOffset: cesar,
            endOffset: cesar + 5,
            excerpt: 'César',
            note: 'Del resaltado',
            // Con color: el de siempre es el mismo que marca un momento.
            color: HighlightColor.lime,
          );
      await pumpApp(tester, harness);
      await openLibraryBook(tester);

      // El pedazo del resaltado de antes abre su ficha de siempre, que lleva
      // la nota con su estilo.
      await tapAt(tester, text.indexOf('César') + 1);
      expect(find.text(es.highlightCardTitle), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bNotesMenu(4)), findsOneWidget);
      await tester.tap(find.byKey(const Key('reading-more-notes')));
      await tester.pumpAndSettle();

      double top(String note) => tester.getTopLeft(find.text(note)).dy;
      expect(top('La primera'), lessThan(top('Del resaltado')));
      expect(top('Del resaltado'), lessThan(top('La última')));
      expect(top('La última'), lessThan(top(es.f45S8bNotesNoPlace)));
      expect(top(es.f45S8bNotesNoPlace), lessThan(top('Perdida')));
      expect(
        tester
            .getSemantics(find.byKey(Key('text-note-tile-${first.id}')))
            .label,
        es.f45S8bBubble('La primera', 'romana'),
      );

      // Ir a su lugar: se marca un momento y se abre.
      await tester.tap(find.text('La última'));
      await tester.pump();
      await tester.pump();
      final flash = Theme.of(
        tester.element(find.byKey(const Key('reading-frame'))),
      ).colorScheme.tertiaryContainer;
      final flashed = painted(
        tester,
        (style) => style.backgroundColor == flash,
      );
      expect(flashed, ['ley']);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${last.id}')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // La sin lugar se abre sin ir a ningún lado.
      await openNotesList(tester);
      await tester.tap(find.text('Perdida'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${lost.id}')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Una nota sobre el texto entero.
      await openNotesList(tester);
      await tester.tap(find.byKey(const Key('text-notes-new-whole-0')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bWholeText), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('text-note-field')),
        'Sobre todo',
      );
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();
      final whole = (await notesOf(tester, library)).last;
      expect(whole.wholeText, isTrue);
      expect(whole.note, 'Sobre todo');

      await openNotesList(tester);
      expect(find.text(es.f45S8bNotesMenu(5)), findsOneWidget);
      expect(top(es.f45S8bNotesNoPlace), lessThan(top('Sobre todo')));
      semantics.dispose();
    });

    testWidgets('sin notas, la lista lo dice', (tester) async {
      await saveBook();
      await pumpApp(tester, harness);
      await openLibraryBook(tester);

      await openNotesList(tester);
      expect(find.text(es.f45S8bNotesMenu(0)), findsOneWidget);
      expect(find.byKey(const Key('text-notes-empty')), findsOneWidget);
    });
  });

  group('en Procesado', () {
    Future<String> processBook() async {
      await saveBook();
      return harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      }, original: const OriginalEdit(ProcessedChange.add));
    }

    testWidgets('la copia del original lleva sus notas, no las de la '
        'Biblioteca; «Nota» va también ahí, sin los colores de resaltar', (
      tester,
    ) async {
      final id = await processBook();
      final copy = TextNoteTarget.processedOriginal(id);
      await noteOn(library, 'romana', note: 'De la Biblioteca');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('embedded-viewer-read-as-book')));
      await tester.pumpAndSettle();
      expect(dotted(tester), isEmpty);

      await select(tester, 'Rubicón');
      expect(find.byKey(const Key('highlight-color-coral')), findsNothing);
      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('text-note-field')),
        'En la copia',
      );
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();

      expect(
        [for (final n in await notesOf(tester, copy)) n.note],
        ['En la copia'],
      );
      expect(
        [for (final n in await notesOf(tester, library)) n.note],
        ['De la Biblioteca'],
      );
      expect(dotted(tester), ['Rubicón']);
    });

    testWidgets('el texto de un procesado: el punteado, el globito, el '
        'pedazo que la abre y «Notas (N)» que va a su lugar', (tester) async {
      final semantics = tester.ensureSemantics();
      final id = await processBook();
      final own = TextNoteTarget.processedText(id);
      final note = await noteOn(own, 'Rubicón', note: 'El río');
      await noteOn(library, 'romana', note: 'De la Biblioteca');
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('processed-read-text')));
      await tester.pumpAndSettle();

      expect(dotted(tester), ['Rubicón']);
      final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
      expect(bubble, findsOneWidget);
      expect(
        tester.getSemantics(bubble).label,
        es.f45S8bBubble('El río', 'Rubicón'),
      );

      // Tocar el pedazo.
      final paragraph = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('Rubicón'),
      );
      final box = tester.renderObject<RenderParagraph>(paragraph);
      final plain = box.text.toPlainText();
      final boxes = box.getBoxesForSelection(
        TextSelection(
          baseOffset: plain.indexOf('Rubicón'),
          extentOffset: plain.indexOf('Rubicón') + 3,
        ),
      );
      await tester.tapAt(box.localToGlobal(boxes.first.toRect().center));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // «Notas (N)»: solo las de este texto.
      await openNotesList(tester);
      expect(find.text(es.f45S8bNotesMenu(1)), findsOneWidget);
      expect(find.text('De la Biblioteca'), findsNothing);
      await tester.tap(find.text('El río'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('«Nota» en el menú de lo elegido del texto de un procesado', (
      tester,
    ) async {
      final id = await processBook();
      final own = TextNoteTarget.processedText(id);
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('processed-read-text')));
      await tester.pumpAndSettle();

      final paragraph = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('Rubicón'),
      );
      final box = tester.renderObject<RenderParagraph>(paragraph);
      final plain = box.text.toPlainText();
      final at = box.getBoxesForSelection(
        TextSelection(
          baseOffset: plain.indexOf('Rubicón'),
          extentOffset: plain.indexOf('Rubicón') + 3,
        ),
      );
      await tester.longPressAt(box.localToGlobal(at.first.toRect().center));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.highlightAddNote));
      await tester.pumpAndSettle();
      expect(find.text('«Rubicón»'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('text-note-field')), 'Río');
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();

      final [note] = await notesOf(tester, own);
      expect(note.excerpt, 'Rubicón');
      expect(text.substring(note.start!, note.end), 'Rubicón');
      expect(dotted(tester), ['Rubicón']);
    });
  });

  group('en una transcripción y en lo creado', () {
    testWidgets('la transcripción de un audio: «Nota» sobre lo elegido, el '
        'punteado, el globito y «Notas (N)»', (tester) async {
      await harness.saveTextSource(
        'voz',
        title: 'Una charla',
        text: text,
        kind: SourceKind.audio,
      );
      const voice = TextNoteTarget.sourceOriginal(
        sourceId: 'voz',
        renditionId: 'rend-voz',
      );
      await tester.pumpWidget(
        harness.wrap(const TranscriptFollowScreen(itemId: 'voz')),
      );
      await tester.pumpAndSettle();

      await select(tester, 'Rubicón');
      await tester.tap(find.byTooltip(es.highlightAddNote));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('text-note-field')), 'Río');
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();

      final [note] = await notesOf(tester, voice);
      expect(note.excerpt, 'Rubicón');
      expect(dotted(tester), ['Rubicón']);
      final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
      expect(bubble, findsOneWidget);
      expect(
        tester.getRect(bubble).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(EditableText)).right),
      );

      // Tocar el pedazo la abre.
      await tapAt(tester, text.indexOf('Rubicón') + 1);
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await openNotesList(tester);
      expect(find.text(es.f45S8bNotesMenu(1)), findsOneWidget);
      expect(find.text('Río'), findsOneWidget);
    });

    testWidgets('un informe: sus notas son sobre el informe entero, en '
        '«Notas (N)»', (tester) async {
      final h = await ReportHarness.create();
      await h.processed('p-1', 'Éxodo');
      final creation = await h.ready(sampleReport());
      await h.open(tester, '/creations/${creation.id}');

      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bNotesMenu(0)), findsOneWidget);
      await tester.tap(find.byKey(const Key('reading-more-notes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('text-notes-new-whole-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('text-note-field')),
        'Repasar la sección 2',
      );
      await tester.tap(find.byKey(const Key('text-note-done')));
      await tester.pumpAndSettle();

      final [note] = (await tester.runAsync(
        () => h.container
            .read(textNoteRepositoryProvider)
            .watchNotes(TextNoteTarget.creation(creation.id))
            .first,
      ))!;
      expect(note.wholeText, isTrue);
      await tester.tap(find.byKey(const Key('reading-frame-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reading-more-notes')));
      await tester.pumpAndSettle();
      expect(find.text(es.f45S8bNotesNoPlace), findsOneWidget);
      expect(find.text('Repasar la sección 2'), findsOneWidget);
      expect(find.text(es.f45S8bWholeText), findsOneWidget);
    });
  });

  group('en un teléfono angosto con la letra al doble', () {
    /// Lo que se lee pasa a un teléfono de 360 con la letra al doble. Se
    /// llega con la pantalla ancha: lo que hay antes del marco no es de este
    /// paso.
    Future<void> goNarrow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
    }

    testWidgets('el libro: el globito en el margen, al lado del texto y sin '
        'taparlo, y nada desborda', (tester) async {
      await saveBook();
      final note = await noteOn(library, 'Rubicón', note: 'El río');
      await pumpApp(tester, harness);
      await openLibraryBook(tester);
      await goNarrow(tester);

      final bubble = tester.getRect(
        find.byKey(Key('text-note-bubble-${note.id}')),
      );
      final textRect = tester.getRect(find.byType(EditableText));
      expect(bubble.left, greaterThanOrEqualTo(textRect.right));
      expect(bubble.right, lessThanOrEqualTo(360));
      // El margen es el de siempre: el texto no se angostó.
      expect(textRect.left, 22);
      expect(textRect.right, 360 - 22);
      expect(tester.takeException(), isNull);

      await openNotesList(tester);
      expect(find.text('El río'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('El río'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el texto de un procesado: lo mismo', (tester) async {
      await saveBook();
      final id = await harness.process('roma', {
        ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
      });
      final note = await noteOn(
        TextNoteTarget.processedText(id),
        'concilio',
        note: 'El Senado',
      );
      await pumpApp(tester, harness);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      await tester.tap(find.byKey(const Key('processed-read-text')));
      await tester.pumpAndSettle();
      await goNarrow(tester);

      // Con la letra al doble, el texto queda más abajo: se baja hasta él.
      final paragraph = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('concilio'),
      );
      await tester.scrollUntilVisible(
        paragraph,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('extract-viewer-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
      expect(bubble, findsOneWidget);
      expect(
        tester.getRect(bubble).left,
        greaterThanOrEqualTo(tester.getRect(paragraph).right),
      );
      expect(tester.getRect(bubble).right, lessThanOrEqualTo(360));
      // El margen es el de siempre: el texto no se angostó.
      expect(tester.getRect(paragraph).right, 360 - 22);
      expect(tester.takeException(), isNull);
    });
  });
}
