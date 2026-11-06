import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';

/// El renglón de un índice de libro (F46, paso 3): el título, los puntos y la
/// página a la derecha, como el índice de Word.
void main() {
  const style = TextStyle(fontSize: 14, height: 1.3);

  Future<RenderIndexLeaderLine> pump(
    WidgetTester tester, {
    required String title,
    String? page = 'p. 47',
    double width = 300,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: IndexLeaderLine(
                title: TextSpan(text: title),
                titleStyle: style,
                page: page,
              ),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderIndexLeaderLine>(
      find.byType(IndexLeaderLine),
    );
  }

  testWidgets('un título corto: los puntos van del final del título hasta la '
      'página, que queda contra el borde derecho', (tester) async {
    final line = await pump(tester, title: 'Nicea');

    final page = line.debugPageRect!;
    final leader = line.debugLeader!;
    expect(page.right, 300);
    expect(leader.to, lessThan(page.left));
    expect(leader.from, lessThan(80));
    expect(leader.to - leader.from, greaterThan(100));
  });

  testWidgets('un título largo se parte, los puntos siguen al final del '
      'último renglón y la página va a su altura', (tester) async {
    final short = await pump(tester, title: 'Nicea');
    final oneLine = short.size.height;
    final line = await pump(
      tester,
      title:
          'El Concilio de Nicea y la discusión sobre la naturaleza de Cristo '
          'en el siglo cuarto',
    );

    expect(line.size.height, greaterThan(oneLine * 1.5));
    final leader = line.debugLeader!;
    final page = line.debugPageRect!;
    // La página, a la altura del último renglón, no del primero.
    expect(page.top, greaterThan(oneLine / 2));
    expect(leader.baseline, greaterThan(oneLine));
    expect(page.right, 300);
  });

  testWidgets('los puntos salen del final del último renglón, no del ancho '
      'del título: un último renglón corto deja una línea larga', (
    tester,
  ) async {
    final line = await pump(tester, title: 'abcdefghijklm abcdefghijklm x');

    final leader = line.debugLeader!;
    // Tres renglones; el último es solo «x».
    expect(line.size.height, greaterThan(40));
    expect(leader.from, lessThan(60));
    expect(leader.to - leader.from, greaterThan(120));
  });

  testWidgets('nunca llega hasta la página: siempre queda lugar para los '
      'puntos', (tester) async {
    final line = await pump(tester, title: List.filled(40, 'palabra').join());

    final leader = line.debugLeader;
    final page = line.debugPageRect!;
    expect(leader, isNotNull);
    expect(leader!.to, lessThan(page.left));
    // Los 18 puntos de lugar que se guardan siempre, enteros.
    expect(leader.to - leader.from, greaterThanOrEqualTo(18));
  });

  testWidgets('sin página, ni puntos ni número: el título solo', (
    tester,
  ) async {
    final line = await pump(tester, title: 'Texto completo', page: null);

    expect(line.debugPageRect, isNull);
    expect(line.debugLeader, isNull);
  });

  testWidgets('con la letra al doble crece en alto y sigue entrando', (
    tester,
  ) async {
    final normal = (await pump(tester, title: 'El Concilio')).size.height;
    final line = await pump(tester, title: 'El Concilio', textScale: 2);

    expect(line.size.height, greaterThan(normal * 1.7));
    expect(line.debugPageRect!.right, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en un idioma que se escribe al revés, la página va a la '
      'izquierda', (tester) async {
    final line = await pump(
      tester,
      title: 'Nicea',
      direction: TextDirection.rtl,
    );

    expect(line.debugPageRect!.left, 0);
    expect(line.debugLeader, isNotNull);
  });

  testWidgets('el título se lee entero, para las pruebas y para quien lo '
      'busca', (tester) async {
    await pump(tester, title: 'Nicea');

    final widget = tester.widget<IndexLeaderLine>(find.byType(IndexLeaderLine));
    expect(widget.plainTitle, 'Nicea');
  });

  testWidgets('cambiar el título o la página vuelve a medir', (tester) async {
    final line = await pump(tester, title: 'Nicea', page: 'p. 4');
    final before = line.debugPageRect!.width;

    await pump(tester, title: 'Nicea', page: 'p. 1234');
    expect(line.debugPageRect!.width, greaterThan(before));

    await pump(tester, title: 'Nicea', page: null);
    expect(line.debugPageRect, isNull);
  });
}
