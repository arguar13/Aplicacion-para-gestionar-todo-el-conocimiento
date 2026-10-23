import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La barrita de resaltado (F38) sola, sin ningún texto seleccionable: es
/// lo que va a usar también el PDF real y la página web.
void main() {
  final es = AppLocalizationsEs();

  const below = TextSelectionToolbarAnchors(
    primaryAnchor: Offset(200, 400),
    secondaryAnchor: Offset(200, 420),
  );

  Future<void> pump(
    WidgetTester tester, {
    TextSelectionToolbarAnchors anchors = below,
    HighlightColor underlineColor = HighlightColor.lightYellow,
    ValueChanged<HighlightColor>? onHighlight,
    ValueChanged<HighlightColor>? onUnderline,
    VoidCallback? onCopy,
    VoidCallback? onReadAloud,
    VoidCallback? onNote,
    VoidCallback? onExtract,
    VoidCallback? onCreateFlashcard,
    List<HighlightToolbarAction> moreActions = const [],
    Size size = const Size(400, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HighlightToolbar(
            anchors: anchors,
            underlineColor: underlineColor,
            onHighlight: onHighlight ?? (_) {},
            onUnderline: onUnderline ?? (_) {},
            onCopy: onCopy,
            onReadAloud: onReadAloud,
            onNote: onNote,
            onExtract: onExtract,
            onCreateFlashcard: onCreateFlashcard,
            moreActions: moreActions,
          ),
        ),
      ),
    );
  }

  testWidgets('cada color resalta con ese color y no con otro', (tester) async {
    final chosen = <HighlightColor>[];
    await pump(tester, onHighlight: chosen.add);

    for (final color in HighlightColor.values) {
      await tester.tap(find.byKey(Key('highlight-color-${color.name}')));
    }

    expect(chosen, HighlightColor.values);
  });

  testWidgets('los colores se llaman por su nombre, para quien no los ve', (
    tester,
  ) async {
    await pump(tester);

    expect(
      find.byTooltip(es.highlightWithColor(es.highlightColorOrange)),
      findsOneWidget,
    );
    expect(
      find.byTooltip(es.highlightWithColor(es.highlightColorViolet)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(es.highlightToolbarLabel), findsOneWidget);
  });

  testWidgets('Subrayar usa el color que se le dio, y dice cuál es', (
    tester,
  ) async {
    final underlined = <HighlightColor>[];
    await pump(
      tester,
      underlineColor: HighlightColor.violet,
      onUnderline: underlined.add,
    );

    expect(
      find.byTooltip(es.highlightUnderlineWithColor(es.highlightColorViolet)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('highlight-underline')));

    expect(underlined, [HighlightColor.violet]);
  });

  testWidgets('cada acción llama a lo suyo, y no a las otras', (tester) async {
    final called = <String>[];
    await pump(
      tester,
      onCopy: () => called.add('copiar'),
      onReadAloud: () => called.add('escuchar'),
      onNote: () => called.add('nota'),
      onExtract: () => called.add('extraer'),
      onCreateFlashcard: () => called.add('tarjeta'),
    );

    await tester.tap(find.byTooltip(es.highlightCopy));
    await tester.tap(find.byTooltip(es.highlightListen));
    await tester.tap(find.byTooltip(es.highlightAddNote));
    await tester.tap(find.byTooltip(es.detailExtractSelection));
    await tester.tap(find.byTooltip(es.flashcardsFromSelection));

    expect(called, ['copiar', 'escuchar', 'nota', 'extraer', 'tarjeta']);
  });

  testWidgets('una acción sin callback no se dibuja: un documento al que no '
      'se le puede extraer una nota no ofrece ese botón', (tester) async {
    await pump(tester, onCopy: () {}, onReadAloud: () {});

    expect(find.byTooltip(es.highlightCopy), findsOneWidget);
    expect(find.byTooltip(es.highlightListen), findsOneWidget);
    expect(find.byTooltip(es.highlightAddNote), findsNothing);
    expect(find.byTooltip(es.detailExtractSelection), findsNothing);
    expect(find.byTooltip(es.flashcardsFromSelection), findsNothing);
    expect(find.byTooltip(es.highlightMore), findsNothing);
  });

  testWidgets('lo que no entra queda detrás de «Más opciones», con su texto', (
    tester,
  ) async {
    var shared = 0;
    await pump(
      tester,
      onCopy: () {},
      moreActions: [
        HighlightToolbarAction(label: 'Compartir', onPressed: () => shared++),
        HighlightToolbarAction(label: 'Buscar en la Web', onPressed: () {}),
      ],
    );

    expect(find.text('Compartir'), findsNothing);
    await tester.tap(find.byTooltip(es.highlightMore));
    await tester.pumpAndSettle();
    expect(find.text('Buscar en la Web'), findsOneWidget);

    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();

    expect(shared, 1);
  });

  testWidgets('cada botón mide lo que un dedo necesita', (tester) async {
    await pump(
      tester,
      onCopy: () {},
      onReadAloud: () {},
      onNote: () {},
      onExtract: () {},
      onCreateFlashcard: () {},
      moreActions: [HighlightToolbarAction(label: 'x', onPressed: () {})],
    );

    final buttons = find.byType(IconButton).evaluate().length;
    expect(buttons, greaterThanOrEqualTo(10));
    for (final button in find.byType(IconButton).evaluate()) {
      final size = tester.getSize(find.byWidget(button.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('entra en un teléfono angosto sin cortarse', (tester) async {
    await pump(
      tester,
      size: const Size(360, 640),
      onCopy: () {},
      onReadAloud: () {},
      onNote: () {},
      onExtract: () {},
      onCreateFlashcard: () {},
      moreActions: [HighlightToolbarAction(label: 'x', onPressed: () {})],
    );
    final bar = tester.getRect(find.byKey(const Key('highlight-toolbar-card')));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('se para encima de la selección si entra', (tester) async {
    await pump(tester, onCopy: () {});

    final bar = tester.getRect(find.byKey(const Key('highlight-toolbar-card')));
    expect(bar.bottom, lessThanOrEqualTo(400));
  });

  testWidgets('si arriba no entra, se para debajo de la selección', (
    tester,
  ) async {
    await pump(
      tester,
      onCopy: () {},
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(200, 30),
        secondaryAnchor: Offset(200, 50),
      ),
    );

    final bar = tester.getRect(find.byKey(const Key('highlight-toolbar-card')));
    expect(bar.top, greaterThanOrEqualTo(50));
  });
}
