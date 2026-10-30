import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Las tres alturas del lienzo del Mapa (F44, paso 2): un solo dibujo que se
/// recorre con el zoom, de lejos a cerca.
enum MapAltitude {
  /// De lejos: las comunidades de temas.
  communities,

  /// Los temas de una comunidad, o todos.
  topics,

  /// Los documentos de un tema.
  documents,
}

/// Cómo se acomoda lo que se mira (F44, paso 2): lo que antes eran el Grafo y
/// el Esquema, sobre el mismo lienzo.
enum MapArrangement {
  /// La red de fuerzas de siempre.
  network,

  /// Lo que se mira en el centro y sus ramas alrededor.
  radial,

  /// De izquierda a derecha, de lo general a lo particular.
  tree;

  /// Cómo se nombra en un archivo exportado.
  String get slug => switch (this) {
    MapArrangement.network => 'red',
    MapArrangement.radial => 'radial',
    MapArrangement.tree => 'arbol',
  };
}

/// Un pedido de mirar algo en el lienzo del Mapa (F44, paso 2): lo deja quien
/// quiere llevar ahí —«Ver en el Mapa» al vincular, una fila o una cifra del
/// Resumen y, en el paso 5, la búsqueda— y lo toma el lienzo, que lo vuelve a
/// `null` al atenderlo. La pantalla, además, pasa a la pestaña Mapa.
sealed class MapCanvasRequest {
  const MapCanvasRequest();
}

/// Los documentos vinculados entre sí, con [focusId] —si viene— resaltado,
/// encuadrado junto a sus vecinos y con su ficha abierta (F44, paso 4): lo
/// que era la vista «Vínculos» (F28).
final class MapShowLinks extends MapCanvasRequest {
  const MapShowLinks({this.focusId});

  final String? focusId;
}

/// Una altura entera: las comunidades, todos los temas o —sin un tema que
/// abrir— lo vinculado.
final class MapShowAltitude extends MapCanvasRequest {
  const MapShowAltitude(this.altitude);

  final MapAltitude altitude;
}

/// Un tema entre los suyos: los temas de su comunidad, con él resaltado,
/// encuadrado junto a sus vecinos y con su ficha abierta.
final class MapShowTopic extends MapCanvasRequest {
  const MapShowTopic(this.valueId);

  final String valueId;
}

/// Un documento en su lugar (F44, paso 4): los documentos de su tema —el del
/// índice del motor (`insights.search`)—, con él resaltado y su ficha
/// abierta. Es como vuela al Mapa un documento sin vínculos, que entre lo
/// vinculado no estaría. Sin tema, lo vinculado con él en foco: su lugar es la
/// burbuja «Sin tema», que es una capa del paso 5.
final class MapShowDocument extends MapCanvasRequest {
  const MapShowDocument(this.itemId);

  final String itemId;
}

/// El pedido pendiente para el lienzo del Mapa, si hay uno.
///
/// Un pedido y no un parámetro de la ruta: el Mapa es un destino del shell que
/// sigue vivo entre pestañas, y pedir dos veces lo mismo —después de haberse
/// movido en el medio— tiene que volver a llevar ahí; una ruta igual a la
/// anterior no avisaría nada.
final mapCanvasRequestProvider = StateProvider<MapCanvasRequest?>(
  (ref) => null,
);
