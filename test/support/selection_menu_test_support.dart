import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las opciones del menú de selección abierto, en orden —también las que
/// quedaron detrás de los tres puntos—; vacío si no hay menú.
List<String> selectionMenuLabels(WidgetTester tester) {
  final toolbar = find.byType(AdaptiveTextSelectionToolbar);
  if (toolbar.evaluate().isEmpty) return const [];
  final context = tester.element(toolbar.first);
  return [
    for (final item
        in tester
            .widget<AdaptiveTextSelectionToolbar>(toolbar.first)
            .buttonItems!)
      AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
  ];
}

/// Toca la opción [label] del menú de selección abierto. En un teléfono las
/// que no entran a lo ancho quedan detrás de los tres puntos: si no se ve,
/// abre ese desplegable primero, como haría el usuario.
Future<void> tapSelectionMenuItem(WidgetTester tester, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    final context = tester.element(
      find.byType(AdaptiveTextSelectionToolbar).first,
    );
    await tester.tap(
      find.byTooltip(MaterialLocalizations.of(context).moreButtonTooltip),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
