import 'package:flutter/material.dart';

/// Un color estable por espacio, para que el grafo pinte cada nodo según a
/// qué espacio pertenece sin que nadie tenga que elegir un color a mano
/// para cada uno.
///
/// Determinístico por el `hashCode` del id: el mismo espacio sale siempre
/// con el mismo color, entre una apertura del grafo y la siguiente — mismo
/// criterio que el layout determinístico de `computeGraphLayout`, aplicado
/// acá al color en vez de a la posición.
///
/// `spaceId == null` —"sin espacio"— no entra en el hash: es un estado
/// normal y no una categoría más, así que sale siempre del mismo gris
/// neutro en vez de competir por un hueco en la rueda de colores.
Color spaceNodeColor(String? spaceId, ColorScheme scheme) {
  if (spaceId == null) return scheme.surfaceContainerHighest;

  final hue = (spaceId.hashCode.abs() % 360).toDouble();
  final lightness = scheme.brightness == Brightness.dark ? 0.32 : 0.82;

  return HSLColor.fromAHSL(1, hue, 0.55, lightness).toColor();
}

/// El color de ícono y texto que combina con [spaceNodeColor] — siempre el
/// tono "on" oscuro u claro que corresponde según qué tan clara salió la
/// mezcla, para que el contraste no dependa de adivinar bien la luminosidad
/// de un color generado.
Color spaceNodeForeground(String? spaceId, ColorScheme scheme) {
  if (spaceId == null) return scheme.onSurfaceVariant;

  return scheme.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.92)
      : Colors.black.withValues(alpha: 0.78);
}
