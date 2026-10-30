import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/map/presentation/providers/map_tab_provider.dart';

/// La pestaña del Mapa que se mira (F44, paso 2): el Resumen la primera vez y,
/// desde ahí, la última que se miró, también entre reinicios.
void main() {
  test('la primera vez, el Resumen', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    expect(MapTabNotifier(prefs: prefs).state, MapTab.summary);
  });

  test('elegir una la recuerda, y al volver a abrir arranca en ella', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    MapTabNotifier(prefs: prefs).select(MapTab.map);

    expect(prefs.getString('map_last_tab'), 'map');
    expect(MapTabNotifier(prefs: prefs).state, MapTab.map);
  });

  test('un valor que no es una pestaña —de otra versión— vuelve al '
      'Resumen', () async {
    SharedPreferences.setMockInitialValues({'map_last_tab': 'grafo'});
    final prefs = await SharedPreferences.getInstance();

    expect(MapTabNotifier(prefs: prefs).state, MapTab.summary);
  });
}
