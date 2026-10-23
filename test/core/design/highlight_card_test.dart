import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/highlight_card.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La ficha de un resaltado ya hecho (F38), sola: avisa lo que la persona
/// decide, sin saber dónde se guarda.
void main() {
  final es = AppLocalizationsEs();

  Highlight highlight({
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  }) => Highlight(
    id: 'h1',
    renditionId: 'r1',
    startOffset: 0,
    endOffset: 9,
    excerpt: 'Conocemos',
    createdAt: DateTime.utc(2026),
    color: color,
    style: style,
    note: note,
  );

  final looks = <(HighlightColor?, HighlightStyle)>[];
  final notes = <String?>[];
  var deleted = 0;

  setUp(() {
    looks.clear();
    notes.clear();
    deleted = 0;
  });

  Future<void> open(WidgetTester tester, Highlight highlight) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showHighlightCard(
                context,
                highlight: highlight,
                onLook: (color, style) => looks.add((color, style)),
                onNote: notes.add,
                onDelete: () => deleted++,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// Los botones de color marcados como elegidos.
  List<HighlightColor> selectedColors(WidgetTester tester) => [
    for (final color in HighlightColor.values)
      if (tester
          .widget<HighlightColorDot>(
            find.byKey(Key('card-color-${color.name}')),
          )
          .selected)
        color,
  ];

  testWidgets('muestra el fragmento, su color y su nota', (tester) async {
    await open(
      tester,
      highlight(color: HighlightColor.violet, note: 'Importante'),
    );

    expect(find.text(es.highlightCardTitle), findsOneWidget);
    expect(find.text('Conocemos'), findsOneWidget);
    expect(find.text('Importante'), findsOneWidget);
    expect(selectedColors(tester), [HighlightColor.violet]);
  });

  testWidgets('elegir otro color avisa con el estilo que ya tenía y mueve '
      'la tilde, sin cerrar', (tester) async {
    await open(
      tester,
      highlight(color: HighlightColor.violet, style: HighlightStyle.underline),
    );

    await tester.tap(find.byKey(const Key('card-color-orange')));
    await tester.pumpAndSettle();

    expect(looks, [(HighlightColor.orange, HighlightStyle.underline)]);
    expect(selectedColors(tester), [HighlightColor.orange]);
    expect(find.text(es.highlightCardTitle), findsOneWidget);
  });

  testWidgets('pasar a subrayado, y de vuelta a fondo, avisa con el color '
      'que ya tenía', (tester) async {
    await open(tester, highlight(color: HighlightColor.turquoise));

    await tester.tap(find.text(es.highlightStyleUnderline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.highlightStyleFill));
    await tester.pumpAndSettle();

    expect(looks, [
      (HighlightColor.turquoise, HighlightStyle.underline),
      (HighlightColor.turquoise, HighlightStyle.fill),
    ]);
  });

  testWidgets('un resaltado de los de antes, sin color, conserva el de '
      'siempre al cambiarle el estilo', (tester) async {
    await open(tester, highlight());

    expect(selectedColors(tester), isEmpty);
    await tester.tap(find.text(es.highlightStyleUnderline));
    await tester.pumpAndSettle();

    expect(looks, [(null, HighlightStyle.underline)]);
  });

  testWidgets('guardar la nota avisa con el texto recortado y cierra', (
    tester,
  ) async {
    await open(tester, highlight());

    await tester.enterText(find.byType(TextField), '  Una nota  ');
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(notes, ['Una nota']);
    expect(find.text(es.highlightCardTitle), findsNothing);
  });

  testWidgets('guardar la nota en blanco la borra', (tester) async {
    await open(tester, highlight(note: 'Vieja'));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(notes, [null]);
  });

  testWidgets('quitar el resaltado avisa y cierra', (tester) async {
    await open(tester, highlight());

    await tester.tap(find.text(es.detailRemoveHighlight));
    await tester.pumpAndSettle();

    expect(deleted, 1);
    expect(find.text(es.highlightCardTitle), findsNothing);
  });

  testWidgets('cerrarla sin tocar nada no avisa de nada', (tester) async {
    await open(tester, highlight(note: 'Una nota'));

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text(es.highlightCardTitle), findsNothing);
    expect(looks, isEmpty);
    expect(notes, isEmpty);
    expect(deleted, 0);
  });
}
