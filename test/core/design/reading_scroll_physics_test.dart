import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';

void main() {
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 100000,
    pixels: 0,
    viewportDimension: 800,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 3,
  );

  /// Hasta dónde llega un arrastre rápido soltado a [velocity] px/s.
  double reach(ScrollPhysics physics, double velocity) {
    final simulation = physics.createBallisticSimulation(metrics, velocity)!;
    return simulation.x(10);
  }

  test('un arrastre rápido llega más lejos que en una lista', () {
    const list = ClampingScrollPhysics();
    const reading = ReadingScrollPhysics(parent: ClampingScrollPhysics());

    expect(reach(reading, 3000), greaterThan(reach(list, 3000) * 1.3));
    expect(reading.maxFlingVelocity, list.maxFlingVelocity * readingFlingBoost);
  });

  test('sin impulso no se mueve solo', () {
    const reading = ReadingScrollPhysics(parent: ClampingScrollPhysics());

    expect(reading.createBallisticSimulation(metrics, 0), isNull);
  });
}
