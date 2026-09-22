import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/format_clock.dart';

/// Un instante de un audio o un video, como se lee en un reproductor.
void main() {
  test('menos de una hora: minutos y segundos', () {
    expect(formatClock(0), '0:00');
    expect(formatClock(14000), '0:14');
    expect(formatClock(127000), '2:07');
    expect(formatClock(59 * 60 * 1000 + 59000), '59:59');
  });

  test('desde una hora: horas, minutos y segundos', () {
    expect(formatClock(3600 * 1000), '1:00:00');
    expect(formatClock(3727000), '1:02:07');
    expect(formatClock(10 * 3600 * 1000 + 5000), '10:00:05');
  });

  test('los milisegundos de más se descartan, no se redondean', () {
    expect(formatClock(14999), '0:14');
    expect(formatClock(999), '0:00');
  });
}
