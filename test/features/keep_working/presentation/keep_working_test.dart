import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/keep_working/domain/services/background_settings.dart';
import 'package:sinapsis/features/keep_working/presentation/providers/keep_working_providers.dart';
import 'package:sinapsis/features/keep_working/presentation/screens/keep_working_screen.dart';
import 'package:sinapsis/features/keep_working/presentation/widgets/keep_working_offer_listener.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../support/fake_background_settings.dart';

/// La ayuda "Que siga con la app cerrada" (F29): se ofrece una sola vez, la
/// primera vez que hay trabajo largo con la app a la vista, y lleva a los
/// ajustes justos de cada teléfono.
void main() {
  late SharedPreferences prefs;
  late FakeBackgroundSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = FakeBackgroundSettings();
  });

  Widget localized(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) =>
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  group('la oferta', () {
    late LongWorkCoordinator coordinator;
    late LongWorkKeeper processing;
    late int opened;

    setUp(() {
      coordinator = LongWorkCoordinator(
        platform: const NoLongWorkPlatform(),
        releaseDelay: Duration.zero,
      );
      processing = coordinator.keeperFor(LongWorkOwner.processing);
      opened = 0;
    });

    tearDown(() => coordinator.dispose());

    Future<void> pump(
      WidgetTester tester, {
      BackgroundSettings? background,
      bool android = true,
    }) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          // Uno nuevo cada vez: la app vuelta a abrir arranca de cero.
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            longWorkCoordinatorProvider.overrideWithValue(coordinator),
            backgroundSettingsProvider.overrideWithValue(
              android ? background ?? settings : null,
            ),
          ],
          child: localized(
            KeepWorkingOfferListener(
              navigatorKey: navigatorKey,
              onOpenHelp: () => opened++,
              child: const Scaffold(body: Text('biblioteca')),
            ),
            navigatorKey: navigatorKey,
          ),
        ),
      );
    }

    /// Empieza un trabajo largo, después de que el anterior terminó.
    Future<void> startWork(WidgetTester tester) async {
      processing
        ..idle()
        ..working(done: 0, total: 10);
      await tester.pumpAndSettle();
    }

    testWidgets('aparece la primera vez que hay trabajo largo, y «Ver cómo» '
        'lleva a la ayuda', (tester) async {
      await pump(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsNothing);

      await startWork(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsOneWidget);

      await tester.tap(find.text('Ver cómo'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(prefs.getBool('keep_working_help_offered'), isTrue);
    });

    testWidgets('una sola vez: «Ahora no» y no vuelve, tampoco al abrir la '
        'app de nuevo', (tester) async {
      await pump(tester);
      await startWork(tester);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      await startWork(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsNothing);

      // La app vuelta a abrir, con la marca ya guardada.
      await pump(tester);
      await startWork(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsNothing);
      expect(opened, 0);
    });

    testWidgets('con la app en segundo plano no pregunta: espera a un trabajo '
        'con la app a la vista', (tester) async {
      await pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await startWork(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsNothing);
      expect(prefs.getBool('keep_working_help_offered'), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await startWork(tester);
      expect(find.text('¿Que siga aunque cierres la app?'), findsOneWidget);
    });

    testWidgets('fuera de Android no se ofrece', (tester) async {
      await pump(tester, android: false);
      await startWork(tester);

      expect(find.text('¿Que siga aunque cierres la app?'), findsNothing);
    });
  });

  group('la pantalla', () {
    /// Toca el botón [label], desplazando hasta él si hace falta.
    Future<void> tapVisible(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }

    Future<void> pump(WidgetTester tester) {
      // Alto de teléfono: los dos pasos y sus botones, a la vista.
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        ProviderScope(
          overrides: [backgroundSettingsProvider.overrideWithValue(settings)],
          child: localized(const KeepWorkingScreen()),
        ),
      );
    }

    testWidgets('en un Xiaomi, los dos pasos: «Inicio automático» y la '
        'batería', (tester) async {
      settings.isXiaomi = true;
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('keep-working-autostart')), findsOneWidget);
      expect(find.byKey(const Key('keep-working-battery')), findsOneWidget);

      await tapVisible(tester, 'Abrir Inicio automático');
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Abrir ajustes de batería');
      await tester.pumpAndSettle();
      expect(settings.opened, ['inicio automático', 'batería']);
      // Se abrieron las pantallas justas: no hay nada más que decir.
      expect(find.textContaining('buscá'), findsNothing);
    });

    testWidgets('en otra marca, solo la batería: «Inicio automático» es de '
        'Xiaomi', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('keep-working-autostart')), findsNothing);
      expect(find.byKey(const Key('keep-working-battery')), findsOneWidget);
    });

    testWidgets('si se abrió la ficha de la app en vez del ahorro de batería, '
        'dice qué tocar ahí', (tester) async {
      settings.batteryOpens = BackgroundSettingsScreen.appDetails;
      await pump(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, 'Abrir ajustes de batería');
      await tester.pumpAndSettle();

      expect(
        find.text('Entrá en «Batería» y elegí «Sin restricciones».'),
        findsOneWidget,
      );
    });

    testWidgets('si no se pudo abrir nada, dónde buscarlo a mano', (
      tester,
    ) async {
      settings
        ..isXiaomi = true
        ..autostartOpens = null;
      await pump(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, 'Abrir Inicio automático');
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudieron abrir los ajustes. Buscá Sinapsis en Ajustes › Apps.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('al volver de los ajustes, la batería ya hecha se ve '
        'hecha', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Listo: el sistema no le aplica ahorro de batería.'),
        findsNothing,
      );

      settings.batteryUnrestricted = true;
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.text('Listo: el sistema no le aplica ahorro de batería.'),
        findsOneWidget,
      );
    });
  });
}
