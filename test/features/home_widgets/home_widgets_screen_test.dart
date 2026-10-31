import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/home_widgets/presentation/screens/home_widgets_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../support/fake_home_screen_widgets.dart';
import '../help/help_test_app.dart';

/// La pantalla de los widgets (F47, paso 7), con la plataforma reemplazada
/// por un doble, a 360 dp con la letra al doble, en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  late FakeHomeScreenWidgets widgets;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) => pumpHelpScreen(
    tester,
    const HomeWidgetsScreen(),
    brightness: brightness,
    overrides: [
      homeScreenWidgetsProvider.overrideWithValue(widgets),
      appVersionProvider.overrideWith(
        (ref) async =>
            const AppVersion(name: 'Sinapsis', version: '0.1.0', build: '1'),
      ),
    ],
  );

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('en ${brightness.name}: los tres, con qué muestra cada uno y '
        '«Agregar»', (tester) async {
      widgets = FakeHomeScreenWidgets();
      await pumpScreen(tester, brightness: brightness);

      for (final (name, description) in [
        (es.f47P7WidgetDueToday, es.f47P7WidgetDueTodayDescription),
        (es.f47P7WidgetQuickCapture, es.f47P7WidgetQuickCaptureDescription),
        (
          es.f47P7WidgetContinueListening,
          es.f47P7WidgetContinueListeningDescription,
        ),
      ]) {
        await show(tester, find.text(description));
        expect(find.text(name), findsOneWidget);
      }
      for (final kind in HomeWidgetKind.values) {
        await show(tester, find.byKey(Key('home-widget-add-${kind.name}')));
      }
      expect(find.byKey(const Key('home-widgets-manual-hint')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('«Agregar» le pide al teléfono ese widget', (tester) async {
    widgets = FakeHomeScreenWidgets();
    await pumpScreen(tester);

    for (final kind in HomeWidgetKind.values.reversed) {
      final add = find.byKey(Key('home-widget-add-${kind.name}'));
      await show(tester, add);
      await tester.tap(add);
      await tester.pump();
    }

    expect(widgets.added, HomeWidgetKind.values.reversed.toList());
  });

  testWidgets('si el teléfono no deja agregarlos, dice cómo hacerlo a mano', (
    tester,
  ) async {
    widgets = FakeHomeScreenWidgets(canAdd: false);
    await pumpScreen(tester);

    expect(find.byKey(const Key('home-widget-add-dueToday')), findsNothing);
    final hint = find.text(es.f47P7WidgetsManualHint('Sinapsis'));
    await show(tester, hint);
    expect(hint, findsOneWidget);
  });

  testWidgets('dice que «Seguir escuchando» deja el título a la vista', (
    tester,
  ) async {
    widgets = FakeHomeScreenWidgets();
    await pumpScreen(tester);

    final privacy = find.text(es.f47P7WidgetsPrivacy);
    await show(tester, privacy);
    expect(privacy, findsOneWidget);
  });

  testWidgets('para el lector de pantalla, «Agregar» dice qué agrega', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    widgets = FakeHomeScreenWidgets();
    await pumpScreen(tester);

    final add = find.byKey(const Key('home-widget-add-quickCapture'));
    await show(tester, add);
    expect(
      tester.getSemantics(add),
      isSemantics(
        label: es.f47P7WidgetAddSemantics(es.f47P7WidgetQuickCapture),
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
