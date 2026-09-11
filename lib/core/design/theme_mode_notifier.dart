import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences.getInstance()` es async, así que esta instancia se
/// resuelve una sola vez en `bootstrap()` (antes de `runApp`) y se
/// sobreescribe acá — igual que `appLoggerProvider`. Si algo la lee sin
/// pasar por ese override (p. ej. en un test que se olvidó de mockearla),
/// falla fuerte en vez de comportarse raro en silencio.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider debe sobreescribirse en bootstrap() '
    '(o en el test) antes de leerlo.',
  );
});

/// Recuerda la preferencia de tema del usuario (claro/oscuro/sistema)
/// entre reinicios de la app.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'app_theme_mode';

  final SharedPreferences _prefs;

  static ThemeMode _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_prefsKey, mode.name);
  }
}

final themeModeNotifierProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
      return ThemeModeNotifier(prefs: ref.watch(sharedPreferencesProvider));
    });
