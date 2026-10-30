import 'package:sinapsis/features/map/domain/entities/community_profile.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/map_recent.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';

/// Lo que el motor sabe del mapa además del grafo y sus comunidades (F44, paso
/// 1): se calcula en el mismo isolate, con el mismo cálculo, y llega con cada
/// mapa (`KnowledgeMapSnapshot.insights`).
///
/// Quién lo usa:
///
/// - el lienzo: [communities] para rotular cada burbuja con sus dos temas,
///   [bridges] para el anillo doble, [unthemed] para la burbuja gris y
///   [search] para «⚲ Buscar» y el vuelo hasta un nodo;
/// - la ficha de un nodo: [communities] con todos los temas, los documentos,
///   los vínculos, «Une con» y «Lo más reciente»;
/// - el Resumen: [recent] para las cifras con su «+3» y «Lo nuevo», y
///   [bridges] para «Puentes entre temas».
///
/// Es un derivado: no se guarda, y si falla, falla el mapa entero con su
/// estado de siempre (`MapFailed`).
class MapInsights {
  const MapInsights({
    required this.bridges,
    required this.communities,
    required this.search,
    required this.unthemed,
    required this.recent,
  });

  /// Lo que se sabe de un mapa sin nada, o de uno calculado sin esto.
  const MapInsights.empty()
    : bridges = const BridgeAnalysis.empty(),
      communities = const CommunityProfiles.empty(),
      search = const MapSearchIndex.empty(),
      unthemed = const UnthemedBubble.empty(),
      recent = const MapRecent.none();

  final BridgeAnalysis bridges;
  final CommunityProfiles communities;
  final MapSearchIndex search;
  final UnthemedBubble unthemed;
  final MapRecent recent;
}
