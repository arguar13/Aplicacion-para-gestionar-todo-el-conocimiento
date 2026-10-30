import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';

/// Cómo se llama la burbuja «Sin tema» donde el mapa pide un tema: en
/// `TopicItemsGraph.valueId` y en las migas. No es el valor de ninguna fila.
const kUnthemedBubbleId = '@sin-tema';

/// La burbuja «Sin tema» (F44): los documentos sin ningún valor de lo que se
/// mira, para que también estén en el mapa y no solo contados.
///
/// Alejada es un nodo más, gris, unida a las comunidades con las que sus
/// documentos se vinculan; al entrar, dibuja sus documentos como el nivel de
/// los documentos de un tema.
class UnthemedBubble {
  const UnthemedBubble({
    required this.count,
    required this.items,
    required this.communities,
    required this.linkedCount,
  });

  /// Una burbuja vacía: no se dibuja.
  const UnthemedBubble.empty()
    : count = 0,
      items = const TopicItemsGraph.empty(kUnthemedBubbleId),
      communities = const [],
      linkedCount = 0;

  /// Cuántos documentos hay sin tema.
  final int count;

  /// Lo que se dibuja al entrar: los procesados más recientemente primero,
  /// como mucho `kMaxGraphItems`, con los vínculos entre ellos. Su `valueId`
  /// es [kUnthemedBubbleId].
  final TopicItemsGraph items;

  /// Las comunidades con las que se vinculan sus documentos, de la que más
  /// vínculos tiene a la que menos: lo que la une a ellas en el panorama. El
  /// peso es la cantidad de vínculos.
  final List<CommunityLink> communities;

  /// Cuántos de sus documentos tienen algún vínculo, con lo que sea.
  final int linkedCount;

  bool get isEmpty => count == 0;
}
