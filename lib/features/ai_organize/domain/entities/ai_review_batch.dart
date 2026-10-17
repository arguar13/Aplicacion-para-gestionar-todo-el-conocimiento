import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';

/// Un pedido de «Revisar con otro modelo» (F33) y cómo va: lo que muestra
/// «Lo que hizo la IA» mientras el modelo elegido revisa lo que hizo la IA en
/// varios elementos.
@immutable
class AiReviewBatch {
  const AiReviewBatch({
    required this.total,
    this.done = 0,
    this.proposed = 0,
    this.paused = false,
    this.currentTitle,
    this.waiting,
    this.resumesAt,
    this.modelMissing = false,
  });

  /// Cuántos elementos entraron en el pedido.
  final int total;

  /// Cuántos ya se revisaron, hayan dado correcciones o no.
  final int done;

  /// Cuántas correcciones quedaron en «Revisión» para que la persona decida.
  final int proposed;

  /// Si la persona lo pausó: lo que estaba en curso termina, y no se toma
  /// otro hasta reanudar.
  final bool paused;

  /// El elemento que se está revisando ahora, si alguno.
  final String? currentTitle;

  /// Por qué espera al modelo en la nube, si espera (sin cuota, sin
  /// conexión…): no se pierde nada, sigue sola a las [resumesAt] o cuando
  /// cambie lo elegido.
  final AiModelWait? waiting;
  final DateTime? resumesAt;

  /// Falta el modelo elegido: bajar Gemma o cargar una clave.
  final bool modelMissing;

  bool get finished => done >= total;

  AiReviewBatch copyWith({
    int? total,
    int? done,
    int? proposed,
    bool? paused,
    String? Function()? currentTitle,
    AiModelWait? Function()? waiting,
    DateTime? Function()? resumesAt,
    bool? modelMissing,
  }) => AiReviewBatch(
    total: total ?? this.total,
    done: done ?? this.done,
    proposed: proposed ?? this.proposed,
    paused: paused ?? this.paused,
    currentTitle: currentTitle == null ? this.currentTitle : currentTitle(),
    waiting: waiting == null ? this.waiting : waiting(),
    resumesAt: resumesAt == null ? this.resumesAt : resumesAt(),
    modelMissing: modelMissing ?? this.modelMissing,
  );

  @override
  bool operator ==(Object other) =>
      other is AiReviewBatch &&
      other.total == total &&
      other.done == done &&
      other.proposed == proposed &&
      other.paused == paused &&
      other.currentTitle == currentTitle &&
      other.waiting == waiting &&
      other.resumesAt == resumesAt &&
      other.modelMissing == modelMissing;

  @override
  int get hashCode => Object.hash(
    total,
    done,
    proposed,
    paused,
    currentTitle,
    waiting,
    resumesAt,
    modelMissing,
  );

  @override
  String toString() =>
      'AiReviewBatch($done/$total, $proposed correcciones'
      '${paused ? ', en pausa' : ''}'
      '${waiting == null ? '' : ', esperando ${waiting!.name}'}'
      '${modelMissing ? ', sin modelo' : ''})';
}
