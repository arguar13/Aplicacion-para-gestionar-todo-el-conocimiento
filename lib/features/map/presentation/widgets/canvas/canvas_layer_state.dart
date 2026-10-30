import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/canvas_layers.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layers_provider.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_layer_feeds.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// Las capas de un lienzo del Mapa (F44, paso 5): cuáles están prendidas, qué
/// se dibuja de lo que se acomodó y lo que leen aparte.
///
/// El lienzo acomoda una sola vez lo que cualquier capa puede mostrar
/// ([laidOut]: la burbuja «Sin tema», los vínculos entre documentos) y dibuja
/// lo que las capas dejan a la vista ([scene], [shownPositions]). Prender o
/// apagar una solo vuelve a recortar —no acomoda nada ni lee de nuevo lo que
/// ya se tiene—; lo que leen aparte lo escucha [feeds], solo con su capa
/// prendida.
class CanvasLayerState {
  CanvasLayerState(this._ref, {required VoidCallback onChanged})
    : layers = _ref.read(mapLayersProvider),
      feeds = CanvasLayerFeeds(_ref, onChanged: onChanged);

  final WidgetRef _ref;

  /// Las capas prendidas: las de `mapLayersProvider`, que las recuerda, y las
  /// que un pedido prendió recién ([turnOn]).
  Set<MapLayer> layers;

  /// Lo que leen las capas aparte del dibujo.
  final CanvasLayerFeeds feeds;

  /// Lo que se acomodó, con todo lo que alguna capa puede mostrar.
  GraphScene laidOut = const GraphScene.empty();

  /// Lo que se dibuja: [laidOut] con las capas prendidas (`layeredScene`).
  GraphScene scene = const GraphScene.empty();

  /// Dónde está cada nodo que se dibuja: lo que una capa esconde no cuenta
  /// para el encuadre ni para el minimapa.
  Map<String, Offset> shownPositions = const {};

  /// Los parecidos que la persona vinculó desde su «≈» (`similarPairKey`): ya
  /// no se proponen, aunque el mapa todavía no haya dibujado el vínculo.
  final _linked = <String>{};

  bool _disposed = false;

  bool has(MapLayer layer) => layers.contains(layer);

  /// Prende [layer] para lo que se pidió mirar —lo vinculado, la burbuja—, en
  /// el acto, y lo recuerda apenas termine lo que se está armando: un
  /// proveedor no se modifica mientras se arma el árbol.
  void turnOn(MapLayer layer) {
    if (layers.contains(layer)) return;
    layers = {...layers, layer};
    scheduleMicrotask(() {
      if (_disposed) return;
      _ref.read(mapLayersProvider.notifier).set(layer, on: true);
    });
  }

  /// Toma las capas que se eligieron en su hoja; `false` si no cambió nada.
  bool update(Set<MapLayer> next) {
    if (setEquals(next, layers)) return false;
    layers = next;
    return true;
  }

  /// Lo que se dibuja de [laidOut] —o de lo último que se acomodó—, con las
  /// capas de ahora y las posiciones de [positions].
  void apply(Map<String, Offset> positions, {GraphScene? laidOut}) {
    if (laidOut != null) this.laidOut = laidOut;
    final scene = this.scene = layeredScene(this.laidOut, layers);
    shownPositions = {
      for (final node in scene.nodes)
        if (positions[node.key] case final at?) node.key: at,
    };
  }

  /// Lo que las capas tienen que leer para lo que se dibuja: los parecidos,
  /// solo entre los documentos de la Red ([network]).
  void sync({required bool network}) => feeds.sync(
    layers: layers,
    documents: network ? sceneDocuments(scene) : const [],
  );

  /// Cómo va el estudio de cada documento, con «Estudio» prendida y las
  /// tarjetas ya leídas.
  MapStudyMark? Function(String itemId)? get studyOf {
    final cards = feeds.cards;
    if (!has(MapLayer.study) || cards == null) return null;
    return (itemId) => MapStudyMark.of(cards[itemId]);
  }

  /// Los parecidos que se dibujan: en la Red ([network]), entre lo que está a
  /// la vista y no está vinculado.
  List<MapSimilarLine> drawnSimilar({required bool network}) {
    if (!network || !has(MapLayer.similar)) return const [];
    return [
      for (final line in similarLines(scene, laidOut, feeds.similar))
        if (!_linked.contains(line.pair.key)) line,
    ];
  }

  /// [pair] quedó vinculado: no se propone más.
  void markLinked(SimilarPair pair) => _linked.add(pair.key);

  void dispose() {
    _disposed = true;
    feeds.dispose();
  }
}
