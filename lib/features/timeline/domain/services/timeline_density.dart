import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Cuántos hechos hay en cada tramo de todo el rango de los datos: lo que
/// dibuja el mini mapa de la línea de tiempo (F40).
///
/// Se calcula UNA vez por lista de hechos, no por cuadro: arrastrar el eje
/// mueve solo la ventana marcada sobre estas barras. Con diez mil hechos
/// cuesta un recorrido y un acumulado, no un cruce de cada hecho con cada
/// barra: cada hecho suma +1 donde empieza y -1 donde termina, y el recuento
/// de cada barra sale de acumular esas marcas.
class TimelineDensity {
  const TimelineDensity._({
    required this.from,
    required this.to,
    required this.levels,
  });

  /// Las barras de [events] entre [from] y [to] —el rango de los datos, con el
  /// borde difuso incluido—. Un rango sin ancho se abre a un año para tener
  /// dónde repartir.
  factory TimelineDensity.of(
    Iterable<TimelineEvent> events, {
    required double from,
    required double to,
    int bins = binCount,
  }) {
    final width = to > from ? to - from : 1.0;
    final end = to > from ? to : from + width;

    // Una marca por borde de barra, con un lugar de más para el cierre del
    // último hecho.
    final marks = Int32List(bins + 1);
    for (final event in events) {
      final first = _binOf(event.from, from, width, bins);
      // El final es exclusivo: un hecho que termina justo en el borde de una
      // barra no cuenta en la siguiente.
      final last = math.max(
        first,
        (((event.to - from) / width * bins).ceil() - 1).clamp(0, bins - 1),
      );
      marks[first]++;
      marks[last + 1]--;
    }

    final counts = Int32List(bins);
    var running = 0;
    var busiest = 0;
    for (var i = 0; i < bins; i++) {
      running += marks[i];
      counts[i] = running;
      busiest = math.max(busiest, running);
    }

    // La raíz achata los picos: una década con mil hechos no deja en cero a las
    // que tienen veinte, que es justo lo que se quiere ver.
    final levels = Float64List(bins);
    if (busiest > 0) {
      for (var i = 0; i < bins; i++) {
        levels[i] = math.sqrt(counts[i] / busiest);
      }
    }
    return TimelineDensity._(from: from, to: end, levels: levels);
  }

  static int _binOf(double year, double from, double width, int bins) {
    final fraction = (year - from) / width;
    return (fraction * bins).floor().clamp(0, bins - 1);
  }

  /// Cuántas barras tiene el mini mapa: las que se dibujan, con cualquier
  /// ancho de pantalla. Más finas no se distinguirían y menos pierden dónde se
  /// juntan los hechos.
  static const binCount = 96;

  /// Dónde empiezan y terminan las barras, en el eje de `timeline_axis.dart`.
  final double from;
  final double to;

  /// La altura de cada barra, de 0 (sin hechos) a 1 (la más cargada).
  final Float64List levels;

  /// Cuántas barras hay.
  int get length => levels.length;

  /// Qué fracción del ancho —0 a 1— le toca a [year]. Puede salirse del rango:
  /// la vista del eje puede mirar más allá de los datos.
  double fractionOf(double year) => (year - from) / (to - from);

  /// El año que cae a la [fraction] del ancho.
  double yearAt(double fraction) => from + fraction * (to - from);
}
