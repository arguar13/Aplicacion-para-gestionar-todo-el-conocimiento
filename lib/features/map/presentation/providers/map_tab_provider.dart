import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';

/// Las dos pestañas del Mapa (F44, paso 2): antes eran cuatro.
enum MapTab {
  /// Lo que resume la bóveda, en cifras y tarjetas.
  summary,

  /// El lienzo único: comunidades, temas y documentos.
  map,
}

/// La pestaña del Mapa que se mira: el Resumen la primera vez y, desde ahí, la
/// última que se miró, también entre reinicios de la app.
class MapTabNotifier extends StateNotifier<MapTab> {
  MapTabNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(
        MapTab.values.asNameMap()[prefs.getString(_prefsKey)] ?? MapTab.summary,
      );

  static const _prefsKey = 'map_last_tab';

  final SharedPreferences _prefs;

  /// Pasa a [tab] al instante y lo recuerda.
  void select(MapTab tab) {
    if (tab == state) return;
    state = tab;
    unawaited(_prefs.setString(_prefsKey, tab.name));
  }
}

final mapTabProvider = StateNotifierProvider<MapTabNotifier, MapTab>(
  (ref) => MapTabNotifier(prefs: ref.watch(sharedPreferencesProvider)),
);
