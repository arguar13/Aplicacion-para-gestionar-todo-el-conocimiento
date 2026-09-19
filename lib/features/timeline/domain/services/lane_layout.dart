import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

/// Un evento con el carril en que se dibuja: 0 es el de arriba.
typedef PlacedEvent = ({TimelineEvent event, int lane});

/// Cómo quedan repartidos los eventos visibles en carriles.
class LaneLayout {
  const LaneLayout({
    required this.placed,
    required this.hidden,
    required this.laneCount,
  });

  /// Los eventos que entraron, en el orden del eje.
  final List<PlacedEvent> placed;

  /// Cuántos no entraron por falta de carriles. Se cuentan, no se dibujan: la
  /// pantalla avisa que hay más y que acercar el zoom los separa.
  final int hidden;

  /// Cuántos carriles se usan, de 0 a lo pedido.
  final int laneCount;
}

/// Reparte [events] en carriles para que ninguno se pise con otro.
///
/// Recorre los eventos de izquierda a derecha y pone cada uno en el primer
/// carril que ya quedó libre; si no hay ninguno y todavía no se llegó a
/// [maxLanes], abre uno nuevo. Es el reparto que menos carriles usa para
/// intervalos, y es estable: el mismo conjunto se dibuja igual siempre.
///
/// Trabaja sobre lo que se ve —lo que devuelve `TimelineIndex.window`— y no
/// sobre todos los eventos: su costo es proporcional a la ventana por
/// [maxLanes], no a lo guardado.
///
/// [footprint] dice cuánto eje necesita como mínimo un evento, en años. Un
/// año exacto a poco zoom es un punto invisible, pero su rótulo ocupa
/// espacio: sin esto, dos rótulos vecinos se dibujarían uno encima del otro.
/// Depende del zoom y del texto, así que lo calcula quien dibuja.
LaneLayout layoutLanes(
  Iterable<TimelineEvent> events, {
  required int maxLanes,
  double Function(TimelineEvent event)? footprint,
}) {
  assert(maxLanes > 0, 'Hace falta al menos un carril.');

  final ordered = events.toList()..sort(compareTimelineEvents);
  final laneEnds = <double>[];
  final placed = <PlacedEvent>[];
  var hidden = 0;

  for (final event in ordered) {
    final start = event.reachFrom;
    final minEnd = start + (footprint?.call(event) ?? 0);
    final end = event.reachTo > minEnd ? event.reachTo : minEnd;

    var lane = laneEnds.indexWhere((laneEnd) => laneEnd <= start);
    if (lane < 0) {
      if (laneEnds.length >= maxLanes) {
        hidden++;
        continue;
      }
      laneEnds.add(end);
      lane = laneEnds.length - 1;
    } else {
      laneEnds[lane] = end;
    }
    placed.add((event: event, lane: lane));
  }

  return LaneLayout(placed: placed, hidden: hidden, laneCount: laneEnds.length);
}
