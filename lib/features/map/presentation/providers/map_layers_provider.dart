import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/map/data/repositories/map_similar_source_impl.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/map_similar_source.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';

/// Las capas prendidas del lienzo del Mapa (F44, paso 5): al principio, solo
/// «Vínculos» (decisión B); desde ahí, lo que se eligió, también entre
/// reinicios de la app.
class MapLayersNotifier extends StateNotifier<Set<MapLayer>> {
  MapLayersNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_read(prefs));

  static const _prefsKey = 'map_layers';

  final SharedPreferences _prefs;

  /// Lo guardado, sin lo que no es una capa —de otra versión—. Sin nada
  /// guardado, las de siempre; una lista guardada vacía es «todas apagadas»,
  /// que también es una elección.
  static Set<MapLayer> _read(SharedPreferences prefs) {
    final saved = prefs.getStringList(_prefsKey);
    if (saved == null) return kDefaultMapLayers;
    final byName = MapLayer.values.asNameMap();
    return {
      for (final name in saved)
        if (byName[name] case final layer?) layer,
    };
  }

  /// Prende o apaga [layer] y lo recuerda.
  void set(MapLayer layer, {required bool on}) {
    if (state.contains(layer) == on) return;
    state = on ? {...state, layer} : ({...state}..remove(layer));
    unawaited(
      _prefs.setStringList(_prefsKey, [
        for (final layer in MapLayer.values)
          if (state.contains(layer)) layer.name,
      ]),
    );
  }
}

final mapLayersProvider =
    StateNotifierProvider<MapLayersNotifier, Set<MapLayer>>(
      (ref) => MapLayersNotifier(prefs: ref.watch(sharedPreferencesProvider)),
    );

/// Si está el modelo de vínculos, con el que «Parecidos» compara (F30): sin
/// él, la capa lo dice y lleva a descargarlo.
///
/// `autoDispose`: se vuelve a preguntar cada vez que alguien lo mira de nuevo
/// —el modelo se pudo bajar en el medio—.
final mapSimilarModelReadyProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(embeddingModelManagerProvider).isReady(),
);

/// De dónde salen los parecidos del Mapa.
final mapSimilarSourceProvider = Provider<MapSimilarSource>(
  (ref) => mapSimilarSource(
    database: ref.watch(appDatabaseProvider),
    vectors: ref.watch(itemVectorIndexProvider),
  ),
);

/// Entre qué documentos busca «Parecidos»: los que están a la vista, sin
/// importar el orden. Dos pedidos con los mismos son el mismo pedido.
@immutable
class MapSimilarRequest {
  MapSimilarRequest(Iterable<String> itemIds)
    : itemIds = List.unmodifiable(itemIds.toSet().toList()..sort());

  final List<String> itemIds;

  @override
  bool operator ==(Object other) =>
      other is MapSimilarRequest && listEquals(other.itemIds, itemIds);

  @override
  int get hashCode => Object.hashAll(itemIds);
}

/// Los parecidos entre los documentos de un pedido (F44, paso 5).
///
/// `autoDispose`: con la capa apagada, o con otros documentos a la vista,
/// nadie lo mira y se suelta. No escucha la base: un vínculo nuevo lo saca el
/// lienzo en el acto (`similarLines`), sin volver a comparar.
final mapSimilarPairsProvider = FutureProvider.autoDispose
    .family<List<SimilarPair>, MapSimilarRequest>(
      (ref, request) => ref.watch(mapSimilarSourceProvider)(request.itemIds),
    );
