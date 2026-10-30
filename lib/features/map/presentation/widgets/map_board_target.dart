import 'package:meta/meta.dart';

/// Adónde lleva en el Mapa algo que se toca en el Resumen (F44, decisión D):
/// una altura —tocar una cifra grande—, un tema o un documento —tocar una
/// fila—. El Explorador queda para «Abrir», en la ficha del nodo.
///
/// La vista del Resumen solo dice adónde; `MapBoardPane` lo traduce a un
/// pedido del lienzo (`canvasRequestFor`, `mapCanvasRequestProvider`) y el
/// lienzo decide cómo llegar —qué altura, qué foco—, así puede crecer sin que
/// el Resumen cambie.
@immutable
sealed class MapBoardTarget {
  const MapBoardTarget();
}

/// Lo que cuenta una cifra grande del Resumen, que se mira a su altura.
enum MapBoardFigure {
  /// Los documentos: la altura de los elementos.
  documents,

  /// Los temas (o etiquetas, o valores).
  topics,

  /// Las comunidades: el Mapa entero, de lejos.
  communities,

  /// Los vínculos entre documentos: la capa de vínculos.
  links,
}

/// El Mapa a la altura de una cifra.
final class MapBoardLevel extends MapBoardTarget {
  const MapBoardLevel(this.figure);

  final MapBoardFigure figure;

  @override
  bool operator ==(Object other) =>
      other is MapBoardLevel && other.figure == figure;

  @override
  int get hashCode => figure.hashCode;

  @override
  String toString() => 'MapBoardLevel(${figure.name})';
}

/// El Mapa con un tema en foco.
final class MapBoardTopic extends MapBoardTarget {
  const MapBoardTopic(this.valueId);

  final String valueId;

  @override
  bool operator ==(Object other) =>
      other is MapBoardTopic && other.valueId == valueId;

  @override
  int get hashCode => valueId.hashCode;

  @override
  String toString() => 'MapBoardTopic($valueId)';
}

/// El Mapa con un documento en foco.
final class MapBoardItem extends MapBoardTarget {
  const MapBoardItem(this.itemId);

  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is MapBoardItem && other.itemId == itemId;

  @override
  int get hashCode => itemId.hashCode;

  @override
  String toString() => 'MapBoardItem($itemId)';
}
