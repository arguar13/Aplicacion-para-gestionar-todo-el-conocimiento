import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Recuerda el idioma elegido por el usuario (o `null` = "seguir el
/// idioma del sistema") entre reinicios de la app. Reutiliza
/// `sharedPreferencesProvider` (ya resuelto en `bootstrap()` para el tema)
/// en vez de agregar un segundo storage — incluso su key vive en el mismo
/// namespace de preferencias de la app.
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _prefsKey = 'app_locale';

  final SharedPreferences _prefs;

  static Locale? _readInitial(SharedPreferences prefs) {
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return null;
    return Locale(stored);
  }

  /// `null` = volver a seguir el idioma del sistema.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    if (locale == null) {
      await _prefs.remove(_prefsKey);
    } else {
      await _prefs.setString(_prefsKey, locale.languageCode);
    }
  }
}

final localeNotifierProvider = StateNotifierProvider<LocaleNotifier, Locale?>((
  ref,
) {
  return LocaleNotifier(prefs: ref.watch(sharedPreferencesProvider));
});

/// Resuelve un `Locale` concreto (nunca null) para código que no tiene
/// `BuildContext` — p. ej. un `StateNotifier` que necesita un mensaje
/// traducido (ver `SignUpNotifier`). Si el usuario no fijó preferencia,
/// cae al idioma del sistema operativo (leído sin contexto vía
/// `PlatformDispatcher`), y si ese idioma no está soportado, al idioma
/// base (`en`, el `template-arb-file`).
final effectiveLocaleProvider = Provider<Locale>((ref) {
  final preference = ref.watch(localeNotifierProvider);
  if (preference != null) return preference;

  final systemLanguage = Locale(
    PlatformDispatcher.instance.locale.languageCode,
  );
  return AppLocalizations.supportedLocales.contains(systemLanguage)
      ? systemLanguage
      : const Locale('en');
});
