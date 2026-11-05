import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
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
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) => pumpHelpScreen(
    tester,
    const HomeWidgetsScreen(),
    brightness: brightness,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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

  group('«Mostrar el título con la bóveda cerrada» (paso 7a-bis)', () {
    final toggle = find.byKey(const Key('home-widgets-show-while-locked'));
    final explanation = find.byKey(
      const Key('home-widgets-show-while-locked-explanation'),
    );

    /// Al pie de la pantalla, donde está el interruptor.
    Future<void> scrollToEnd(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
    }

    /// Que [finder], llevado a la vista, se vea entero en la lista —debajo
    /// de la barra de arriba—, sin cortarse: con la letra al doble, nada es
    /// más alto ni más ancho que lo que se ve.
    ///
    /// Cada parte por separado: la letra de las pruebas dibuja cada letra
    /// como un cuadrado entero, el doble de ancha que la del teléfono, y el
    /// interruptor y su explicación juntos no entrarían acá aunque en el
    /// teléfono sí.
    Future<void> expectWhole(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final list = tester.getRect(find.byType(ListView));
      final rect = tester.getRect(finder);
      expect(list.contains(rect.topLeft), isTrue, reason: '$rect en $list');
      expect(
        list.contains(rect.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: '$rect en $list',
      );
    }

    /// Toca el interruptor, a la vista.
    Future<void> flip(WidgetTester tester) async {
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
    }

    for (final brightness in Brightness.values) {
      testWidgets('en ${brightness.name}: de entrada apagado, y dice que '
          'oculta el título; a 360 dp con la letra al doble se ve '
          'entero', (tester) async {
        widgets = FakeHomeScreenWidgets();
        await pumpScreen(tester, brightness: brightness);
        await scrollToEnd(tester);

        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(find.text(es.f47P7WidgetsShowLockedTitle), findsOneWidget);
        expect(
          tester.widget<Text>(explanation).data,
          es.f47P7WidgetsShowLockedOff,
        );
        for (final part in [
          toggle,
          find.text(es.f47P7WidgetsShowLockedTitle),
          find.byType(Switch),
          explanation,
        ]) {
          await expectWhole(tester, part);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('prenderlo deja el título a la vista, lo dice y queda '
        'guardado; apagarlo lo vuelve a ocultar', (tester) async {
      widgets = FakeHomeScreenWidgets();
      await pumpScreen(tester);
      await scrollToEnd(tester);

      await flip(tester);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        tester.widget<Text>(explanation).data,
        es.f47P7WidgetsShowLockedOn,
      );
      await expectWhole(tester, toggle);
      await expectWhole(tester, explanation);
      expect(prefs.getBool('continue_listening.show_while_locked'), isTrue);
      expect(tester.takeException(), isNull);

      await flip(tester);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        tester.widget<Text>(explanation).data,
        es.f47P7WidgetsShowLockedOff,
      );
      expect(prefs.getBool('continue_listening.show_while_locked'), isFalse);
    });

    testWidgets('para el lector de pantalla es un interruptor con su nombre y '
        'su estado', (tester) async {
      final semantics = tester.ensureSemantics();
      widgets = FakeHomeScreenWidgets();
      await pumpScreen(tester);
      await scrollToEnd(tester);

      expect(
        tester.getSemantics(toggle),
        isSemantics(
          label: es.f47P7WidgetsShowLockedTitle,
          hasToggledState: true,
          isToggled: false,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await flip(tester);
      expect(
        tester.getSemantics(toggle),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      semantics.dispose();
    });
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
