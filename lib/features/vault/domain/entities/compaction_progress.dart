import 'package:flutter/foundation.dart';

/// En qué va una compactación.
enum CompactionPhase {
  /// Midiendo qué hay para recuperar y si hay disco. Todavía no cambió nada.
  checking,

  /// La primera vez, SQLite reescribe la bóveda entera. Es UNA sola operación:
  /// no informa avance y, una vez empezada, no se puede detener —ni el sistema
  /// ni SQLite dan cómo interrumpirla—, así que quien quiera cancelar tiene que
  /// hacerlo antes.
  rewriting,

  /// Las veces siguientes se devuelven las páginas libres de a tramos: se ve
  /// cuántas van y se puede cancelar entre un tramo y el siguiente sin dejar
  /// nada a medias.
  returning,

  /// Comprobando que no se perdió nada: la misma cantidad de filas en cada
  /// tabla y el texto de cada fuente reconstruido por sus chunks.
  verifying;

  /// Si en esta fase todavía se puede pedir que pare.
  bool get isCancellable => this == checking || this == returning;
}

/// Un aviso de avance de la compactación.
@immutable
class CompactionProgress {
  const CompactionProgress(this.phase, {this.done = 0, this.total = 0});

  final CompactionPhase phase;

  /// Cuánto va, en la unidad de la fase: páginas devueltas en
  /// [CompactionPhase.returning], fuentes comprobadas en
  /// [CompactionPhase.verifying]. Cero si la fase no cuenta nada.
  final int done;

  /// Cuánto hay en total, en esa misma unidad; cero si no se sabe.
  final int total;

  /// El avance de 0 a 1, o `null` si esta fase no informa uno —quien lo muestra
  /// dibuja entonces un indicador sin fin—.
  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  @override
  bool operator ==(Object other) =>
      other is CompactionProgress &&
      other.phase == phase &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);

  @override
  String toString() => 'CompactionProgress($phase, $done de $total)';
}

/// El pedido de parar una compactación en curso.
///
/// Quien compacta lo mira entre un paso y otro —no interrumpe nada a la mitad—,
/// y por eso hay fases en las que no puede atenderlo: ver
/// [CompactionPhase.isCancellable].
class CompactionCancellation {
  bool _requested = false;

  bool get isRequested => _requested;

  void cancel() => _requested = true;
}
