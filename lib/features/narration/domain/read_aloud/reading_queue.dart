import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Qué se repite al terminar (F47, paso 2): nada, la cola entera o lo que
/// suena. El botón ⟲ del reproductor pasa de uno a otro en ese orden, como en
/// un reproductor de música.
enum ReadAloudRepeat {
  /// Al terminar, sigue la cola; sin nada en la cola, se detiene.
  off,

  /// Lo que terminó vuelve al final de la cola: la cola da vueltas.
  all,

  /// Lo que terminó vuelve a empezar.
  one;

  /// El que sigue al tocar ⟲.
  ReadAloudRepeat get next => switch (this) {
    off => all,
    all => one,
    one => off,
  };
}

/// Algo que espera su turno en la cola del lector (F47, paso 2): un
/// documento y la parte que se va a leer de él (F39).
@immutable
class QueuedReading {
  const QueuedReading(this.document, {this.scope = ReadScope.all});

  final ReadableDocument document;
  final ReadScope scope;

  /// Si es lo mismo que [other]: el mismo documento —por su id, que no
  /// cambia aunque la pantalla lo vuelva a armar— y la misma parte.
  bool sameAs(QueuedReading other) =>
      other.document.id == document.id && other.scope == scope;

  @override
  bool operator ==(Object other) =>
      other is QueuedReading &&
      other.document == document &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(document, scope);
}

/// Lo que se lee después (F47, paso 2): «Siguiente», en orden, y qué se
/// repite al terminar.
///
/// Sin estado propio: cada cambio da una cola nueva, y lo que pasa al
/// terminar —qué suena después y cómo queda la cola— sale de
/// [afterFinishing] y de [skipFrom], sin que el lector tenga que saber de
/// repeticiones.
@immutable
class ReadingQueue {
  const ReadingQueue({
    this.upcoming = const [],
    this.repeat = ReadAloudRepeat.off,
  });

  /// «Siguiente», en el orden en que va a sonar.
  final List<QueuedReading> upcoming;

  final ReadAloudRepeat repeat;

  bool get isEmpty => upcoming.isEmpty;

  /// Con [reading] al final. Si ya estaba en la cola, no se repite: queda
  /// donde estaba.
  ReadingQueue add(QueuedReading reading) {
    if (upcoming.any(reading.sameAs)) return this;
    return _with([...upcoming, reading]);
  }

  /// Sin lo que está en [index].
  ReadingQueue removeAt(int index) {
    if (index < 0 || index >= upcoming.length) return this;
    return _with([...upcoming]..removeAt(index));
  }

  /// Con lo que estaba en [from] movido a [to], contado como lo cuenta
  /// `ReorderableListView`: [to] es la posición **antes** de sacarlo, así
  /// que bajar uno es `to = from + 2`.
  ReadingQueue move(int from, int to) {
    if (from < 0 || from >= upcoming.length) return this;
    final target = (to > from ? to - 1 : to).clamp(0, upcoming.length - 1);
    if (target == from) return this;
    final next = [...upcoming];
    final moved = next.removeAt(from);
    next.insert(target, moved);
    return _with(next);
  }

  /// «Limpiar cola»: sin nada siguiente, con la repetición como estaba.
  ReadingQueue clear() => _with(const []);

  ReadingQueue withRepeat(ReadAloudRepeat repeat) =>
      ReadingQueue(upcoming: upcoming, repeat: repeat);

  /// [finished] terminó de leerse solo: qué suena después y cómo queda la
  /// cola.
  ///
  /// - Repitiendo lo que suena, vuelve a sonar eso.
  /// - Repitiendo la cola, suena lo primero de la cola y lo que terminó va al
  ///   final; con la cola vacía, vuelve a sonar lo que terminó.
  /// - Sin repetir, suena lo primero de la cola, o nada.
  ({QueuedReading? next, ReadingQueue rest}) afterFinishing(
    QueuedReading finished,
  ) {
    if (repeat == ReadAloudRepeat.one) return (next: finished, rest: this);
    return skipFrom(finished);
  }

  /// La persona tocó «siguiente» mientras sonaba [current]: como si hubiera
  /// terminado, salvo que repetir lo que suena no lo vuelve a empezar —se
  /// pidió pasar a otra cosa—.
  ({QueuedReading? next, ReadingQueue rest}) skipFrom(QueuedReading current) {
    final repeatsQueue = repeat == ReadAloudRepeat.all;
    if (upcoming.isEmpty) {
      return (next: repeatsQueue ? current : null, rest: this);
    }
    final rest = upcoming.sublist(1);
    return (
      next: upcoming.first,
      rest: _with(repeatsQueue ? [...rest, current] : rest),
    );
  }

  ReadingQueue _with(List<QueuedReading> upcoming) =>
      ReadingQueue(upcoming: List.unmodifiable(upcoming), repeat: repeat);

  @override
  bool operator ==(Object other) =>
      other is ReadingQueue &&
      other.repeat == repeat &&
      listEquals(other.upcoming, upcoming);

  @override
  int get hashCode => Object.hash(repeat, Object.hashAll(upcoming));
}
