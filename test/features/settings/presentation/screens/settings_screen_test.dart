import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/links/presentation/screens/broken_links_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // Con la fila nueva de "Posibles duplicados" (F7), la lista entera
    // ya no entra en el tamaño de ventana por defecto de las pruebas de
    // widget (800x600) — agrandar la ventana es más simple y menos
    // frágil que un `scrollUntilVisible` en cada prueba que toca algo
    // del final de la lista.
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra las tres secciones', (tester) async {
    await pumpSettings(tester);

    expect(find.text(es.settingsAppearanceSection), findsOneWidget);
    expect(find.text(es.settingsAiSection), findsOneWidget);
    expect(find.text(es.settingsVaultSection), findsOneWidget);
  });

  group('idioma', () {
    testWidgets('muestra el idioma efectivo actual', (tester) async {
      await pumpSettings(tester);

      expect(find.text('ES'), findsOneWidget);
    });

    testWidgets('tocarlo lo cambia al siguiente de la lista', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.languageTooltip));
      await tester.pumpAndSettle();

      expect(find.text('EN'), findsOneWidget);
    });
  });

  group('tema', () {
    testWidgets('arranca en "sistema"', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.themeModeSystem), findsOneWidget);
    });

    testWidgets('tocarlo lo cambia al siguiente de la lista', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.themeModeTooltip));
      await tester.pumpAndSettle();

      expect(find.text(es.themeModeLight), findsOneWidget);
      expect(
        harness.container.read(themeModeNotifierProvider),
        ThemeMode.light,
      );
    });
  });

  group('bóveda', () {
    testWidgets('bloquear la bóveda actualiza la sesión', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(es.lockVaultTooltip));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(vaultSessionControllerProvider),
        isA<VaultLocked>(),
      );
    });

    testWidgets('muestra la opción de posibles duplicados (F7)', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(es.duplicatesSettingsTooltip), findsOneWidget);
    });

    testWidgets('muestra la opción del vocabulario (F8)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.vocabularySettingsTooltip), findsOneWidget);
    });

    testWidgets('tocar el vocabulario abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.vocabularySettingsTooltip));
      // Sin `pumpAndSettle`: la pantalla real calcula los candidatos en un
      // isolate (`compute`), que no corre bajo el reloj simulado, y su
      // indicador de carga anima para siempre. Para probar la navegación
      // alcanzan unos cuadros.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(VocabularyScreen), findsOneWidget);
      expect(find.text(es.vocabularyTitle), findsOneWidget);
    });

    testWidgets('muestra la opción de enlaces rotos (F9)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.brokenLinksTitle), findsOneWidget);
    });

    testWidgets('tocar los enlaces rotos abre su pantalla, con el router '
        'real', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.brokenLinksTitle));
      await tester.pumpAndSettle();

      expect(find.byType(BrokenLinksScreen), findsOneWidget);
      // La bóveda de la prueba no tiene ningún enlace roto.
      expect(find.text(es.brokenLinksEmpty), findsOneWidget);
    });
  });
}
