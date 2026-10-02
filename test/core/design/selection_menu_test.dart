import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  /// Lo que Flutter habría ofrecido por su cuenta.
  var flutterLabels = <String?>[];

  /// Abre el menú de un texto seleccionable con el menú de la app, y
  /// devuelve lo que ofreció.
  Future<List<ContextMenuButtonItem>> openMenu(
    WidgetTester tester, {
    required bool withOwnActions,
  }) async {
    var captured = <ContextMenuButtonItem>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'Una palabra cualquiera',
              contextMenuBuilder: (context, editable) {
                flutterLabels = [
                  for (final item in editable.contextMenuButtonItems)
                    item.label,
                ];
                captured = withOwnActions
                    ? selectionMenuItems(
                        context,
                        editable,
                        onReadAloud: () {},
                        onHighlight: () {},
                        onExtract: () {},
                        onCreateFlashcard: () {},
                      )
                    : selectionMenuItems(context, editable);
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editable.contextMenuAnchors,
                  buttonItems: captured,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();
    return captured;
  }

  String label(ContextMenuButtonItem item) =>
      item.label ??
      switch (item.type) {
        ContextMenuButtonType.copy => 'Copiar',
        ContextMenuButtonType.share => 'Compartir',
        ContextMenuButtonType.selectAll => 'Seleccionar todo',
        ContextMenuButtonType.searchWeb => 'Buscar en la Web',
        _ => item.type.name,
      };

  setUp(() {
    // Lo que Android le suma al menú por cada app que acepta texto: el menú
    // de la app no lo muestra.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, (call) async {
          if (call.method == 'ProcessText.queryTextActions') {
            return <String, String>{
              'chatgpt': 'Preguntar a ChatGPT',
              'gemini': 'Preguntar a Gemini',
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, null);
  });

  testWidgets('las ocho opciones, en el orden pedido y sin las de otras '
      'apps', (tester) async {
    final items = await openMenu(tester, withOwnActions: true);

    // Flutter sí las habría mostrado.
    expect(flutterLabels, contains('Preguntar a ChatGPT'));
    expect(items.map(label), [
      'Copiar',
      'Compartir',
      'Seleccionar todo',
      es.readAloudTooltip,
      es.detailHighlightSelection,
      es.detailExtractSelection,
      es.flashcardsFromSelection,
      'Buscar en la Web',
    ]);
  });

  testWidgets('un texto sin acciones propias se queda con las comunes, en '
      'el mismo orden', (tester) async {
    final items = await openMenu(tester, withOwnActions: false);

    expect(items.map(label), [
      'Copiar',
      'Compartir',
      'Seleccionar todo',
      'Buscar en la Web',
    ]);
  });
}
