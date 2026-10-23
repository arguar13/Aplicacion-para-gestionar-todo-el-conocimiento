import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';

void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('sin nada guardado arranca en el tema del sistema', () async {
    final container = await containerWith({});

    expect(container.read(themeChoiceNotifierProvider), AppThemeChoice.system);
  });

  test('lo que guardaba la versión anterior se lee sin perderse', () async {
    // Antes se guardaba el nombre del `ThemeMode` en esta misma clave.
    for (final (old, expected) in [
      ('system', AppThemeChoice.system),
      ('light', AppThemeChoice.light),
      ('dark', AppThemeChoice.dark),
    ]) {
      final container = await containerWith({'app_theme_mode': old});

      expect(
        container.read(themeChoiceNotifierProvider),
        expected,
        reason: old,
      );
    }
  });

  test('un valor que no se conoce vuelve al del sistema', () async {
    final container = await containerWith({'app_theme_mode': 'rosa'});

    expect(container.read(themeChoiceNotifierProvider), AppThemeChoice.system);
  });

  test(
    'elegir un tema lo aplica al instante y lo guarda con su nombre',
    () async {
      final container = await containerWith({'app_theme_mode': 'dark'});
      final notifier = container.read(themeChoiceNotifierProvider.notifier);

      await notifier.setChoice(AppThemeChoice.sepia);

      expect(container.read(themeChoiceNotifierProvider), AppThemeChoice.sepia);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'sepia');
    },
  );

  test('cada tema elegido se vuelve a leer al reabrir la app', () async {
    for (final choice in AppThemeChoice.values) {
      final first = await containerWith({});
      await first.read(themeChoiceNotifierProvider.notifier).setChoice(choice);
      final prefs = await SharedPreferences.getInstance();

      // «Reabrir»: otro contenedor sobre las mismas preferencias.
      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);

      expect(second.read(themeChoiceNotifierProvider), choice);
    }
  });
}
