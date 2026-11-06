import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/settle_headings.dart';

/// El borde entre el lector de títulos y la base (F46, paso 2): lo que
/// devuelva el lector, la base recibe algo que cumple sus reglas, aunque los
/// `assert` del lector no corran en la app.
void main() {
  ProcessedHeading heading(
    String title, {
    int order = 0,
    int level = 1,
    int? start,
    int? end,
    int? textPage,
    int? pdfPage,
    ProcessedHeadingOrigin origin = ProcessedHeadingOrigin.textHeading,
  }) => ProcessedHeading(
    order: order,
    level: level,
    title: title,
    origin: origin,
    start: start,
    end: end,
    textPage: textPage,
    pdfPage: pdfPage,
  );

  test('lo que ya cumple queda igual, en el mismo orden', () {
    final found = [
      heading('Roma', start: 0, end: 4, textPage: 1),
      heading(
        'La República',
        order: 1,
        level: 2,
        start: 10,
        end: 22,
        textPage: 2,
      ),
      heading('El Imperio', order: 2, level: 2, pdfPage: 30),
    ];

    expect(settleHeadings(found, textLength: 100), found);
  });

  test('los títulos con los espacios juntos; un capítulo en blanco no entra, '
      'y el orden se rehace sin huecos', () {
    final kept = settleHeadings([
      heading('  El  Concilio\n de\tNicea  '),
      heading('   ', order: 1),
      heading('Arrio', order: 2),
    ], textLength: 10);

    expect(
      [for (final h in kept) (h.order, h.title)],
      [(0, 'El Concilio de Nicea'), (1, 'Arrio')],
    );
  });

  test('«Texto completo» va siempre sin título', () {
    final kept = settleHeadings([
      heading(
        'algo',
        origin: ProcessedHeadingOrigin.wholeText,
        start: 0,
        end: 0,
        textPage: 1,
      ),
    ], textLength: 0);

    expect(kept.single.title, '');
    expect(kept.single.origin, ProcessedHeadingOrigin.wholeText);
    expect((kept.single.start, kept.single.textPage), (0, 1));
  });

  test('los niveles se corren para que el más alto sea el 1', () {
    expect(
      settleHeadings([
        heading('a', level: 3),
        heading('b', order: 1, level: 4),
        heading('c', order: 2, level: 3),
      ], textLength: 0).map((h) => h.level),
      [1, 2, 1],
    );
  });

  test('el tramo y su página, juntos y solo si caen adentro del texto; si '
      'no, ninguno de los tres, y el título queda', () {
    final kept = settleHeadings([
      heading('adentro', start: 2, end: 9, textPage: 1),
      heading('hasta el final', order: 1, start: 9, end: 10, textPage: 1),
      heading('termina afuera', order: 2, start: 4, end: 11, textPage: 1),
      heading('empieza antes', order: 3, start: -1, end: 3, textPage: 1),
      heading('al revés', order: 4, start: 6, end: 4, textPage: 1),
      heading('página cero', order: 5, start: 1, end: 2, textPage: 0),
    ], textLength: 10);

    expect(
      [for (final h in kept) (h.start, h.end, h.textPage)],
      [
        (2, 9, 1),
        (9, 10, 1),
        (null, null, null),
        (null, null, null),
        (null, null, null),
        (null, null, null),
      ],
    );
    expect(kept, hasLength(6));
  });

  test('la página del PDF, solo desde 1', () {
    expect(
      settleHeadings([
        heading('a', pdfPage: 0),
        heading('b', order: 1, pdfPage: 47),
      ], textLength: 0).map((h) => h.pdfPage),
      [null, 47],
    );
  });

  test('sin títulos, nada', () {
    expect(settleHeadings(const [], textLength: 10), isEmpty);
    expect(settleHeadings([heading(' \n ')], textLength: 10), isEmpty);
  });

  test('collapseSpaces junta los espacios y saca los de los bordes', () {
    expect(collapseSpaces(' a \t b\n\nc '), 'a b c');
    expect(collapseSpaces('   '), '');
  });
}
