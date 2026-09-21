import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/services/svg_writer.dart';

/// El escritor de SVG del mapa (F14, D7): el documento que sale de él es un XML
/// bien formado, con lo que se dibujó y sin nada que los datos puedan romper.
void main() {
  test('el documento trae el tamaño y el fondo', () {
    final svg = SvgWriter(
      width: 400,
      height: 300.5,
      background: const Color(0xFFFFFFFF),
    ).build();

    expect(svg, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(svg, contains('xmlns="http://www.w3.org/2000/svg"'));
    expect(svg, contains('width="400" height="300.5"'));
    expect(svg, contains('viewBox="0 0 400 300.5"'));
    expect(svg, contains('<rect width="100%" height="100%" fill="#ffffff"/>'));
    expect(svg.trimRight(), endsWith('</svg>'));
  });

  test('sin fondo no hay rectángulo de fondo', () {
    final svg = SvgWriter(width: 10, height: 10).build();

    expect(svg, isNot(contains('<rect')));
  });

  test(
    'los elementos llevan sus colores como #rrggbb y su opacidad aparte',
    () {
      final writer = SvgWriter(width: 100, height: 100)
        ..line(
          Offset.zero,
          const Offset(10.126, 20),
          color: const Color(0x80FF0000),
          strokeWidth: 2.5,
        )
        ..circle(
          const Offset(5, 5),
          3,
          fill: const Color(0xFF00FF00),
          stroke: const Color(0xFF0000FF),
        );

      final svg = writer.build();

      expect(svg, contains('<line x1="0" y1="0" x2="10.13" y2="20"'));
      expect(svg, contains('stroke="#ff0000" stroke-opacity="0.5"'));
      expect(svg, contains('stroke-width="2.5"'));
      expect(svg, contains('<circle cx="5" cy="5" r="3" fill="#00ff00"'));
      expect(svg, contains('stroke="#0000ff"'));
      // Un color opaco no lleva atributo de opacidad.
      expect(svg, isNot(contains('fill-opacity')));
    },
  );

  test('un rectángulo y un triángulo', () {
    final svg =
        (SvgWriter(width: 100, height: 100)
              ..rect(
                const Rect.fromLTWH(1, 2, 30, 40),
                fill: const Color(0xFFEEEEEE),
                radius: 6,
              )
              ..triangle(
                Offset.zero,
                const Offset(4, 0),
                const Offset(2, 4),
                fill: const Color(0xFF000000),
              ))
            .build();

    expect(svg, contains('<rect x="1" y="2" width="30" height="40" rx="6"'));
    expect(svg, contains('<polygon points="0,0 4,0 2,4" fill="#000000"/>'));
  });

  test('el texto se escapa: nada de lo que traigan los datos rompe el XML', () {
    final svg =
        (SvgWriter(width: 100, height: 100)..text(
              'A & B <c> "d"',
              const Offset(10, 20),
              color: const Color(0xFF111111),
              size: 11,
              anchor: 'start',
              bold: true,
            ))
            .build();

    expect(svg, contains('A &amp; B &lt;c&gt; &quot;d&quot;</text>'));
    expect(SvgWriter.escape("it's"), 'it&apos;s');
    expect(svg, contains('text-anchor="start"'));
    expect(svg, contains('font-weight="bold"'));
    expect(svg, isNot(contains('<c>')));
  });

  test('los números no arrastran ceros ni puntos de más', () {
    final svg = (SvgWriter(
      width: 10,
      height: 10,
    )..circle(const Offset(1, 2.5), 3, fill: const Color(0xFF000000))).build();

    expect(svg, contains('cx="1" cy="2.5" r="3"'));
  });
}
