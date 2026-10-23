import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';

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

/// Recuerda el tema que eligió el usuario (el del sistema, el claro, el
/// oscuro o uno con nombre) entre reinicios de la app.
///
/// Se guarda con la misma clave y los mismos nombres que cuando solo había
/// claro, oscuro y sistema: lo que una versión anterior dejó guardado se lee
/// sin migrar nada (ver [AppThemeChoice.fromStorage]).
class ThemeChoiceNotifier extends StateNotifier<AppThemeChoice> {
  ThemeChoiceNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(AppThemeChoice.fromStorage(prefs.getString(_prefsKey)));

  static const _prefsKey = 'app_theme_mode';

  final SharedPreferences _prefs;

  /// Aplica [choice] al instante y lo guarda.
  Future<void> setChoice(AppThemeChoice choice) async {
    state = choice;
    await _prefs.setString(_prefsKey, choice.name);
  }
}

final themeChoiceNotifierProvider =
    StateNotifierProvider<ThemeChoiceNotifier, AppThemeChoice>((ref) {
      return ThemeChoiceNotifier(prefs: ref.watch(sharedPreferencesProvider));
    });
