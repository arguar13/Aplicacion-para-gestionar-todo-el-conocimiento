import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;

/// Si racha, insignias e historial de repasos se muestran (F17, D9): un
/// solo interruptor para las tres, mismo almacén que el tema y el idioma
/// de la app.
///
/// Apagarlo no borra ni pausa nada —`review_log`/`habit_event` siguen
/// registrando lo de siempre—, solo deja de MOSTRAR lo que se calcula a
/// partir de eso: sin un estado propio que "recuerde" el apagado, volver
/// a encenderlo muestra lo mismo que si nunca se hubiera apagado. Eso es
/// lo que D9 pide con "el apagado es honesto, no un pausado que sigue
/// contando por atrás" —no hay un pausado que mantener, así que no hay
/// nada que reconstruir—.
class HabitFeaturesPreferenceNotifier extends StateNotifier<bool> {
  HabitFeaturesPreferenceNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(prefs.getBool(_key) ?? true);

  static const _key = 'habit_features_enabled';

  final SharedPreferences _prefs;

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    await _prefs.setBool(_key, enabled);
  }
}

final habitFeaturesEnabledProvider =
    StateNotifierProvider<HabitFeaturesPreferenceNotifier, bool>(
      (ref) => HabitFeaturesPreferenceNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      ),
    );
