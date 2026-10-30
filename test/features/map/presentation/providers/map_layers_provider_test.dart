import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layers_provider.dart';

/// Las capas prendidas del Mapa (F44, paso 5): al principio solo «Vínculos»
/// (decisión B), y desde ahí lo que se eligió, también entre reinicios.
void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('la primera vez, solo «Vínculos»', () async {
    final prefs = await prefsWith({});

    expect(MapLayersNotifier(prefs: prefs).state, {MapLayer.links});
  });

  test(
    'prender y apagar se recuerda, y al volver a abrir arranca igual',
    () async {
      final prefs = await prefsWith({});
      MapLayersNotifier(prefs: prefs)
        ..set(MapLayer.study, on: true)
        ..set(MapLayer.tensions, on: true)
        ..set(MapLayer.links, on: false);

      expect(prefs.getStringList('map_layers'), ['tensions', 'study']);
      expect(MapLayersNotifier(prefs: prefs).state, {
        MapLayer.tensions,
        MapLayer.study,
      });
    },
  );

  test('todas apagadas también es una elección', () async {
    final prefs = await prefsWith({});
    MapLayersNotifier(prefs: prefs).set(MapLayer.links, on: false);

    expect(MapLayersNotifier(prefs: prefs).state, isEmpty);
  });

  test('lo que no es una capa —de otra versión— se ignora', () async {
    final prefs = await prefsWith({
      'map_layers': ['study', 'capa-vieja'],
    });

    expect(MapLayersNotifier(prefs: prefs).state, {MapLayer.study});
  });

  test('prender lo que ya está prendido no cambia nada', () async {
    final prefs = await prefsWith({});
    final notifier = MapLayersNotifier(prefs: prefs);
    final before = notifier.state;

    notifier.set(MapLayer.links, on: true);

    expect(notifier.state, same(before));
    expect(prefs.getStringList('map_layers'), isNull);
  });

  test('dos pedidos de parecidos con los mismos documentos, en cualquier '
      'orden, son el mismo', () {
    expect(
      MapSimilarRequest(const ['b', 'a', 'b']),
      MapSimilarRequest(const ['a', 'b']),
    );
    expect(
      MapSimilarRequest(const ['b', 'a']).hashCode,
      MapSimilarRequest(const ['a', 'b']).hashCode,
    );
    expect(
      MapSimilarRequest(const ['a']),
      isNot(MapSimilarRequest(const ['a', 'b'])),
    );
  });
}
