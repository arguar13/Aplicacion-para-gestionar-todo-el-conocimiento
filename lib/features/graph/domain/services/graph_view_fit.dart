import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// La transformación que centra y escala el grafo entero para que quepa en
/// el visor, sin que ningún nodo quede cortado en un borde.
///
/// Aparte de `computeGraphLayout` porque resuelve un problema distinto: el
/// layout decide *dónde* va cada nodo dentro del lienzo, esto decide *cómo
/// mirar* ese lienzo — con qué zoom y centrado en qué punto — para que se
/// vea entero de entrada, sin que alguien tenga que ir alejando la imagen a
/// mano hasta encontrar los nodos que quedaron fuera de pantalla. Es el
/// mismo motivo por el que `GraphScreen` calcula un componente conexo por
/// vez (ver `computeConnectedComponents`): cuantos más nodos sueltos entre
/// sí haya en pantalla, más lejos hay que alejarse para verlos todos, y acá
/// es donde ese alejamiento se calcula.
///
/// Función pura y determinística a propósito, igual que
/// `computeGraphLayout`: se prueba con números concretos, sin montar
/// ningún widget ni depender de un tamaño de pantalla real.
Matrix4 computeFitTransform({
  required Map<String, Offset> positions,
  required Size viewportSize,
  // Cuánto aire se deja alrededor del contenido: lo mismo que el margen del
  // layout, cubre lo que la etiqueta de un nodo puede sobresalir de su
  // centro, para que no quede justo al ras del borde del visor.
  double contentMargin = 70,
  double minScale = 0.1,
  double maxScale = 3,
}) {
  if (positions.isEmpty || viewportSize.isEmpty) return Matrix4.identity();

  final xs = positions.values.map((p) => p.dx);
  final ys = positions.values.map((p) => p.dy);
  final minX = xs.reduce(math.min) - contentMargin;
  final maxX = xs.reduce(math.max) + contentMargin;
  final minY = ys.reduce(math.min) - contentMargin;
  final maxY = ys.reduce(math.max) + contentMargin;

  final contentWidth = maxX - minX;
  final contentHeight = maxY - minY;
  // Un solo nodo —o varios apilados exactamente en el mismo punto— da un
  // contenido de ancho o alto cero: dividir por eso sería infinito. Ahí no
  // hay nada que encuadrar más que centrarlo, con el zoom por defecto.
  if (contentWidth <= 0 || contentHeight <= 0) return Matrix4.identity();

  final scale = math
      .min(
        viewportSize.width / contentWidth,
        viewportSize.height / contentHeight,
      )
      .clamp(minScale, maxScale);

  final contentCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final viewportCenter = Offset(
    viewportSize.width / 2,
    viewportSize.height / 2,
  );

  // Se arma multiplicando de derecha a izquierda —Matrix4 aplica las
  // transformaciones en ese orden—: primero corre el contenido para que su
  // centro caiga en el origen, después escala, y por último lo vuelve a
  // correr hasta el centro del visor. El resultado es "el contenido
  // centrado en el visor, a este zoom", que es exactamente lo que
  // `TransformationController.value` espera.
  return Matrix4.identity()
    ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
    ..scaleByDouble(scale, scale, scale, 1)
    ..translateByDouble(-contentCenter.dx, -contentCenter.dy, 0, 1);
}
