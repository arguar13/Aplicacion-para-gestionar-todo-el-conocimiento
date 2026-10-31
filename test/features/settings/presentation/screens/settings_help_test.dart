import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/help/presentation/screens/about_screen.dart';
import 'package:sinapsis/features/help/presentation/screens/user_guide_screen.dart';
import 'package:sinapsis/features/help/presentation/screens/whats_new_screen.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_settings_tiles.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/home_widgets/presentation/screens/home_widgets_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_home_screen_widgets.dart';
import '../../../../support/library_harness.dart';

/// Ajustes › Ayuda y Widgets (F47, paso 7): al final de Ajustes, cada fila
/// lleva a su pantalla, y los widgets solo donde los hay.
void main() {
  final es = AppLocalizationsEs();
  final guide = HelpDocument.parse(File(kUserGuideAsset).readAsStringSync());
  final whatsNew = HelpDocument.parse(File(kWhatsNewAsset).readAsStringSync());
  late LibraryHarness harness;

  Future<void> setUpWith({bool widgets = true}) async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        homeScreenWidgetsProvider.overrideWithValue(
          FakeHomeScreenWidgets(supported: widgets),
        ),
        userGuideProvider.overrideWith((ref) async => guide),
        whatsNewProvider.overrideWith((ref) async => whatsNew),
        appVersionProvider.overrideWith(
          (ref) async =>
              const AppVersion(name: 'Sinapsis', version: '0.1.0', build: '1'),
        ),
      ],
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      500,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 200,
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('en ${brightness.name}, a 360 dp con la letra al doble: los '
        'widgets y la Ayuda entran sin desbordar', (tester) async {
      await setUpWith();
      await pumpSettings(tester, brightness: brightness);

      for (final finder in [
        find.text(es.f47P7WidgetsSection),
        find.byKey(const Key('settings-home-widgets')),
        find.text(es.f47P7HelpSection),
        for (final page in HelpPage.values)
          find.byKey(Key('settings-help-${page.name}')),
      ]) {
        await scrollTo(tester, finder);
        expect(finder, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('la Ayuda va al final —solo bloquear la bóveda la sigue—, con '
      'la guía, las novedades y «Acerca de»; los widgets, antes', (
    tester,
  ) async {
    await setUpWith();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    // La ventana del alto de Ajustes entero: una lista perezosa no arma lo
    // que está lejos, y acá se comparan lugares de punta a punta.
    final overflow = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .maxScrollExtent;
    tester.view.physicalSize = Size(800, 1600 + overflow);
    await tester.pumpAndSettle();

    double top(Finder finder) => tester.getTopLeft(finder).dy;
    final sections = [
      es.settingsVaultSection,
      es.settingsDevelopmentSection,
      es.f47P7WidgetsSection,
      es.f47P7HelpSection,
    ].map((title) => top(find.text(title))).toList();
    expect(sections, [...sections]..sort());

    final tiles = [
      for (final page in HelpPage.values)
        top(find.byKey(Key('settings-help-${page.name}'))),
    ];
    expect(tiles, [...tiles]..sort());
    expect(tiles.first, greaterThan(sections.last));
    expect(top(find.text(es.lockVaultTooltip)), greaterThan(tiles.last));
  });

  testWidgets('sin widgets en la plataforma, no hay sección de widgets', (
    tester,
  ) async {
    await setUpWith(widgets: false);
    await pumpSettings(tester);

    await scrollTo(tester, find.text(es.lockVaultTooltip));
    expect(find.text(es.f47P7WidgetsSection), findsNothing);
    expect(find.byKey(const Key('settings-home-widgets')), findsNothing);
    expect(find.text(es.f47P7HelpSection), findsOneWidget);
  });

  group('cada fila lleva a su pantalla', () {
    Future<void> openFromSettings(WidgetTester tester, Key tile) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(tile));
      await tester.tap(find.byKey(tile));
      await tester.pumpAndSettle();
    }

    final cases = <String, (Key, Type)>{
      'la guía de uso': (const Key('settings-help-guide'), UserGuideScreen),
      'las novedades': (const Key('settings-help-whatsNew'), WhatsNewScreen),
      '«Acerca de»': (const Key('settings-help-about'), AboutScreen),
      'los widgets': (const Key('settings-home-widgets'), HomeWidgetsScreen),
    };
    for (final MapEntry(key: name, value: (tile, screen)) in cases.entries) {
      testWidgets(name, (tester) async {
        await setUpWith();
        await openFromSettings(tester, tile);

        expect(find.byType(screen), findsOneWidget);
      });
    }
  });
}
