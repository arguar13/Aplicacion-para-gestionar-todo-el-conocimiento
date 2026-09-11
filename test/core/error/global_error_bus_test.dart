import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/global_error_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el estado inicial es null (nada que mostrar todavía)', () {
    final notifier = GlobalErrorNotifier();
    expect(notifier.state, isNull);
  });

  test('report() envuelve la excepción en el estado', () {
    // Arrange
    final notifier = GlobalErrorNotifier();
    const exception = NetworkException(message: 'Sin conexión');

    // Act
    notifier.report(exception);

    // Assert
    expect(notifier.state?.exception, exception);
  });

  test('dos reportes consecutivos con la misma excepción producen eventos '
      'con id distinto — un StateNotifier<Exception?> a secas deduplicaría '
      'por == y el segundo listener nunca dispararía', () {
    // Arrange
    final notifier = GlobalErrorNotifier();
    const exception = NetworkException(message: 'Sin conexión');
    final seenIds = <int>[];
    notifier.addListener((event) {
      if (event != null) seenIds.add(event.id);
    }, fireImmediately: false);

    // Act: dos reportes por separado, no un cascade con `addListener` de
    // arriba — mezclar el registro del listener con los dos `report()`
    // en una sola cadena sería menos legible, no más.
    // ignore: cascade_invocations
    notifier
      ..report(exception)
      ..report(exception);

    // Assert
    expect(seenIds.length, 2);
    expect(seenIds[0], isNot(seenIds[1]));
  });
}
