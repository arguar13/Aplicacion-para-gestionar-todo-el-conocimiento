import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/links/presentation/screens/broken_links_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/trash/presentation/screens/trash_screen.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/merge_conflicts_screen.dart';
import 'package:sinapsis/features/vault/presentation/screens/vault_compaction_screen.dart';
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

    testWidgets('muestra la papelera (F11)', (tester) async {
      await pumpSettings(tester);

      expect(find.text(es.trashTitle), findsOneWidget);
    });

    testWidgets('tocar la papelera abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.trashTitle));
      await tester.pumpAndSettle();

      expect(find.byType(TrashScreen), findsOneWidget);
      // La bóveda de la prueba no borró nada.
      expect(find.text(es.trashEmptyTitle), findsOneWidget);
    });

    testWidgets('muestra los cambios para revisar, con cuántos hay (F11)', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(es.conflictsTitle), findsOneWidget);
      // La bóveda de la prueba no fusionó nada.
      expect(find.text(es.conflictsSettingsSubtitle(0)), findsOneWidget);
    });

    testWidgets('tocarlos abre su pantalla, con el router real', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo(RoutePaths.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.conflictsTitle));
      await tester.pumpAndSettle();

      expect(find.byType(MergeConflictsScreen), findsOneWidget);
      expect(find.text(es.conflictsEmptyTitle), findsOneWidget);
    });

    group('el espacio de la bóveda (F12)', () {
      /// Lo que un borrado deja: páginas libres dentro de la base.
      Future<void> leaveFreePages() async {
        final db = harness.database;
        await db.customStatement(
          'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
        );
        await db.customStatement('''
          WITH RECURSIVE n(x) AS (
            SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 400
          )
          INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
        await db.customStatement('DELETE FROM relleno');
      }

      testWidgets('con la bóveda al día, dice que no hay nada que recuperar', (
        tester,
      ) async {
        await pumpSettings(tester);

        expect(find.text(es.vaultCompactionSettingsTooltip), findsOneWidget);
        expect(find.text(es.vaultCompactionSettingsNothing), findsOneWidget);
      });

      testWidgets('con páginas libres, dice cuánto se puede recuperar', (
        tester,
      ) async {
        await leaveFreePages();

        await pumpSettings(tester);

        expect(find.text(es.vaultCompactionSettingsNothing), findsNothing);
        expect(find.textContaining('Se pueden recuperar'), findsOneWidget);
      });

      testWidgets('tocarla abre su pantalla, con el router real', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo(RoutePaths.settings);
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.vaultCompactionSettingsTooltip));
        await tester.pumpAndSettle();

        expect(find.byType(VaultCompactionScreen), findsOneWidget);
        expect(find.text(es.vaultCompactionNothingLine), findsOneWidget);
      });
    });
  });
}
