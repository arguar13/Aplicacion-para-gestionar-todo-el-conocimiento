import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/fit_text.dart';

/// El ajuste del texto (F43): el corazón de «nunca desborda». Con la letra
/// de las pruebas cada carácter mide 1 em de ancho y, con interlineado 1,
/// cada línea mide 1 em de alto: las cuentas son exactas.
void main() {
  const style = TextStyle(fontSize: 10, height: 1);

  FitTextResult solve(
    List<FitTextItem> items, {
    double width = 100,
    double height = 100,
    double minScale = 0.5,
    double? fixedScale,
  }) => FitTextLayout.solve(
    items: items,
    maxWidth: width,
    maxHeight: height,
    minScale: minScale,
    fixedScale: fixedScale,
  );

  FitTextItem item(
    String text, {
    double gap = 0,
    int? maxLines,
    double ornament = 0,
    double leading = 0,
  }) => FitTextItem(
    text: text,
    style: style,
    gapBefore: gap,
    maxLines: maxLines,
    ornamentHeight: ornament,
    leadingWidth: leading,
  );

  test('lo que entra va a escala 1, entero', () {
    final result = solve([item('aa bb')], height: 20);
    expect(result.scale, 1);
    expect(result.complete, isTrue);
    expect(result.height, 10);
  });

  test('lo que no entra se achica a la escala más grande que entra', () {
    // 19 caracteres: a escala 1 son dos líneas (20 de alto); entran en una
    // línea de 100 a partir de 100 / 190 = 0,526.
    final result = solve([item('aaaa bbbb cccc dddd')], height: 10);
    expect(result.scale, lessThanOrEqualTo(100 / 190 + 1e-3));
    expect(result.scale, greaterThan(0.5));
    expect(result.complete, isTrue);
    expect(result.height, lessThanOrEqualTo(10));
  });

  test(
    'el espacio, el adorno y la viñeta cuentan y se achican con el texto',
    () {
      final result = solve([
        item('aaaa'),
        item('bbbb', gap: 10, ornament: 10, leading: 20),
      ], height: 40);
      // A escala 1: 10 + 10 + 10 + 10 = 40, menos el margen de seguridad.
      expect(result.scale, lessThan(1));
      expect(result.height, lessThanOrEqualTo(40 - FitTextLayout.safety));
      expect(solve([item('aaaa'), item('bbbb', gap: 10)], height: 31).scale, 1);
    },
  );

  test('un tope de líneas hace achicar antes de cortar con «…»', () {
    // Doce caracteres en una sola línea de 100: hace falta 100 / 120.
    final result = solve([item('aaaaa bbbbbb', maxLines: 1)]);
    expect(result.scale, lessThanOrEqualTo(100 / 120));
    expect(result.scale, greaterThan(0.75));
    expect(result.complete, isTrue);
  });

  test('una palabra más ancha que su lugar hace achicar: no se parte', () {
    // Sobra alto, pero «Constantinopla» (14) no entra en 100 a escala 1.
    final result = solve([item('Constantinopla')], height: 1000);
    expect(result.scale, lessThanOrEqualTo(100 / 140));
    expect(result.scale, greaterThan(0.69));
  });

  test('si ni a la escala mínima entra, se recortan líneas con «…»', () {
    final long = List.filled(40, 'abcd').join(' ');
    final result = solve([item(long)], height: 22);
    expect(result.scale, 0.5);
    expect(result.maxLines.single, isNotNull);
    expect(result.height, lessThanOrEqualTo(22));
    expect(result.complete, isFalse);
  });

  test('primero pierde líneas el texto más largo', () {
    final result = solve(
      [item('aa'), item(List.filled(30, 'abcd').join(' '))],
      height: 21,
      minScale: 1,
    );
    expect(result.visibleCount, 2);
    expect(result.maxLines.first, isNull);
    expect(result.maxLines.last, 1);
  });

  test('si una línea por texto no alcanza, quedan fuera los últimos', () {
    final result = solve(
      [for (var i = 0; i < 6; i++) item('linea$i')],
      height: 25,
      minScale: 1,
    );
    expect(result.visibleCount, 2);
    expect(result.height, lessThanOrEqualTo(25));
  });

  test('un lugar más bajo que un renglón a la mínima achica ese renglón por '
      'debajo de la mínima: nunca desborda', () {
    // Un renglón de 10 a la escala mínima (0,5) mide 5; en 3 de alto no
    // entra, así que baja hasta entrar.
    final short = solve([item('aa'), item('bb')], height: 3);
    expect(short.visibleCount, 1);
    expect(short.scale, lessThan(0.5));
    expect(short.height, lessThanOrEqualTo(3));
    // Con una escala fija pasa lo mismo.
    final fixed = solve([item('aa')], height: 4, fixedScale: 1);
    expect(fixed.scale, lessThan(1));
    expect(fixed.height, lessThanOrEqualTo(4));
    // Y sin un punto de alto no se dibuja nada.
    final none = solve([item('aa')], height: 0.2);
    expect(none.visibleCount, 0);
    expect(none.height, 0);
  });

  test('una escala fija se respeta, y si no entra se recorta igual', () {
    final fixed = solve([item('aa')], fixedScale: 0.7);
    expect(fixed.scale, 0.7);
    final tight = solve(
      [item(List.filled(30, 'abcd').join(' '))],
      height: 20,
      fixedScale: 1,
    );
    expect(tight.scale, 1);
    expect(tight.height, lessThanOrEqualTo(20));
  });

  test('nunca pasa del alto que tiene, con cualquier texto', () {
    final random = math.Random(4);
    String word() => String.fromCharCodes(
      List.generate(1 + random.nextInt(14), (_) => 97 + random.nextInt(26)),
    );
    for (var round = 0; round < 300; round++) {
      final items = [
        for (var i = 0; i < 1 + random.nextInt(6); i++)
          FitTextItem(
            text: List.generate(
              1 + random.nextInt(25),
              (_) => word(),
            ).join(' '),
            style: TextStyle(
              fontSize: 6 + random.nextDouble() * 30,
              height: 1.3,
            ),
            gapBefore: random.nextDouble() * 10,
            maxLines: random.nextBool() ? null : 1 + random.nextInt(3),
            leadingWidth: random.nextBool() ? 0 : 12,
          ),
      ];
      final width = 60 + random.nextDouble() * 300;
      final height = 2 + random.nextDouble() * 338;
      final result = solve(items, width: width, height: height);
      expect(result.height, lessThanOrEqualTo(height), reason: 'ronda $round');
    }
  });

  group('FitTextGroup', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );

    testWidgets('dibuja lo que midió: entra en su caja, sin desbordar', (
      tester,
    ) async {
      final text = List.filled(50, 'palabra').join(' ');
      await pump(
        tester,
        SizedBox(
          width: 120,
          height: 48,
          child: FitTextGroup(
            items: [
              FitTextItem(text: 'Título', style: style.copyWith(fontSize: 20)),
              FitTextItem(
                text: text,
                style: style,
                gapBefore: 6,
                leadingWidth: 12,
                leading: (scale) => SizedBox(width: 12 * scale),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(SizedBox).first);
      for (final element in find.byType(RichText).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.bottom, lessThanOrEqualTo(box.bottom + 0.01));
        expect(rect.right, lessThanOrEqualTo(box.right + 0.01));
      }
    });

    testWidgets('sin alto límite, se dibuja entero a escala 1', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 100,
          child: SingleChildScrollView(
            child: FitTextGroup(
              items: [FitTextItem(text: 'aaaa bbbb cccc', style: style)],
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.fontSize, 10);
      expect(text.maxLines, isNull);
    });

    testWidgets('la escala común de tarjetas hermanas es la de la que más '
        'necesita', (tester) async {
      late double shared;
      await pump(
        tester,
        Builder(
          builder: (context) {
            shared = FitTextGroup.sharedScale(context, const [
              [FitTextItem(text: 'aa', style: style)],
              [FitTextItem(text: 'aaaa bbbb cccc dddd', style: style)],
            ], const Size(100, 10));
            return const SizedBox();
          },
        ),
      );
      expect(shared, lessThanOrEqualTo(100 / 190 + 1e-3));
      expect(shared, greaterThan(0.5));
    });

    testWidgets('FitText alinea y respeta su tope de líneas', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 200,
          height: 100,
          child: FitText(
            'Un título',
            style: style,
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textAlign, TextAlign.center);
      expect(text.maxLines, 2);
    });
  });
}
