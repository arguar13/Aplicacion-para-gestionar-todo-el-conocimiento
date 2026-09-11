import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_bottom_nav_bar.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_nav_drawer.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';

import '../../../../support/vault_test_doubles.dart';

void main() {
  late SharedPreferences prefs;

  // Locale fija (no la del sistema donde corra el test) para que las
  // aserciones de texto sean deterministas.
  final l10n = AppLocalizationsEn();

  setUp(() async {
    // `SharedPreferences` real usa canales de plataforma;
    // `setMockInitialValues` es el mock oficial del propio paquete.
    // `ThemeModeNotifier` lo necesita por el botón de tema y
    // `LocaleNotifier` por el de idioma — se fija 'en' para que el texto no
    // dependa del idioma del sistema que corre el test.
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(
          FakeVaultLocalDataSource.withPin('246810'),
        ),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultSessionControllerProvider.notifier).markUnlocked();
    return container;
  }

  /// Igual que en `app/app.dart`: el `locale` del MaterialApp sale de
  /// Riverpod, para que quede sincronizado con lo que lee el botón de
  /// idioma de la propia pantalla.
  Widget buildTestableWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(effectiveLocaleProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardScreen(),
        ),
      ),
    );
  }

  Future<void> setViewportWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('estado vacío', () {
    testWidgets('explica qué hace la app en vez de mostrar un vacío mudo', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget(buildContainer()));
      await tester.pumpAndSettle();

      expect(find.text(l10n.emptyLibraryTitle), findsOneWidget);
      expect(find.text(l10n.emptyLibraryMessage), findsOneWidget);
    });

    testWidgets('no hay indicador de carga: la pantalla ya no espera a '
        'ninguna petición de red', (tester) async {
      await tester.pumpWidget(buildTestableWidget(buildContainer()));
      // Un solo frame, sin dejar que nada "termine": si algo quedara
      // cargando, se vería acá.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('layout responsivo', () {
    testWidgets('en pantalla angosta usa la barra inferior', (tester) async {
      await setViewportWidth(tester, 400);

      await tester.pumpWidget(buildTestableWidget(buildContainer()));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardBottomNavBar), findsOneWidget);
    });

    testWidgets('en pantalla ancha usa el cajón lateral', (tester) async {
      await setViewportWidth(tester, 1200);

      await tester.pumpWidget(buildTestableWidget(buildContainer()));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardBottomNavBar), findsNothing);
      // El Drawer se construye al abrirse, así que se comprueba por el
      // Scaffold que lo tiene configurado.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isA<DashboardNavDrawer>());
    });
  });

  group('bloquear la bóveda', () {
    testWidgets('el botón la cierra sin navegar a mano: deja el estado en '
        '`locked` y el router se encarga del resto', (tester) async {
      // Arrange
      final container = buildContainer();
      await tester.pumpWidget(buildTestableWidget(container));
      await tester.pumpAndSettle();

      expect(
        container.read(vaultSessionControllerProvider),
        const VaultSession.unlocked(),
      );

      // Act
      await tester.tap(find.byTooltip(l10n.lockVaultTooltip));
      await tester.pumpAndSettle();

      // Assert
      expect(
        container.read(vaultSessionControllerProvider),
        const VaultSession.locked(),
      );
    });

    testWidgets('cerrar la bóveda NO borra el credencial: la misma clave '
        'vuelve a abrirla', (tester) async {
      // Arrange
      final vault = FakeVaultLocalDataSource.withPin('246810');
      final container = ProviderContainer(
        overrides: [
          vaultLocalDataSourceProvider.overrideWithValue(vault),
          pinHasherProvider.overrideWithValue(FakePinHasher()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      container.read(vaultSessionControllerProvider.notifier).markUnlocked();

      await tester.pumpWidget(buildTestableWidget(container));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byTooltip(l10n.lockVaultTooltip));
      await tester.pumpAndSettle();

      // Assert: bloquear es cerrar una puerta, no destruir la casa. El
      // equivalente anterior —cerrar sesión— sí borraba el token, y
      // confundir ambas cosas acá dejaría al usuario sin sus datos.
      expect(vault.credential, isNotNull);
    });
  });
}
