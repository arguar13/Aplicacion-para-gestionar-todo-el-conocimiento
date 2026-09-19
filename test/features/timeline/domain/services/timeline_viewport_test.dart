import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_viewport.dart';

void main() {
  // Datos de 44 a.C. (-43) a 1453: cruzan el cero.
  final limits = ViewportLimits.forExtent((from: -43, to: 1454));

  group('límites', () {
    test(
      'se acerca hasta medio año y se aleja hasta cuatro veces los datos',
      () {
        expect(limits.minSpan, 0.5);
        expect(limits.maxSpan, (1454 - -43) * 4);
      },
    );

    test('con pocos datos el alejamiento tiene un mínimo de veinte años', () {
      final small = ViewportLimits.forExtent((from: 476, to: 477));

      expect(small.maxSpan, 20);
    });
  });

  group('mostrar todo', () {
    test('cubre todos los datos con aire alrededor', () {
      final fit = TimelineViewport.fit(limits);

      expect(fit.from, lessThan(-43));
      expect(fit.to, greaterThan(1454));
      expect(fit.center, closeTo((limits.from + limits.to) / 2, 1e-9));
    });

    test('un solo hecho no ocupa toda la pantalla: diez años de contexto', () {
      final single = ViewportLimits.forExtent((from: 476, to: 477));

      final fit = TimelineViewport.fit(single);

      expect(fit.span, 10);
      expect(fit.center, closeTo(476.5, 1e-9));
    });
  });

  group('desplazamiento', () {
    test('corre la vista una fracción de su ancho, sin cambiar el ancho', () {
      const view = TimelineViewport(from: 100, to: 200);

      final moved = view.panned(0.25, limits);

      expect(moved.from, 125);
      expect(moved.to, 225);
      expect(moved.span, view.span);
    });

    test('hacia el pasado con signo negativo', () {
      const view = TimelineViewport(from: 100, to: 200);

      expect(view.panned(-0.5, limits).from, 50);
    });

    test('cruza el cero sin saltos', () {
      const view = TimelineViewport(from: -20, to: 20);

      final moved = view.panned(0.25, limits);

      // Se corrió diez años a la derecha: -10 a 30, sin ningún hueco en el 0.
      expect(moved.from, -10);
      expect(moved.to, 30);
    });

    test('el centro no sale de los datos', () {
      const view = TimelineViewport(from: 1000, to: 1100);

      final moved = view.panned(100, limits);

      expect(moved.center, limits.to);
      expect(moved.span, 100);
    });

    test('tampoco por el lado del pasado', () {
      const view = TimelineViewport(from: 0, to: 100);

      final moved = view.panned(-100, limits);

      expect(moved.center, limits.from);
    });
  });

  group('zoom', () {
    test(
      'acercar con scale 2 deja la mitad del ancho, alrededor del centro',
      () {
        const view = TimelineViewport(from: 100, to: 300);

        final zoomed = view.zoomed(2, limits);

        expect(zoomed.span, 100);
        expect(zoomed.center, 200);
      },
    );

    test('alejar con scale 0.5 duplica el ancho', () {
      const view = TimelineViewport(from: 100, to: 300);

      expect(view.zoomed(0.5, limits).span, 400);
    });

    test('no baja de medio año', () {
      const view = TimelineViewport(from: 100, to: 102);

      expect(view.zoomed(1000, limits).span, limits.minSpan);
    });

    test('no pasa del máximo', () {
      const view = TimelineViewport(from: 0, to: 1000);

      expect(view.zoomed(0.0001, limits).span, limits.maxSpan);
    });
  });

  group('anclada', () {
    test('el año bajo los dedos sigue bajo los dedos al hacer zoom', () {
      const start = TimelineViewport(from: 0, to: 400);
      // Los dedos están a 1/4 del ancho: el año 100.
      final focusYear = start.yearAt(0.25);

      final zoomed = TimelineViewport.anchored(
        focusYear: focusYear,
        fraction: 0.25,
        span: start.span / 4,
        limits: limits,
      );

      expect(zoomed.span, 100);
      expect(zoomed.yearAt(0.25), closeTo(100, 1e-9));
    });

    test('mover los dedos desplaza la vista: el año sigue bajo ellos', () {
      const start = TimelineViewport(from: 0, to: 400);
      final focusYear = start.yearAt(0.5); // 200

      // Los dedos se corrieron a los 3/4 del ancho, sin cambiar el zoom.
      final panned = TimelineViewport.anchored(
        focusYear: focusYear,
        fraction: 0.75,
        span: start.span,
        limits: limits,
      );

      expect(panned.yearAt(0.75), closeTo(200, 1e-9));
      expect(panned.from, -100);
    });

    test('respeta los límites de ancho', () {
      final view = TimelineViewport.anchored(
        focusYear: 500,
        fraction: 0.5,
        span: 0.01,
        limits: limits,
      );

      expect(view.span, limits.minSpan);
    });
  });

  group('acotada', () {
    test('un ancho fuera de rango vuelve al rango, manteniendo el centro', () {
      const view = TimelineViewport(from: 500, to: 500.1);

      final clamped = view.clamped(limits);

      expect(clamped.span, limits.minSpan);
      expect(clamped.center, closeTo(500.05, 1e-9));
    });
  });

  test('yearAt convierte una fracción del ancho en un año', () {
    const view = TimelineViewport(from: -100, to: 100);

    expect(view.yearAt(0), -100);
    expect(view.yearAt(0.5), 0);
    expect(view.yearAt(1), 100);
  });

  test('dos vistas iguales son iguales', () {
    expect(
      const TimelineViewport(from: 1, to: 2),
      const TimelineViewport(from: 1, to: 2),
    );
    expect(
      const TimelineViewport(from: 1, to: 2),
      isNot(const TimelineViewport(from: 1, to: 3)),
    );
  });
}
