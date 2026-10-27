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
/// mano hasta encontrar los nodos que quedaron fuera de pantalla. Cuantos
/// más nodos sueltos entre sí haya en pantalla, más lejos hay que alejarse
/// para verlos todos, y acá es donde ese alejamiento se calcula.
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
  final content = _contentRect(positions, contentMargin);
  final fit = _fitScale(content, viewportSize);
  if (content == null || fit == null) return Matrix4.identity();

  final scale = fit.clamp(minScale, maxScale);

  final contentCenter = content.center;
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

/// Hasta dónde se puede alejar el visor de [positions] (pedido del dueño,
/// F40): nunca menos de lo que hace falta para verlo entero.
///
/// Un piso fijo dejaba afuera los grafos grandes —el grafo local con
/// «Todos» los grados no entraba ni al zoom más lejano—. El piso es
/// [floor] para un grafo chico, y para uno grande, un poco por debajo del
/// zoom que lo encuadra entero ([slack]), así queda aire alrededor.
double zoomOutLimit({
  required Map<String, Offset> positions,
  required Size viewportSize,
  double contentMargin = 70,
  double floor = 0.1,
  double slack = 0.8,
}) {
  final fit = _fitScale(_contentRect(positions, contentMargin), viewportSize);
  return fit == null ? floor : math.min(floor, fit * slack);
}

/// El rectángulo que ocupan [positions], con [margin] de aire alrededor;
/// ninguno si no hay nodos.
Rect? _contentRect(Map<String, Offset> positions, double margin) {
  if (positions.isEmpty) return null;
  final xs = positions.values.map((p) => p.dx);
  final ys = positions.values.map((p) => p.dy);
  return Rect.fromLTRB(
    xs.reduce(math.min) - margin,
    ys.reduce(math.min) - margin,
    xs.reduce(math.max) + margin,
    ys.reduce(math.max) + margin,
  );
}

/// El zoom con que [content] entra justo en [viewport], sin topes. Ninguno
/// si no hay nada que encuadrar: sin contenido, sin visor, o un contenido de
/// ancho o alto cero —un solo nodo, o varios apilados en el mismo punto—,
/// que daría un zoom infinito.
double? _fitScale(Rect? content, Size viewport) {
  if (content == null || viewport.isEmpty) return null;
  if (content.width <= 0 || content.height <= 0) return null;
  return math.min(
    viewport.width / content.width,
    viewport.height / content.height,
  );
}
