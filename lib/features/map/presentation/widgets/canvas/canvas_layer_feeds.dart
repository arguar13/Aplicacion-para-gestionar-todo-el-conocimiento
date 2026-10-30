import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/presentation/providers/board_providers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layers_provider.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// Lo que las capas del lienzo leen aparte del dibujo (F44, paso 5): las
/// tarjetas de cada documento para «Estudio», y si está el modelo de vínculos
/// y los parecidos entre lo que está a la vista para «Parecidos».
///
/// Cada fuente se escucha solo mientras su capa está prendida, y se suelta al
/// apagarla: una capa apagada no lee nada. Las tarjetas son la misma lectura
/// agrupada que usa el Resumen (`boardCardsProvider`), que se actualiza sola al
/// repasar; los parecidos se vuelven a pedir solo si cambian los documentos a
/// la vista, y comparan fuera del hilo de la interfaz (`ItemVectorIndex`).
///
/// No acomoda nada ni toca el dibujo: avisa con [onChanged] y el lienzo vuelve
/// a pintar lo que ya tiene acomodado.
class CanvasLayerFeeds {
  CanvasLayerFeeds(this._ref, {required this.onChanged});

  final WidgetRef _ref;

  /// Llega algo nuevo de alguna fuente.
  final VoidCallback onChanged;

  /// Las tarjetas de cada documento que tiene alguna, con «Estudio» prendida;
  /// `null` con la capa apagada o mientras llegan.
  Map<String, BoardCardFact>? get cards => _cards;
  Map<String, BoardCardFact>? _cards;

  /// Si está el modelo de vínculos, con «Parecidos» prendida; `null` con la
  /// capa apagada o mientras se pregunta.
  bool? get similarReady => _similarReady;
  bool? _similarReady;

  /// Los parecidos entre los documentos a la vista; vacío mientras llegan o
  /// sin la capa.
  List<SimilarPair> get similar => _similar;
  List<SimilarPair> _similar = const [];

  /// Si comparar los documentos falló.
  bool get similarFailed => _similarFailed;
  bool _similarFailed = false;

  /// Si se están comparando los documentos a la vista.
  bool get similarPending => _similarRequest != null && _similarPending;
  bool _similarPending = false;

  ProviderSubscription<AsyncValue<Map<String, BoardCardFact>>>? _cardsFeed;
  ProviderSubscription<AsyncValue<bool>>? _readyFeed;
  ProviderSubscription<AsyncValue<List<SimilarPair>>>? _similarFeed;
  MapSimilarRequest? _similarRequest;
  List<String> _documents = const [];

  /// Mientras se acomodan las suscripciones no se avisa: quien llama ya va a
  /// pintar.
  bool _syncing = false;

  /// Lo que cada capa de [layers] necesita leer, con [documents] a la vista
  /// —los de la red, si los hay—: escucha lo que falta y suelta lo que sobra.
  void sync({required Set<MapLayer> layers, required List<String> documents}) {
    _syncing = true;
    try {
      _syncCards(on: layers.contains(MapLayer.study));
      _documents = documents;
      _syncSimilar(on: layers.contains(MapLayer.similar));
    } finally {
      _syncing = false;
    }
  }

  /// Vuelve a preguntar si está el modelo de vínculos: se pudo bajar en el
  /// medio.
  void recheckModel() {
    if (_readyFeed == null) return;
    _ref.invalidate(mapSimilarModelReadyProvider);
  }

  void dispose() {
    _cardsFeed?.close();
    _readyFeed?.close();
    _similarFeed?.close();
  }

  void _changed() {
    if (!_syncing) onChanged();
  }

  void _syncCards({required bool on}) {
    if (!on) {
      _cardsFeed?.close();
      _cardsFeed = null;
      _cards = null;
      return;
    }
    _cardsFeed ??= _ref.listenManual(boardCardsProvider, (_, next) {
      // Mientras se vuelve a leer, lo de antes sigue a la vista.
      if (next case AsyncData(:final value)) {
        _cards = value;
        _changed();
      }
    }, fireImmediately: true);
  }

  void _syncSimilar({required bool on}) {
    if (!on) {
      _readyFeed?.close();
      _readyFeed = null;
      _similarReady = null;
      _askSimilar(null);
      return;
    }
    _readyFeed ??= _ref.listenManual(mapSimilarModelReadyProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        _similarReady = value;
        _askSimilar(_wanted());
        _changed();
      }
    }, fireImmediately: true);
    _askSimilar(_wanted());
  }

  /// Lo que hay que comparar ahora: los documentos a la vista, si hay dos y
  /// está el modelo.
  MapSimilarRequest? _wanted() =>
      (_similarReady ?? false) && _documents.length > 1
      ? MapSimilarRequest(_documents)
      : null;

  void _askSimilar(MapSimilarRequest? request) {
    if (request == _similarRequest) return;
    _similarFeed?.close();
    _similarFeed = null;
    _similarRequest = request;
    _similar = const [];
    _similarFailed = false;
    _similarPending = request != null;
    if (request == null) return;
    _similarFeed = _ref.listenManual(mapSimilarPairsProvider(request), (
      _,
      next,
    ) {
      switch (next) {
        case AsyncData(:final value):
          _similar = value;
          _similarFailed = false;
          _similarPending = false;
          _changed();
        case AsyncError():
          _similarFailed = true;
          _similarPending = false;
          _changed();
        default:
      }
    }, fireImmediately: true);
  }
}
