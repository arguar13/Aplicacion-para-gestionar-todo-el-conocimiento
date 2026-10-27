import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/text_anchor_locator.dart';

void main() {
  String cut(String text, ({int start, int end})? range) =>
      text.substring(range!.start, range.end);

  test('tal cual, donde esté', () {
    const text = 'El cono-\ncimiento acumulado de siglos.';
    final range = locateExcerpt(text, 'acumulado');

    expect(range, (start: 18, end: 27));
  });

  test('un subrayado de la extracción vieja de un PDF —renglones unidos, '
      'palabra cortada unida— se encuentra en la nueva, que los conserva', () {
    const nuevo =
        'he eludido positivamente\ntoda referencia técnica. Las ex-\n'
        'plicaciones van aparte.';
    final range = locateExcerpt(
      nuevo,
      'positivamente toda referencia técnica. Las explicaciones',
    );

    expect(
      cut(nuevo, range),
      'positivamente\ntoda referencia técnica. Las ex-\nplicaciones',
    );
  });

  test('el guion suave no cuenta, y los espacios seguidos son uno', () {
    const nuevo = 'la ex­plicación   final';
    expect(
      cut(nuevo, locateExcerpt(nuevo, 'explicación final')),
      'ex­plicación   final',
    );
  });

  test('repetido: gana el más cercano a donde estaba', () {
    const text = 'Aleluya. Santo. Aleluya. Santo. Aleluya.';
    // Está en 0, 16 y 32.
    expect(locateExcerpt(text, 'Aleluya', near: 30)!.start, 32);
    expect(locateExcerpt(text, 'Aleluya', near: 12)!.start, 16);
    expect(locateExcerpt(text, 'Aleluya', near: 3)!.start, 0);
  });

  test('lo que no está, no está: no se inventa un lugar', () {
    expect(locateExcerpt('Otro texto entero', 'es tu maquillaje'), isNull);
    expect(locateExcerpt('algo', ''), isNull);
  });

  test('las mayúsculas y las tildes sí cuentan: es otro texto', () {
    expect(locateExcerpt('Canción', 'cancion'), isNull);
  });

  test('un buscador para muchos fragmentos del mismo texto encuentra lo '
      'mismo que buscarlos de a uno (F41)', () {
    const text =
        'Una ex-\nplicación larga. Otra frase   partida\nen dos. '
        'Aleluya. Santo. Aleluya.';
    final locator = ExcerptLocator(text);
    for (final (excerpt, near) in [
      ('explicación larga', 0),
      ('Otra frase partida en dos.', 0),
      ('Aleluya', 60),
      ('Aleluya', 0),
      ('no está', 0),
      ('', 0),
      ('   ', 0),
    ]) {
      expect(
        locator.locate(excerpt, near: near),
        locateExcerpt(text, excerpt, near: near),
        reason: excerpt,
      );
    }
    expect(locator.text, text);
  });
}
