import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/stats_charts.dart';

/// Las piezas de los gráficos de Estadísticas e Historial (F43, M16 y M17).
void main() {
  test('el tope del eje no desperdicia el alto y su mitad es un entero', () {
    expect(
      [
        for (final v in [0, 1, 3, 7, 10, 11, 13, 17, 23, 31, 45, 79, 81, 230])
          StatsBarPainter.niceCeil(v.toDouble()),
      ],
      [2, 2, 4, 8, 10, 12, 14, 20, 24, 40, 50, 80, 100, 240],
    );
    for (var v = 1; v < 5000; v += 7) {
      final top = StatsBarPainter.niceCeil(v.toDouble());
      expect(top, greaterThanOrEqualTo(v));
      expect(top / 2, (top / 2).roundToDouble(), reason: 'tope $top');
    }
  });
}
