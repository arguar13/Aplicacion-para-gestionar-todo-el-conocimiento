import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/audio/lock_screen_title.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_media_session.dart';
import '../../../../support/library_harness.dart';

/// Ajustes › Privacidad (F47, paso 7a-bis): «Mostrar el título en la
/// pantalla de bloqueo», de entrada apagado, solo donde hay tarjeta de lo que
/// suena, a 360 dp con la letra al doble, en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeMediaSession session;

  final toggle = find.byKey(const Key('settings-lock-screen-title'));
  final explanation = find.byKey(
    const Key('settings-lock-screen-title-explanation'),
  );

  Future<void> setUpWith({bool supported = true}) async {
    session = FakeMediaSession(isSupported: supported);
    harness = await LibraryHarness.create(
      extraOverrides: [mediaSessionPlatformProvider.overrideWithValue(session)],
    );
  }

  /// Ajustes a 360 dp con la letra al doble, en el tema [brightness].
  Future<void> pumpSettings(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
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
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder settingsList() => find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Que [finder], llevado a la vista, se vea entero en la lista —debajo de
  /// la barra de arriba—, sin cortarse.
  Future<void> expectWhole(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      500,
      scrollable: settingsList(),
      maxScrolls: 200,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final list = tester.getRect(settingsList());
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
    final control = find.descendant(of: toggle, matching: find.byType(Switch));
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('en ${brightness.name}: Privacidad, con el interruptor '
        'apagado y lo que pasa, entra sin desbordar', (tester) async {
      await setUpWith();
      await pumpSettings(tester, brightness: brightness);

      for (final part in [
        find.text(es.f47P7bisPrivacySection),
        toggle,
        find.text(es.f47P7bisLockScreenTitle),
        explanation,
      ]) {
        await expectWhole(tester, part);
      }
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.widget<Text>(explanation).data, es.f47P7bisLockScreenOff);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prenderlo lo deja ver, lo dice y queda guardado; apagarlo lo '
      'oculta otra vez', (tester) async {
    await setUpWith();
    await pumpSettings(tester);
    await expectWhole(tester, toggle);

    await flip(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(tester.widget<Text>(explanation).data, es.f47P7bisLockScreenOn);
    await expectWhole(tester, explanation);
    expect(harness.container.read(lockScreenTitleProvider), isTrue);
    expect(
      harness.container
          .read(sharedPreferencesProvider)
          .getBool('media_session.show_title_on_lock_screen'),
      isTrue,
    );

    await flip(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(tester.widget<Text>(explanation).data, es.f47P7bisLockScreenOff);
    expect(harness.container.read(lockScreenTitleProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  /// Ajustes entero en una ventana alta: una lista perezosa no arma lo que
  /// está lejos.
  Future<void> pumpWholeSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('va justo antes de la Bóveda', (tester) async {
    await setUpWith();
    await pumpWholeSettings(tester);

    final privacy = tester.getTopLeft(find.text(es.f47P7bisPrivacySection));
    final vault = tester.getTopLeft(find.text(es.settingsVaultSection));
    expect(privacy.dy, lessThan(vault.dy));
    expect(tester.getTopLeft(toggle).dy, lessThan(vault.dy));
  });

  testWidgets('donde no hay tarjeta de lo que suena, no está', (tester) async {
    await setUpWith(supported: false);
    await pumpWholeSettings(tester);

    expect(find.text(es.settingsVaultSection), findsOneWidget);
    expect(find.text(es.f47P7bisPrivacySection), findsNothing);
    expect(toggle, findsNothing);
  });

  testWidgets('para el lector de pantalla es un interruptor con su nombre y '
      'su estado', (tester) async {
    final semantics = tester.ensureSemantics();
    await setUpWith();
    await pumpSettings(tester);
    await expectWhole(tester, toggle);

    expect(
      tester.getSemantics(toggle),
      isSemantics(
        label: es.f47P7bisLockScreenTitle,
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
}
