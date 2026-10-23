import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/features/export/domain/services/scanned_page_lines.dart';

/// Lo que se calcula sin PDFium: dónde cae cada renglón de una página
/// escaneada (F38, decisión D). Una página de 600 × 800 puntos, para que las
/// cuentas se hagan de cabeza: márgenes de 48 a los lados, 48 arriba y abajo,
/// 704 de alto útil.
void main() {
  const text = 'Uno\nDos\nTres\nCuatro';

  List<PdfRect> lines(
    String pageText,
    int from,
    int to, {
    double width = 600,
    double height = 800,
    PdfPageRotation rotation = PdfPageRotation.none,
  }) => scannedPageLines(
    pageText: pageText,
    from: from,
    to: to,
    width: width,
    height: height,
    rotation: rotation,
  );

  test('el renglón cae en la franja que le toca: el primero arriba, el último '
      'abajo, a todo el ancho entre márgenes', () {
    // Cuatro renglones: franjas de 176 desde 48. «Uno» está centrada en
    // 48 + 88 = 136 desde arriba, o sea 800 - 136 = 664 en el PDF.
    final [uno] = lines(text, 0, 3);
    expect(uno.left, closeTo(48, 0.001));
    expect(uno.right, closeTo(552, 0.001));
    expect((uno.top + uno.bottom) / 2, closeTo(664, 0.001));
    expect(uno.top, greaterThan(uno.bottom));

    final [cuatro] = lines(text, 13, 19);
    expect(
      (cuatro.top + cuatro.bottom) / 2,
      closeTo(800 - 48 - 3.5 * 176, 0.001),
    );
  });

  test('un renglón no ocupa toda su franja: tiene el alto de una línea de '
      'texto', () {
    final [uno] = lines(text, 0, 3);
    // 3,5 % del alto de la página, por 0,9 para que dos no se toquen.
    expect(uno.top - uno.bottom, closeTo(800 * 0.035 * 0.9, 0.001));
  });

  test('con muchos renglones, la franja es más baja que una línea y manda '
      'ella', () {
    final many = List.generate(100, (i) => 'r$i').join('\n');
    final [first] = lines(many, 0, 2);
    expect(first.top - first.bottom, closeTo(704 / 100 * 0.9, 0.001));
  });

  test('un tramo en varios renglones: un rectángulo por renglón, en orden de '
      'arriba a abajo', () {
    final rects = lines(text, 4, 12);
    expect(rects, hasLength(2));
    expect(rects[0].top, greaterThan(rects[1].top));
  });

  test('los renglones en blanco no cuentan en el reparto', () {
    final [dos] = lines('Uno\n\n   \nDos', 7, 10);
    // Dos renglones: «Dos» es el segundo, centrada en 48 + 1,5 × 352.
    expect((dos.top + dos.bottom) / 2, closeTo(800 - 48 - 1.5 * 352, 0.001));
  });

  test('lo marcado en un renglón alcanza con tocarlo, y lo que son solo '
      'espacios no marca nada', () {
    expect(lines(text, 2, 5), hasLength(2));
    expect(lines('Uno\n\n   \nDos', 4, 8), isEmpty);
    expect(lines('', 0, 0), isEmpty);
    expect(lines('   \n  ', 0, 6), isEmpty);
  });

  test('el salto de renglón y los espacios de los bordes no son parte del '
      'renglón', () {
    // Tocar solo el salto, o solo la sangría, no marca nada.
    expect(lines(text, 3, 4), isEmpty);
    expect(lines('  Uno  \n  Dos', 0, 2), isEmpty);
    expect(lines('  Uno  \n  Dos', 5, 7), isEmpty);
    expect(lines('Uno\r\nDos', 3, 4), isEmpty);
    expect(lines('Uno\t\nDos', 3, 4), isEmpty);
    expect(lines('Uno\u00A0\nDos', 3, 4), isEmpty);
    // Pero con una letra adentro, sí.
    expect(lines('  Uno  \n  Dos', 1, 3), hasLength(1));
    expect(lines('  Uno  \n  Dos', 4, 6), hasLength(1));
  });

  test('un tramo fuera del texto de la página no marca nada', () {
    expect(lines(text, 100, 120), isEmpty);
  });

  group('una página girada', () {
    // Una hoja de 600 × 800 como se ve; sin girar es de 800 × 600 con la
    // tinta de lado. El primer renglón (el de arriba de lo que se ve) es una
    // franja en 48 + 88 = 136 desde arriba de lo que se ve.
    PdfRect first(PdfPageRotation rotation) =>
        lines(text, 0, 3, rotation: rotation).single;

    test('90 grados: lo que se ve arriba es el lado izquierdo de la página '
        'sin girar', () {
      final rect = first(PdfPageRotation.clockwise90);
      // La página sin girar mide 800 de ancho y 600 de alto. Arriba de lo
      // que se ve es x chico; el ancho visual (600) es el alto sin girar.
      expect((rect.left + rect.right) / 2, closeTo(136, 0.001));
      expect(rect.top, closeTo(600 - 48, 0.001));
      expect(rect.bottom, closeTo(48, 0.001));
    });

    test('270 grados: lo que se ve arriba es el lado derecho de la página '
        'sin girar', () {
      final rect = first(PdfPageRotation.clockwise270);
      expect((rect.left + rect.right) / 2, closeTo(800 - 136, 0.001));
      expect(rect.top, closeTo(600 - 48, 0.001));
      expect(rect.bottom, closeTo(48, 0.001));
    });

    test('180 grados: lo que se ve arriba es abajo en la página sin girar', () {
      final rect = first(PdfPageRotation.clockwise180);
      expect((rect.top + rect.bottom) / 2, closeTo(136, 0.001));
      expect(rect.left, closeTo(48, 0.001));
      expect(rect.right, closeTo(552, 0.001));
    });
  });
}
