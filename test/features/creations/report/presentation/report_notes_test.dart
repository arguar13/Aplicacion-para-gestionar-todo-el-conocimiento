import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_section_card.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/report_harness.dart';
import '../support/sample_reports.dart';

/// Las notas sobre pedazos de un informe (F45, paso 8c): elegir un pedazo
/// —de un párrafo, una pregunta, una opción— y ponerle «Nota»; verla con su
/// punteado y su globito; abrirla tocando el pedazo, sin que eso responda la
/// pregunta; «Notas (N)» que va a su lugar —desplegando su sección— y la
/// nota sobre el informe entero, que sigue igual. En claro y en oscuro, en
/// un teléfono angosto con la letra al doble y con el lector de pantalla.
void main() {
  final es = AppLocalizationsEs();
  late ReportHarness h;
  final text = ReportText.of(sampleReport());

  setUp(() async {
    h = await ReportHarness.create();
    await h.processed('p-1', 'Éxodo');
  });

  Future<StudyCreation> open(
    WidgetTester tester, {
    Map<String, Object?> options = const {},
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    final creation = await h.ready(sampleReport(), options: options);
    await h.open(
      tester,
      '/creations/${creation.id}',
      size: size,
      theme: theme,
      textScale: textScale,
    );
    return creation;
  }

  /// Una nota sobre la primera aparición de [excerpt] en la parte [place].
  Future<TextNote> noteOn(
    WidgetTester tester,
    StudyCreation creation,
    ReportTextPlace place,
    String excerpt, {
    String note = 'Una nota',
    HighlightColor color = HighlightColor.lime,
  }) async {
    final part = text.partAt(place)!;
    final start = part.start + part.text.indexOf(excerpt);
    final created = await tester.runAsync(
      () => h.container
          .read(textNoteRepositoryProvider)
          .create(
            target: TextNoteTarget.creation(creation.id),
            start: start,
            end: start + excerpt.length,
            excerpt: excerpt,
            note: note,
            color: color,
          ),
    );
    await tester.pumpAndSettle();
    return created!.getRight().toNullable()!;
  }

  Future<List<TextNote>> notesOf(
    WidgetTester tester,
    StudyCreation creation,
  ) async => (await tester.runAsync(
    () => h.container
        .read(textNoteRepositoryProvider)
        .watchNotes(TextNoteTarget.creation(creation.id))
        .first,
  ))!;

  /// El párrafo que dibuja exactamente [plain].
  Finder paragraphOf(String plain) => find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == plain,
  );

  /// El centro de [excerpt] dentro del párrafo que dibuja [plain].
  Offset centerOf(WidgetTester tester, String plain, String excerpt) {
    final box = tester.renderObject<RenderParagraph>(paragraphOf(plain));
    final at = plain.indexOf(excerpt);
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + excerpt.length),
    );
    return box.localToGlobal(boxes.first.toRect().center);
  }

  /// Los pedazos con el punteado de una nota.
  List<String> dotted(WidgetTester tester) {
    final out = <String>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.style?.decorationStyle == TextDecorationStyle.dotted &&
            (span.text ?? '').isNotEmpty) {
          out.add(span.text!);
        }
        return true;
      });
    }
    return out;
  }

  Future<void> openNotesList(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reading-frame-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-more-notes')));
    await tester.pumpAndSettle();
  }

  const paragraph =
      'El libro del Éxodo cuenta cómo Moisés guía al pueblo fuera de Egipto.';

  testWidgets('«Nota» en el menú de lo elegido: se escribe sobre su lugar del '
      'texto del informe, con el punteado y el globito al costado', (
    tester,
  ) async {
    final creation = await open(tester);

    await tester.longPressAt(centerOf(tester, paragraph, 'Moisés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.highlightAddNote));
    await tester.pumpAndSettle();
    expect(find.text('«Moisés»'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('text-note-field')),
      'El que guía',
    );
    await tester.tap(find.byKey(const Key('text-note-done')));
    await tester.pumpAndSettle();

    final [note] = await notesOf(tester, creation);
    expect(note.excerpt, 'Moisés');
    final part = text.partAt(const ReportTextPlace.block(0, 0))!;
    expect(note.start, part.start + paragraph.indexOf('Moisés'));
    expect(text.content.substring(note.start!, note.end), 'Moisés');

    expect(dotted(tester), ['Moisés']);
    final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
    expect(bubble, findsOneWidget);
    final bubbleRect = tester.getRect(bubble);
    final line = tester.getRect(paragraphOf(paragraph));
    expect(bubbleRect.left, greaterThanOrEqualTo(line.right));
    // En su margen, del tamaño de un globito, sin pisar la tarjeta.
    expect(bubbleRect.width, greaterThanOrEqualTo(18));
    final card = tester.getRect(
      find.ancestor(
        of: paragraphOf(paragraph),
        matching: find.byType(ReportSectionCard),
      ),
    );
    expect(bubbleRect.left, greaterThanOrEqualTo(card.right));
    // A la altura del renglón de su pedazo.
    final piece = centerOf(tester, paragraph, 'Moisés');
    expect(bubbleRect.top, lessThanOrEqualTo(piece.dy));
    expect(bubbleRect.bottom, greaterThanOrEqualTo(piece.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un pedazo de varias partes: de la primera letra elegida a la '
      'última, con el salto entre una y otra', (tester) async {
    final creation = await open(tester);
    // Con el ratón: se arrastra del título de la sección a «libro» del
    // párrafo de abajo, y el menú sale con el botón derecho.
    final from = centerOf(tester, 'Introducción', 'Intro');
    final to = centerOf(tester, paragraph, 'libro');
    final box = tester.renderObject<RenderParagraph>(
      paragraphOf('Introducción'),
    );
    final start = box.localToGlobal(
      box
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .first
          .toRect()
          .centerLeft,
    );
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveTo(from);
    await drag.moveTo(to);
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tapAt(
      to,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.highlightAddNote));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('text-note-field')),
      'Arranque',
    );
    await tester.tap(find.byKey(const Key('text-note-done')));
    await tester.pumpAndSettle();

    final [note] = await notesOf(tester, creation);
    final title = text.partAt(const ReportTextPlace.sectionTitle(0))!;
    expect(note.start, title.start);
    expect(note.excerpt, startsWith('Introducción${ReportText.separator}El'));
    expect(text.content.substring(note.start!, note.end), note.excerpt);
    // El punteado, en las dos partes; el globito, en la primera.
    expect(dotted(tester), containsAll(['Introducción']));
    final bubble = tester.getRect(
      find.byKey(Key('text-note-bubble-${note.id}')),
    );
    final heading = tester.getRect(paragraphOf('Introducción'));
    expect(bubble.top, lessThanOrEqualTo(heading.center.dy));
    expect(bubble.bottom, greaterThanOrEqualTo(heading.center.dy));
  });

  testWidgets('tocar el pedazo abre la nota; en una opción, tocar el pedazo '
      'no la responde y tocar fuera de él sí', (tester) async {
    final semantics = tester.ensureSemantics();
    final creation = await open(tester);
    final onParagraph = await noteOn(
      tester,
      creation,
      const ReportTextPlace.block(0, 0),
      'Moisés',
      note: 'El que guía',
    );
    final onOption = await noteOn(
      tester,
      creation,
      const ReportTextPlace.option(0, 0, 2),
      'Josué',
      note: 'Después',
      color: HighlightColor.blue,
    );
    expect(dotted(tester), unorderedEquals(['Moisés', 'Josué']));

    await tester.tapAt(centerOf(tester, paragraph, 'Moisés'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('text-note-card-${onParagraph.id}')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final josue = centerOf(tester, 'Josué', 'Josué');
    await tester.tapAt(josue);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('text-note-card-${onOption.id}')), findsOneWidget);
    expect(find.byKey(const Key('report-question-feedback')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // El globito, para el lector de pantalla.
    expect(
      tester
          .getSemantics(find.byKey(Key('text-note-bubble-${onOption.id}')))
          .label,
      es.f45S8bBubble('Después', 'Josué'),
    );

    // Fuera del pedazo, la opción se elige como siempre.
    final tile = tester.getRect(
      find.ancestor(
        of: paragraphOf('Josué'),
        matching: find.byKey(const ValueKey('report-option-2')),
      ),
    );
    await tester.tapAt(Offset(tile.right - 30, tile.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-question-feedback')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('«Notas (N)» va a su lugar —despliega su sección plegada—, la '
      'marca un momento y la abre; la nota sobre el informe entero, igual '
      'que antes', (tester) async {
    final creation = await open(tester, size: const Size(420, 900));
    final far = await noteOn(
      tester,
      creation,
      const ReportTextPlace.block(2, 0),
      'da forma',
      note: 'El pacto',
    );
    // La sección 3 se pliega.
    await tester.ensureVisible(
      find.byKey(const ValueKey('report-section-toggle-2')),
    );
    await tester.tap(find.byKey(const ValueKey('report-section-toggle-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-section-body-2')), findsNothing);
    expect(find.byKey(Key('text-note-bubble-${far.id}')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-title')),
      -300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('report-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    await openNotesList(tester);
    expect(find.text(es.f45S8bNotesMenu(1)), findsOneWidget);
    await tester.tap(find.text('El pacto'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('report-section-body-2')), findsOneWidget);
    final flashed = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          _spans(widget.text).any(
            (span) =>
                span.text == 'da forma' && span.style?.backgroundColor != null,
          ),
    );
    expect(flashed, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('text-note-card-${far.id}')), findsOneWidget);
    // Quedó a la vista.
    final rect = tester.getRect(
      paragraphOf('La Alianza del Sinaí da forma al pueblo.'),
    );
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(900));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(flashed, findsNothing);

    // La nota sobre el informe entero.
    await openNotesList(tester);
    await tester.tap(find.byKey(const Key('text-notes-new-whole-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('text-note-field')),
      'Repasar todo',
    );
    await tester.tap(find.byKey(const Key('text-note-done')));
    await tester.pumpAndSettle();
    final notes = await notesOf(tester, creation);
    expect(notes.where((n) => n.wholeText).single.note, 'Repasar todo');
    await openNotesList(tester);
    expect(find.text(es.f45S8bNotesMenu(2)), findsOneWidget);
    expect(find.text(es.f45S8bWholeText), findsOneWidget);
  });

  testWidgets('en el formato de lectura, la nota de una pregunta no se ve en '
      'el informe: va a la lista, que la abre', (tester) async {
    final creation = await open(
      tester,
      options: {CreationOptionValues.format: CreationOptionValues.document},
    );
    final note = await noteOn(
      tester,
      creation,
      const ReportTextPlace.question(0, 1),
      'llega',
      note: 'Al Sinaí',
    );
    expect(find.byKey(Key('text-note-bubble-${note.id}')), findsNothing);
    await openNotesList(tester);
    await tester.tap(find.text('Al Sinaí'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('text-note-card-${note.id}')), findsOneWidget);
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('en un teléfono de 360 con la letra al doble, '
        '${theme.name}: el globito al lado del texto, dentro de la '
        'pantalla, y nada desborda', (tester) async {
      final creation = await open(
        tester,
        size: const Size(360, 1600),
        theme: theme,
        textScale: 2,
      );
      final note = await noteOn(
        tester,
        creation,
        const ReportTextPlace.title(),
        'liberación',
        note: 'La salida',
      );
      final bubble = find.byKey(Key('text-note-bubble-${note.id}'));
      expect(bubble, findsOneWidget);
      final title = tester.getRect(find.byKey(const Key('report-title')));
      expect(tester.getRect(bubble).left, greaterThanOrEqualTo(title.right));
      expect(tester.getRect(bubble).right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });
  }
}

/// Los pedazos de texto de [span], a lo largo.
List<TextSpan> _spans(InlineSpan span) {
  final out = <TextSpan>[];
  span.visitChildren((child) {
    if (child is TextSpan && child.text != null) out.add(child);
    return true;
  });
  return out;
}
