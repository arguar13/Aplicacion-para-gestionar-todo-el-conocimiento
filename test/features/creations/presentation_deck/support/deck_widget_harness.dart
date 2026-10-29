import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Monta [child] como una pantalla de la app, en castellano, con el ancho,
/// el tamaño de letra, el tema y el «sin animaciones» que se pidan.
Future<void> pumpDeckScreen(
  WidgetTester tester,
  Widget child, {
  double width = 412,
  double height = 900,
  double textScale = 1,
  bool dark = false,
  bool disableAnimations = false,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(body: SafeArea(child: child)),
        ),
      ),
    ),
  );
}
