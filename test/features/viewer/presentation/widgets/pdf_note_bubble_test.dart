import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El globito de las notas sobre la página de un PDF (F45, paso 8c): en el
/// margen derecho de la página a la altura de su renglón, del mismo tamaño
/// con cualquier zoom y con la letra al doble, con los tonos del papel en
/// los dos modos y, para el lector de pantalla, lo mismo que el del texto.
void main() {
  final es = AppLocalizationsEs();

  TextNote note(String id, {HighlightColor color = HighlightColor.lime}) =>
      TextNote(
        id: id,
        origin: TextNoteOrigin.note,
        target: const TextNoteTarget.processedText('doc'),
        excerpt: 'Rubicón',
        note: 'El río $id',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        start: 0,
        end: 7,
        color: color,
      );

  Future<List<List<TextNote>>> pump(
    WidgetTester tester, {
    required List<TextNote> notes,
    Size page = const Size(300, 400),
    Rect line = const Rect.fromLTRB(40, 100, 200, 112),
    ThemeData? theme,
    double textScale = 1,
  }) async {
    final opened = <List<TextNote>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: page,
              child: Stack(
                children: [
                  PdfNoteBubble(
                    spot: (
                      line: const PdfRect(40, 300, 200, 288),
                      notes: notes,
                    ),
                    lineInPage: line,
                    pageSize: page,
                    onOpen: opened.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('en el margen derecho de la página, centrado en su renglón, y '
      'del mismo tamaño con la letra al doble', (tester) async {
    final first = note('a');
    await pump(tester, notes: [first], textScale: 2);
    final bubble = tester.getRect(find.byKey(const Key('text-note-bubble-a')));
    expect(bubble.right, lessThanOrEqualTo(300));
    expect(bubble.right, greaterThanOrEqualTo(300 - 4));
    expect(bubble.center.dy, closeTo(106, 0.01));
    expect(bubble.size, const Size.square(PdfNoteBubble.touchSize));
    final face = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('text-note-bubble-a')),
        matching: find.byType(Container),
      ),
    );
    expect(face, const Size.square(PdfNoteBubble.size));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no se sale de la página arriba ni abajo', (tester) async {
    expect(
      PdfNoteBubble.placeIn(
        const Size(300, 400),
        const Rect.fromLTRB(40, 0, 200, 4),
      ).top,
      0,
    );
    expect(
      PdfNoteBubble.placeIn(
        const Size(300, 400),
        const Rect.fromLTRB(40, 396, 200, 400),
      ).bottom,
      400,
    );
  });

  testWidgets('para el lector de pantalla: «Nota: …, sobre "…"», un botón que '
      'la abre; con varias en el renglón, cuántas son', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = await pump(tester, notes: [note('a')]);
    final node = tester.getSemantics(
      find.byKey(const Key('text-note-bubble-a')),
    );
    expect(node.label, es.f45S8bBubble('El río a', 'Rubicón'));
    expect(
      node,
      matchesSemantics(
        label: es.f45S8bBubble('El río a', 'Rubicón'),
        isButton: true,
        hasTapAction: true,
        onTapHint: es.f45S8bOpenNote,
      ),
    );
    tester.semantics.tap(
      find.semantics.byLabel(es.f45S8bBubble('El río a', 'Rubicón')),
    );
    expect([for (final notes in opened) notes.single.id], ['a']);

    final several = await pump(tester, notes: [note('a'), note('b')]);
    expect(
      tester.getSemantics(find.byKey(const Key('text-note-bubble-a'))).label,
      es.f45S8bBubbleSeveral(2),
    );
    expect(find.text('2'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel(es.f45S8bBubbleSeveral(2)));
    expect([for (final n in several.single) n.id], ['a', 'b']);
    semantics.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('con los tonos del papel también en modo '
        '${dark ? 'oscuro' : 'claro'}: la página es blanca', (tester) async {
      await pump(
        tester,
        notes: [note('a', color: HighlightColor.coral)],
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      final face = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('text-note-bubble-a')),
          matching: find.byType(Container),
        ),
      );
      final decoration = face.decoration! as BoxDecoration;
      expect(decoration.color, HighlightPalette.onPaper(HighlightColor.coral));
      expect(
        (decoration.border! as Border).top.color,
        HighlightPalette.lineOnPaper(HighlightColor.coral),
      );
    });
  }
}
