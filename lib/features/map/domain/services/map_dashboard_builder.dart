import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';

/// Cuántas contradicciones abiertas trae el tablero: las más recientes.
const kDashboardContradictions = 5;

/// Cuántos meses de crecimiento trae el tablero: los últimos.
const kDashboardGrowthMonths = 24;

/// Lo que el tablero necesita saber de cada elemento vivo.
class DashboardItem {
  const DashboardItem({
    required this.id,
    required this.isNote,
    required this.createdAt,
    this.maturity,
  });

  final String id;
  final bool isNote;
  final DateTime createdAt;

  /// Solo las notas la tienen.
  final NoteMaturity? maturity;
}

/// Una contradicción abierta con el momento en que se creó: para ordenarlas.
class DashboardContradiction {
  const DashboardContradiction({required this.contradiction, required this.at});

  final OpenContradiction contradiction;
  final DateTime at;
}

/// Arma el tablero con lo que la base entregó.
///
/// Es puro. Solo cuentan los elementos de [items] —los vivos que pasan el
/// filtro— y las contradicciones con sus DOS extremos ahí.
MapDashboard buildMapDashboard({
  required List<DashboardItem> items,
  required List<DashboardContradiction> contradictions,
}) {
  final ids = {for (final item in items) item.id};

  var notes = 0;
  final maturity = <NoteMaturity, int>{};
  final perMonth = <int, int>{};
  for (final item in items) {
    if (item.isNote) {
      notes++;
      final level = item.maturity;
      if (level != null) {
        maturity.update(level, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    perMonth.update(
      _monthKey(item.createdAt.year, item.createdAt.month),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }

  final open = [
    for (final entry in contradictions)
      if (ids.contains(entry.contradiction.fromId) &&
          ids.contains(entry.contradiction.toId))
        entry,
  ]..sort((a, b) => b.at.compareTo(a.at));

  return MapDashboard(
    itemCount: items.length,
    sourceCount: items.length - notes,
    noteCount: notes,
    openContradictionCount: open.length,
    openContradictions: [
      for (final entry in open.take(kDashboardContradictions))
        entry.contradiction,
    ],
    growth: _growth(perMonth),
    maturity: maturity,
  );
}

int _monthKey(int year, int month) => year * 12 + (month - 1);

/// Un punto por mes hasta el último con elementos, sin saltear ninguno, y solo
/// los últimos [kDashboardGrowthMonths]: el total de cada punto cuenta también
/// lo de antes de la ventana.
List<GrowthPoint> _growth(Map<int, int> perMonth) {
  if (perMonth.isEmpty) return const [];
  final first = perMonth.keys.reduce((a, b) => a < b ? a : b);
  final last = perMonth.keys.reduce((a, b) => a > b ? a : b);

  final points = <GrowthPoint>[];
  var total = 0;
  for (var key = first; key <= last; key++) {
    final added = perMonth[key] ?? 0;
    total += added;
    points.add(
      GrowthPoint(
        year: key ~/ 12,
        month: key % 12 + 1,
        added: added,
        total: total,
      ),
    );
  }
  return points.length <= kDashboardGrowthMonths
      ? points
      : points.sublist(points.length - kDashboardGrowthMonths);
}
