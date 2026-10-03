import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';

/// Recuerda los interruptores de Ajustes › IA entre reinicios (F27), mismo
/// criterio que `NarrationSettingsNotifier`: una clave por interruptor, así
/// agregar uno nuevo no invalida lo guardado de los demás.
class AiOrganizeSettingsNotifier extends StateNotifier<AiOrganizeSettings> {
  AiOrganizeSettingsNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_read(prefs));

  final SharedPreferences _prefs;

  static String _key(AiOrganizeToggle toggle) => 'ai_organize_${toggle.name}';

  static AiOrganizeSettings _read(SharedPreferences prefs) {
    var settings = const AiOrganizeSettings();
    for (final toggle in AiOrganizeToggle.values) {
      final stored = prefs.getBool(_key(toggle));
      if (stored != null) settings = toggle.applyTo(settings, on: stored);
    }
    return settings;
  }

  Future<void> set(AiOrganizeToggle toggle, {required bool on}) async {
    state = toggle.applyTo(state, on: on);
    await _prefs.setBool(_key(toggle), on);
  }
}

final aiOrganizeSettingsProvider =
    StateNotifierProvider<AiOrganizeSettingsNotifier, AiOrganizeSettings>(
      (ref) => AiOrganizeSettingsNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      ),
    );

/// En qué anda la cola de la IA (F27). La cola es la única que lo escribe;
/// Ajustes › IA y "Lo que hizo la IA" lo leen.
final aiOrganizeStatusProvider = StateProvider<AiOrganizeStatus>(
  (ref) => const AiOrganizeIdle(),
);
