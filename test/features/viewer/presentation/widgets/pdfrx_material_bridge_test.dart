import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El menú "Copiar / Seleccionar todo" del visor de PDF, construido como lo
/// construye `pdfrx` —con `material_ui`, no con `flutter/material`— dentro de
/// una app armada como la de verdad. No hace falta PDFium: lo que se rompía
/// era el menú, no el PDF (F22).
void main() {
  // Android: ahí el menú pide las traducciones de Material.
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  Widget menu() => Builder(
    builder: (context) => mui.AdaptiveTextSelectionToolbar.buttonItems(
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(100, 200),
      ),
      buttonItems: [
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {},
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () {},
        ),
      ],
    ),
  );

  Future<void> pumpApp(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('sin el puente, el menú de pdfrx no encuentra sus traducciones '
      '(la causa del visor gris)', (tester) async {
    await pumpApp(tester, menu());

    expect(tester.takeException(), isNotNull);
  }, variant: android);

  testWidgets('con el puente, el menú se arma en español: "Copiar" y '
      '"Seleccionar todo"', (tester) async {
    await pumpApp(tester, PdfrxMaterialBridge(child: menu()));

    expect(tester.takeException(), isNull);
    expect(find.text('Copiar'), findsOneWidget);
    expect(find.text('Seleccionar todo'), findsOneWidget);
  }, variant: android);

  testWidgets('el puente copia los colores de la app, modo oscuro incluido', (
    tester,
  ) async {
    late mui.ThemeData seen;
    await pumpApp(
      tester,
      PdfrxMaterialBridge(
        child: Builder(
          builder: (context) {
            seen = mui.Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
      theme: AppTheme.darkTheme,
    );

    final app = AppTheme.darkTheme.colorScheme;
    expect(seen.colorScheme.brightness, Brightness.dark);
    expect(seen.colorScheme.surface, app.surface);
    expect(seen.colorScheme.onSurface, app.onSurface);
    expect(seen.colorScheme.primary, app.primary);
  }, variant: android);

  group('los tiradores de la selección (F22)', () {
    test('la punta de la gota toca la letra: el del principio, arriba a la '
        'izquierda de la primera; el del final, abajo a la derecha de la '
        'última', () {
      expect(
        pdfSelectionHandleTip(start: true, rightToLeft: false),
        Alignment.bottomRight,
      );
      expect(
        pdfSelectionHandleTip(start: false, rightToLeft: false),
        Alignment.topLeft,
      );
    });

    test('en un texto de derecha a izquierda, del lado opuesto', () {
      expect(
        pdfSelectionHandleTip(start: true, rightToLeft: true),
        Alignment.bottomLeft,
      );
      expect(
        pdfSelectionHandleTip(start: false, rightToLeft: true),
        Alignment.topRight,
      );
    });
  });
}
