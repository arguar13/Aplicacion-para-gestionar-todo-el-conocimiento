import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Monta [child] como lo vería alguien en un teléfono angosto (360 dp) con la
/// letra al doble, en el tema [brightness] de la app y en castellano.
Future<void> pumpHelpScreen(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: app!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Los tramos de todos los textos con formato a la vista, para mirar qué se
/// pintó encima de qué.
Iterable<TextSpan> paintedSpans(WidgetTester tester) sync* {
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    final spans = <TextSpan>[];
    text.text.visitChildren((span) {
      if (span is TextSpan) spans.add(span);
      return true;
    });
    yield* spans;
  }
}
