import 'package:sinapsis/core/domain/entities/processed_depth.dart';

/// Una contradicción que nadie revisó: un vínculo `contradicts` entre dos
/// elementos vivos, sin marca de revisado.
class OpenContradiction {
  const OpenContradiction({
    required this.relationId,
    required this.fromId,
    required this.fromTitle,
    required this.toId,
    required this.toTitle,
  });

  final String relationId;
  final String fromId;
  final String fromTitle;
  final String toId;
  final String toTitle;
}

/// Cuánto creció la bóveda en un mes.
class GrowthPoint {
  const GrowthPoint({
    required this.year,
    required this.month,
    required this.added,
    required this.total,
  });

  final int year;

  /// De 1 a 12.
  final int month;

  /// Cuántos documentos se procesaron ese mes.
  final int added;

  /// Cuántos había al terminar el mes, contando los de antes.
  final int total;
}

/// Lo que el tablero del mapa cuenta además del grafo de temas (F14): las
/// contradicciones abiertas, cuánto creció lo procesado y qué tan trabajado
/// está.
///
/// Se calcula sobre los documentos procesados vivos que pasan el mismo filtro
/// que el mapa (F41, paso 6).
class MapDashboard {
  const MapDashboard({
    required this.itemCount,
    required this.openContradictionCount,
    required this.openContradictions,
    required this.growth,
    required this.depth,
  });

  /// Un tablero sin nada.
  const MapDashboard.empty()
    : itemCount = 0,
      openContradictionCount = 0,
      openContradictions = const [],
      growth = const [],
      depth = const {};

  final int itemCount;

  /// Cuántas contradicciones hay sin revisar en total.
  final int openContradictionCount;

  /// Las más recientes de ellas —las que conviene mirar primero—: cinco, como
  /// mucho.
  final List<OpenContradiction> openContradictions;

  /// Un punto por mes, de menor a mayor, sin saltear meses, y a lo sumo los
  /// últimos 24.
  final List<GrowthPoint> growth;

  /// Cuántos documentos hay en cada escalón de lo trabajado.
  final Map<ProcessedDepth, int> depth;
}
