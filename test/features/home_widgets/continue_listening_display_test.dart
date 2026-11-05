import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

import '../../support/vault_test_doubles.dart';

/// «Seguir escuchando» y la bóveda cerrada (F47, paso 7a-bis): qué se le
/// manda al widget según lo escuchado, el interruptor de Ajustes › Widgets y
/// la bóveda, y la regla con que el widget decide solo —también después de
/// reiniciar el teléfono, con la app muerta—.
void main() {
  const boot = 'arranque-7';

  group('la regla del widget', () {
    const title = ContinueListeningDisplay(title: 'El Imperio', openBoot: boot);

    test('sin nada escuchado no hay título que mostrar ni que ocultar', () {
      for (final display in const [
        ContinueListeningDisplay(),
        ContinueListeningDisplay(title: '  ', openBoot: boot),
        ContinueListeningDisplay(showWhileLocked: true),
      ]) {
        expect(display.shownIn(boot), ContinueListeningShown.nothing);
      }
    });

    test('con la bóveda abierta en este encendido, el título', () {
      expect(title.shownIn(boot), ContinueListeningShown.title);
    });

    test('reiniciado el teléfono, la bóveda quedó cerrada: el genérico, '
        'aunque la app no se haya enterado', () {
      expect(title.shownIn('arranque-8'), ContinueListeningShown.protected);
    });

    test('sin saber el encendido —el de ahora o el de la bóveda—, oculta', () {
      expect(title.shownIn(null), ContinueListeningShown.protected);
      expect(
        const ContinueListeningDisplay(title: 'El Imperio').shownIn(boot),
        ContinueListeningShown.protected,
      );
    });

    test('a la vista por elección, el título siempre', () {
      const shown = ContinueListeningDisplay(
        title: 'El Imperio',
        showWhileLocked: true,
      );
      for (final current in [boot, 'arranque-8', null]) {
        expect(shown.shownIn(current), ContinueListeningShown.title);
      }
    });
  });

  group('lo que se le manda', () {
    late SharedPreferences prefs;
    late FakeVaultLocalDataSource vault;

    /// La app recién abierta en el encendido [now]; la bóveda se abrió por
    /// última vez en [openBoot] (`null`, cerrada).
    Future<ProviderContainer> open({
      String? now = boot,
      String? openBoot,
      Map<String, Object> stored = const {},
      bool bootFails = false,
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      prefs = await SharedPreferences.getInstance();
      vault = FakeVaultLocalDataSource.withPin('246810', openBoot: openBoot);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          vaultLocalDataSourceProvider.overrideWithValue(vault),
          pinHasherProvider.overrideWithValue(FakePinHasher()),
          deviceBootProvider.overrideWithValue(
            () async => bootFails ? throw StateError('sin canal') : now,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> resolve(ProviderContainer container) async {
      await container
          .read(vaultSessionControllerProvider.notifier)
          .resolveInitialState();
      await container
          .read(deviceBootNowProvider.future)
          .catchError((_) => null);
    }

    Future<void> listen(ProviderContainer container, String title) => container
        .read(continueListeningProvider.notifier)
        .listened(title: title, location: '/processed/p1');

    ContinueListeningShown shown(ProviderContainer container) =>
        container.read(continueListeningDisplayProvider)!.shownIn(boot);

    test('de entrada, el interruptor está apagado: oculta', () async {
      final container = await open();
      expect(container.read(continueListeningShowWhileLockedProvider), isFalse);
    });

    test('mientras no se sabe si la bóveda quedó abierta, no se manda '
        'nada: el widget sigue con lo suyo', () async {
      final container = await open(openBoot: boot);
      expect(container.read(continueListeningDisplayProvider), isNull);
    });

    test('con la bóveda cerrada, el genérico; al abrirla, el título; al '
        'bloquearla, otra vez el genérico', () async {
      final container = await open();
      await listen(container, 'El Imperio');
      await resolve(container);

      expect(
        container.read(continueListeningDisplayProvider),
        const ContinueListeningDisplay(title: 'El Imperio'),
      );
      expect(shown(container), ContinueListeningShown.protected);

      container.read(vaultSessionControllerProvider.notifier).markUnlocked();
      expect(
        container.read(continueListeningDisplayProvider),
        const ContinueListeningDisplay(title: 'El Imperio', openBoot: boot),
      );
      expect(shown(container), ContinueListeningShown.title);

      await container.read(vaultSessionControllerProvider.notifier).lock();
      expect(shown(container), ContinueListeningShown.protected);
    });

    test('abierta en este encendido —sin pedir la clave—, el título; '
        'abierta en el anterior, el genérico', () async {
      final same = await open(openBoot: boot);
      await listen(same, 'El Imperio');
      await resolve(same);
      expect(shown(same), ContinueListeningShown.title);

      final rebooted = await open(now: 'arranque-8', openBoot: boot);
      await listen(rebooted, 'El Imperio');
      await resolve(rebooted);
      expect(rebooted.read(continueListeningDisplayProvider)!.openBoot, isNull);
      expect(
        rebooted.read(continueListeningDisplayProvider)!.shownIn('arranque-8'),
        ContinueListeningShown.protected,
      );
    });

    test('si no se sabe el encendido, oculta aunque la bóveda esté '
        'abierta', () async {
      final container = await open(bootFails: true);
      await listen(container, 'El Imperio');
      await resolve(container);
      container.read(vaultSessionControllerProvider.notifier).markUnlocked();
      await container
          .read(deviceBootNowProvider.future)
          .catchError((_) => null);

      final display = container.read(continueListeningDisplayProvider)!;
      expect(display.openBoot, isNull);
      expect(display.shownIn(boot), ContinueListeningShown.protected);
    });

    test('prender el interruptor lo muestra al instante con la bóveda '
        'cerrada, y queda guardado; apagarlo lo vuelve a ocultar', () async {
      final container = await open();
      await listen(container, 'El Imperio');
      await resolve(container);
      final sent = <ContinueListeningDisplay?>[];
      container.listen(
        continueListeningDisplayProvider,
        (_, next) => sent.add(next),
      );

      await container
          .read(continueListeningShowWhileLockedProvider.notifier)
          .set(show: true);
      // Riverpod avisa a quien escucha en la vuelta siguiente.
      await pumpEventQueue();
      expect(sent, [
        const ContinueListeningDisplay(
          title: 'El Imperio',
          showWhileLocked: true,
        ),
      ]);
      expect(sent.single!.shownIn('arranque-8'), ContinueListeningShown.title);

      // Al volver a abrir la app, sigue prendido.
      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);
      expect(reopened.read(continueListeningShowWhileLockedProvider), isTrue);

      // Apagarlo lo oculta otra vez.
      await container
          .read(continueListeningShowWhileLockedProvider.notifier)
          .set(show: false);
      await pumpEventQueue();
      expect(sent.last!.shownIn(boot), ContinueListeningShown.protected);
    });

    test('a la vista por elección, con la bóveda abierta o cerrada, el '
        'título', () async {
      final container = await open(
        stored: {'continue_listening.show_while_locked': true},
      );
      await listen(container, 'El Imperio');
      await resolve(container);
      expect(shown(container), ContinueListeningShown.title);

      container.read(vaultSessionControllerProvider.notifier).markUnlocked();
      expect(shown(container), ContinueListeningShown.title);
    });

    test('lo escuchado nuevo llega con la misma condición', () async {
      final container = await open();
      await resolve(container);
      expect(shown(container), ContinueListeningShown.nothing);

      await listen(container, 'Otro');
      expect(
        container.read(continueListeningDisplayProvider),
        const ContinueListeningDisplay(title: 'Otro'),
      );
    });
  });
}
