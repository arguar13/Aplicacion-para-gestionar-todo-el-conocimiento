import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Entre qué valores se puede mover la vista de la línea de tiempo.
class ViewportLimits {
  const ViewportLimits({
    required this.from,
    required this.to,
    required this.minSpan,
    required this.maxSpan,
  });

  /// Los límites que corresponden a unos datos que van de [from] a [to]: se
  /// puede acercar hasta medio año y alejar hasta ver cuatro veces todo lo
  /// que hay, con un mínimo de veinte años para que unos pocos hechos
  /// cercanos no dejen el zoom trabado.
  factory ViewportLimits.forExtent(({double from, double to}) extent) {
    final dataSpan = extent.to - extent.from;
    return ViewportLimits(
      from: extent.from,
      to: extent.to,
      minSpan: 0.5,
      maxSpan: math.max(dataSpan * 4, 20),
    );
  }

  /// Dónde empiezan y terminan los datos. La vista puede salirse de ahí, pero
  /// su centro no: siempre queda algo a la vista a que volver.
  final double from;
  final double to;

  /// El menor y el mayor ancho de vista, en años.
  final double minSpan;
  final double maxSpan;
}

/// Qué tramo del eje se ve, de [from] a [to], en años astronómicos.
///
/// Es inmutable: cada gesto produce una vista nueva. Toda la matemática del
/// desplazamiento y del zoom vive acá y no en el widget, para probarla sin
/// dibujar nada: el widget solo traduce píxeles a fracciones del ancho.
@immutable
class TimelineViewport {
  const TimelineViewport({required this.from, required this.to});

  /// Una vista con [focusYear] a la [fraction] del ancho (0 es el borde
  /// izquierdo, 1 el derecho) y [span] años de ancho.
  ///
  /// Con ella se expresan a la vez el desplazamiento y el zoom de un gesto de
  /// pellizco: el año que estaba bajo los dedos al empezar sigue bajo los
  /// dedos, cualquiera sea el zoom.
  factory TimelineViewport.anchored({
    required double focusYear,
    required double fraction,
    required double span,
    required ViewportLimits limits,
  }) {
    assert(
      focusYear.isFinite && span.isFinite && span > 0,
      'La vista tiene que ser finita y de ancho positivo.',
    );
    final clampedSpan = span.clamp(limits.minSpan, limits.maxSpan);
    final from = focusYear - fraction * clampedSpan;
    return TimelineViewport(from: from, to: from + clampedSpan).clamped(limits);
  }

  /// La vista que muestra todos los datos con un poco de aire alrededor.
  factory TimelineViewport.fit(ViewportLimits limits) {
    final dataSpan = limits.to - limits.from;
    final span = math
        .max(dataSpan * 1.1, _fitFloor)
        .clamp(limits.minSpan, limits.maxSpan);
    final center = (limits.from + limits.to) / 2;
    return TimelineViewport(from: center - span / 2, to: center + span / 2);
  }

  /// Aunque los datos estén todos en un mismo año, "mostrar todo" no acerca
  /// más que esto: un hecho suelto se ve mejor en su contexto que ocupando
  /// toda la pantalla.
  static const _fitFloor = 10.0;

  final double from;
  final double to;

  double get span => to - from;

  double get center => (from + to) / 2;

  /// El año que cae a la [fraction] del ancho.
  double yearAt(double fraction) => from + fraction * span;

  /// Corrida de [fractionOfSpan] veces su ancho: positivo va hacia el futuro.
  TimelineViewport panned(double fractionOfSpan, ViewportLimits limits) {
    final shift = fractionOfSpan * span;
    return TimelineViewport(from: from + shift, to: to + shift).clamped(limits);
  }

  /// Acercada ([scale] mayor que 1) o alejada ([scale] menor que 1) alrededor
  /// de su centro.
  TimelineViewport zoomed(double scale, ViewportLimits limits) {
    return TimelineViewport.anchored(
      focusYear: center,
      fraction: 0.5,
      span: span / scale,
      limits: limits,
    );
  }

  /// La misma vista, con el ancho dentro de los límites y el centro sobre los
  /// datos.
  TimelineViewport clamped(ViewportLimits limits) {
    final clampedSpan = span.clamp(limits.minSpan, limits.maxSpan);
    final clampedCenter = center.clamp(limits.from, limits.to);
    return TimelineViewport(
      from: clampedCenter - clampedSpan / 2,
      to: clampedCenter + clampedSpan / 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineViewport && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'TimelineViewport($from, $to)';
}
