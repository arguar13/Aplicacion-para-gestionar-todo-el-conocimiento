import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';

/// Cuántos temas dicen el nombre de una comunidad.
const kCommunityNameTopics = 2;

/// Lo que se sabe de una comunidad además de sus temas (F44): cómo se llama,
/// cuántos documentos y vínculos tiene y con qué otras se une. Es lo que dice
/// la ficha del nodo y lo que rotula la burbuja en el lienzo.
class CommunityProfile {
  const CommunityProfile({
    required this.communityId,
    required this.topics,
    required this.nameLabels,
    required this.documentCount,
    required this.linkCount,
    required this.neighbors,
    required this.latestItemId,
  });

  final int communityId;

  /// Las posiciones en `TopicGraph.nodes` de TODOS sus temas, del más
  /// importante al menos: primero los más unidos con los demás de la
  /// comunidad, y a igual unión, los de más documentos. Es la lista entera de
  /// la ficha.
  final List<int> topics;

  /// Los nombres de sus temas principales —los primeros de [topics]—, como
  /// mucho [kCommunityNameTopics] y sin repetir un mismo nombre: una comunidad
  /// de un solo tema tiene uno.
  final List<String> nameLabels;

  /// Cuántos documentos tienen alguno de sus temas. Un documento con dos de
  /// sus temas cuenta una vez.
  final int documentCount;

  /// Cuántos vínculos unen dos documentos de la comunidad.
  final int linkCount;

  /// Las comunidades con las que más se une, de la que más a la que menos,
  /// como mucho `kCommunityNeighbors`: el «Une con» de la ficha.
  final List<CommunityLink> neighbors;

  /// El documento de la comunidad procesado más recientemente, o `null` si
  /// ninguno tiene fecha: «Lo más reciente» de la ficha.
  final String? latestItemId;

  /// El nombre, con sus temas principales: «Cristianismo · Tomás de Aquino».
  String get name => nameLabels.join(' · ');
}

/// Lo que se sabe de cada comunidad de un mapa.
class CommunityProfiles {
  const CommunityProfiles(this.all, this._byId);

  const CommunityProfiles.empty() : all = const [], _byId = const {};

  /// En el orden de las comunidades: de la más grande a la más chica.
  final List<CommunityProfile> all;

  /// La posición en [all] de cada identidad.
  final Map<int, int> _byId;

  /// Lo que se sabe de la comunidad [communityId], o `null` si no existe.
  CommunityProfile? of(int communityId) {
    final at = _byId[communityId];
    return at == null ? null : all[at];
  }
}
