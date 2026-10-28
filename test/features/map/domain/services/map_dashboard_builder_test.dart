import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/services/map_dashboard_builder.dart';

/// El tablero del mapa (F14), armado sin base de datos: cuánto hay, cuánto
/// creció, qué tan trabajado está lo procesado (F41, paso 6) y qué
/// contradicciones siguen abiertas.
void main() {
  DashboardItem item(
    String id,
    DateTime createdAt, {
    ProcessedDepth depth = ProcessedDepth.textOnly,
  }) => DashboardItem(id: id, createdAt: createdAt, depth: depth);

  DashboardContradiction contradiction(
    String id,
    String from,
    String to,
    DateTime at,
  ) => DashboardContradiction(
    at: at,
    contradiction: OpenContradiction(
      relationId: id,
      fromId: from,
      fromTitle: 'Título $from',
      toId: to,
      toTitle: 'Título $to',
    ),
  );

  MapDashboard build({
    List<DashboardItem> items = const [],
    List<DashboardContradiction> contradictions = const [],
  }) => buildMapDashboard(items: items, contradictions: contradictions);

  test('una bóveda vacía da un tablero vacío', () {
    final dashboard = build();

    expect(dashboard.itemCount, 0);
    expect(dashboard.growth, isEmpty);
    expect(dashboard.depth, isEmpty);
    expect(dashboard.openContradictions, isEmpty);
  });

  test('cuenta los documentos procesados', () {
    final dashboard = build(
      items: [
        item('p1', DateTime(2026, 1, 5)),
        item('p2', DateTime(2026, 1, 6)),
        item('p3', DateTime(2026, 1, 7), depth: ProcessedDepth.annotated),
      ],
    );

    expect(dashboard.itemCount, 3);
  });

  group('lo trabajado', () {
    test('cuenta los documentos por escalón', () {
      final dashboard = build(
        items: [
          item('p1', DateTime(2026)),
          item('p2', DateTime(2026, 1, 2)),
          item('p3', DateTime(2026, 1, 3), depth: ProcessedDepth.cut),
          item('p4', DateTime(2026, 1, 4), depth: ProcessedDepth.annotated),
        ],
      );

      expect(dashboard.depth, {
        ProcessedDepth.textOnly: 2,
        ProcessedDepth.cut: 1,
        ProcessedDepth.annotated: 1,
      });
    });
  });

  group('el crecimiento', () {
    test('un punto por mes, con el total acumulado', () {
      final dashboard = build(
        items: [
          item('a', DateTime(2026, 1, 3)),
          item('b', DateTime(2026, 1, 20)),
          item('c', DateTime(2026, 2)),
          item('d', DateTime(2026, 3, 15)),
          item('e', DateTime(2026, 3, 16)),
          item('f', DateTime(2026, 3, 17)),
        ],
      );

      expect(
        [for (final p in dashboard.growth) (p.year, p.month, p.added, p.total)],
        [(2026, 1, 2, 2), (2026, 2, 1, 3), (2026, 3, 3, 6)],
      );
    });

    test('no saltea los meses sin elementos', () {
      final dashboard = build(
        items: [
          item('a', DateTime(2025, 11, 10)),
          item('b', DateTime(2026, 2, 10)),
        ],
      );

      expect(
        [for (final p in dashboard.growth) (p.year, p.month, p.added, p.total)],
        [(2025, 11, 1, 1), (2025, 12, 0, 1), (2026, 1, 0, 1), (2026, 2, 1, 2)],
      );
    });

    test('solo los últimos 24 meses, y el total cuenta lo de antes', () {
      final dashboard = build(
        items: [
          for (var i = 0; i < 30; i++) item('i$i', DateTime(2024, 1 + i, 10)),
        ],
      );

      expect(dashboard.growth, hasLength(kDashboardGrowthMonths));
      // El último punto es junio de 2026 (el mes 30), con los 30.
      expect(dashboard.growth.last.total, 30);
      // El primero de la ventana es el mes 7, y ya había 7.
      expect(dashboard.growth.first.total, 7);
      expect(dashboard.growth.first.added, 1);
    });

    test('cruza el cambio de año', () {
      final dashboard = build(
        items: [item('a', DateTime(2025, 12, 31)), item('b', DateTime(2026))],
      );

      expect(
        [for (final p in dashboard.growth) (p.year, p.month)],
        [(2025, 12), (2026, 1)],
      );
    });
  });

  group('las contradicciones abiertas', () {
    final items = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
        item(id, DateTime(2026)),
    ];

    test('las más recientes primero, y hasta cinco', () {
      final dashboard = build(
        items: items,
        contradictions: [
          for (var i = 0; i < 7; i++)
            contradiction('r$i', 'a', 'b', DateTime(2026, 2, 1 + i)),
        ],
      );

      expect(dashboard.openContradictionCount, 7);
      expect(
        [for (final c in dashboard.openContradictions) c.relationId],
        ['r6', 'r5', 'r4', 'r3', 'r2'],
      );
    });

    test('las que tienen un extremo fuera de los elementos no cuentan', () {
      final dashboard = build(
        items: items,
        contradictions: [
          contradiction('ok', 'a', 'b', DateTime(2026, 2)),
          contradiction('sin-origen', 'zzz', 'b', DateTime(2026, 2, 2)),
          contradiction('sin-destino', 'a', 'zzz', DateTime(2026, 2, 3)),
        ],
      );

      expect(dashboard.openContradictionCount, 1);
      expect(dashboard.openContradictions.single.relationId, 'ok');
    });
  });
}
