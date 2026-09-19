import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Lo que se ve en una ventana del eje.
class TimelineWindow {
  const TimelineWindow({required this.events, required this.examined});

  /// Los eventos que tocan la ventana, ordenados como en
  /// [compareTimelineEvents].
  final List<TimelineEvent> events;

  /// Cuántos nodos del índice hubo que mirar para llegar a [events]: lo que
  /// costó la consulta. Crece con lo que se ve, no con lo que hay guardado;
  /// existe para poder comprobarlo.
  final int examined;
}

/// El orden del eje: por dónde llegan hacia el pasado, los tramos más largos
/// primero, y de ahí lo que haga falta para que dos eventos distintos nunca
/// empaten. Un orden total es lo que hace que el dibujo no cambie de un
/// cuadro al siguiente.
int compareTimelineEvents(TimelineEvent a, TimelineEvent b) {
  final byStart = a.reachFrom.compareTo(b.reachFrom);
  if (byStart != 0) return byStart;
  final byEnd = b.reachTo.compareTo(a.reachTo);
  if (byEnd != 0) return byEnd;
  final byItem = a.itemId.compareTo(b.itemId);
  if (byItem != 0) return byItem;
  return a.from.compareTo(b.from);
}

/// Un índice sobre todos los eventos que responde "qué cae en esta ventana"
/// sin recorrerlos todos.
///
/// Se arma una vez, cuando cambian los datos, y se consulta en cada cuadro
/// del gesto: con diez mil eventos y un zoom que muestra treinta, dibujar
/// tiene que costar treinta, no diez mil. Por eso la pantalla pinta lo que
/// devuelve [window] y nada más.
///
/// Es un árbol de intervalos sin punteros: los eventos ordenados por dónde
/// empiezan, con la raíz de cada tramo en su punto medio y, guardado en esa
/// posición, hasta dónde llega el evento que más se extiende dentro de ese
/// tramo. Esa cota es lo que permite descartar de un vistazo todo un tramo
/// que termina antes de la ventana —también cuando hay un evento larguísimo
/// al principio, que es donde fallaría un simple máximo acumulado—.
///
/// El índice mide el alcance de cada evento con su borde difuso incluido: un
/// "circa" cuyo centro cae fuera de la ventana pero cuyo borde entra, se
/// dibuja.
class TimelineIndex {
  factory TimelineIndex(Iterable<TimelineEvent> events) {
    final source = events.toList(growable: false);
    final count = source.length;

    // Ordenar índices contra arreglos de números y no los eventos: cada
    // comparación de [compareTimelineEvents] recalcula posiciones desde la
    // fecha, y con miles de eventos eso se paga miles de veces.
    final rawStarts = Float64List(count);
    final rawEnds = Float64List(count);
    for (var i = 0; i < count; i++) {
      rawStarts[i] = source[i].reachFrom;
      rawEnds[i] = source[i].reachTo;
    }
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) {
        final byStart = rawStarts[a].compareTo(rawStarts[b]);
        if (byStart != 0) return byStart;
        final byEnd = rawEnds[b].compareTo(rawEnds[a]);
        if (byEnd != 0) return byEnd;
        return compareTimelineEvents(source[a], source[b]);
      });

    final sorted = [for (final i in order) source[i]];
    final starts = Float64List(count);
    final ends = Float64List(count);
    for (var i = 0; i < count; i++) {
      starts[i] = rawStarts[order[i]];
      ends[i] = rawEnds[order[i]];
    }

    return TimelineIndex._(sorted, starts, ends, Float64List(count))
      .._fillSubtreeEnds(0, count);
  }

  TimelineIndex._(this._events, this._starts, this._ends, this._subtreeEnd);

  final List<TimelineEvent> _events;
  final Float64List _starts;
  final Float64List _ends;

  /// En la posición de la raíz de cada tramo, el mayor final de todo el
  /// tramo.
  final Float64List _subtreeEnd;

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  /// De dónde a dónde llegan todos los eventos, o `null` si no hay ninguno.
  /// Para encuadrar el eje al abrir la pantalla.
  ({double from, double to})? get extent {
    if (_events.isEmpty) return null;
    return (from: _starts.first, to: _subtreeEnd[_events.length >> 1]);
  }

  double _fillSubtreeEnds(int low, int high) {
    if (low >= high) return double.negativeInfinity;
    final root = (low + high) >> 1;
    final ownEnd = math.max(
      _ends[root],
      math.max(_fillSubtreeEnds(low, root), _fillSubtreeEnds(root + 1, high)),
    );
    _subtreeEnd[root] = ownEnd;
    return ownEnd;
  }

  /// Los eventos que se solapan con la ventana `[from, to)`.
  TimelineWindow window(double from, double to) {
    final found = <TimelineEvent>[];
    final examined = _collect(0, _events.length, from, to, found);
    return TimelineWindow(events: found, examined: examined);
  }

  /// Junta en [into], en orden, lo que toca `[from, to)` dentro del tramo
  /// `[low, high)`, y devuelve cuántos nodos miró.
  int _collect(
    int low,
    int high,
    double from,
    double to,
    List<TimelineEvent> into,
  ) {
    if (low >= high) return 0;
    final root = (low + high) >> 1;

    // Nada de este tramo llega hasta la ventana.
    if (_subtreeEnd[root] <= from) return 1;

    final examined = 1 + _collect(low, root, from, to, into);

    // Ordenados por inicio: si la raíz ya empieza después de la ventana,
    // también todo lo que tiene a la derecha.
    if (_starts[root] >= to) return examined;

    if (_ends[root] > from) into.add(_events[root]);
    return examined + _collect(root + 1, high, from, to, into);
  }
}
