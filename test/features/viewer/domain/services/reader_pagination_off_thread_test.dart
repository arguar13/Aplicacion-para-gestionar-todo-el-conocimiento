import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';

import '../../../../support/time_growth.dart';

/// Abrir el detalle de un libro de millones de caracteres no puede partirlo
/// entero en el hilo de la interfaz (la app dejaba de responder): la vista
/// previa necesita solo la primera hoja, y el lector parte el libro en otro
/// hilo.
void main() {
  /// Un libro de [paragraphs] párrafos de unos 700 caracteres, con títulos.
  String book(int paragraphs, {String separator = '\n\n'}) {
    final buffer = StringBuffer();
    for (var i = 0; i < paragraphs; i++) {
      if (i % 20 == 0) buffer.write('## Capítulo ${i ~/ 20}$separator');
      buffer
        ..write(
          'La **revolución** industrial cambió el [mundo](http://x.y) de forma '
                  'profunda y duradera para todos los pueblos del párrafo $i, '
                  'según cuentan los historiadores que la estudiaron. ' *
              4,
        )
        ..write(separator);
    }
    return buffer.toString();
  }

  group('firstReaderPageRange', () {
    test('es la primera página de readerPageRanges, en un libro entero', () {
      for (final content in [
        book(40),
        book(4000),
        // Un PDF: las páginas unidas por el separador de página.
        List.generate(
          300,
          (i) => 'Texto de la página $i. ' * 40,
        ).join('\n\n---\n\n'),
      ]) {
        expect(
          firstReaderPageRange(content),
          readerPageRanges(content).first,
          reason: 'largo ${content.length}',
        );
      }
    });

    test('da lo mismo que partir todo, en textos de todas las formas '
        '(comparado con readerPageRanges, 400 textos al azar)', () {
      const pieces = [
        'palabra ',
        'otra palabra más ',
        ' ',
        '  ',
        '\n',
        '\n\n',
        '\n\n\n',
        '---',
        '-----',
        '\n\n---\n\n',
        '\n\n---\n\n\n\n',
        '\n---\n',
        'x',
      ];
      for (var seed = 0; seed < 400; seed++) {
        final random = math.Random(seed);
        final buffer = StringBuffer();
        // De unos pocos caracteres a varias veces la ventana de la primera
        // página; a veces con un párrafo largo sin un solo espacio.
        final count = 1 + random.nextInt(seed.isEven ? 40 : 900);
        for (var i = 0; i < count; i++) {
          final piece = pieces[random.nextInt(pieces.length)];
          buffer.write(random.nextInt(25) == 0 ? piece * 300 : piece);
        }
        final content = buffer.toString();
        final target = const [40, 200, 2400][random.nextInt(3)];

        expect(
          firstReaderPageRange(content, targetPageLength: target),
          readerPageRanges(content, targetPageLength: target).firstOrNull,
          reason: 'semilla $seed, largo ${content.length}, página $target',
        );
      }
    });

    test('los bordes: vacío, solo espacios, un separador al comienzo, dos '
        'seguidos, uno al final', () {
      for (final content in [
        '',
        ' \n\n ',
        '\n\n---\n\nHola mundo.',
        'Uno.\n\n---\n\n\n\n---\n\nDos.',
        'Uno.\n\n---\n\n',
        '---',
        'x' * 50000,
        ' ' * 30000 + 'Hola.',
        'Hola.\n\n${' ' * 25000}Chau.',
        'Hola.${'\n' * 3000}---\n\nChau.',
      ]) {
        expect(
          firstReaderPageRange(content),
          readerPageRanges(content).firstOrNull,
          reason: 'largo ${content.length}',
        );
      }
    });

    test('mirar la primera hoja no cuesta más porque el libro sea más largo: '
        'cuatro veces más texto, el mismo tiempo (no cuatro veces)', () async {
      final small = book(1500);
      final big = book(6000);
      expect(big.length, greaterThan(small.length * 3.5));

      final growth = await timeGrowth(
        () => micros(() => firstReaderPageRange(small)),
        () => micros(() => firstReaderPageRange(big)),
      );

      expect(growth, lessThan(2.2));
    });

    test('partir el libro entero, en cambio, sí crece con el libro (lo que la '
        'prueba de arriba tiene que distinguir)', () async {
      final small = book(1500);
      final big = book(6000);

      final growth = await timeGrowth(
        () => micros(() => readerPageRanges(small)),
        () => micros(() => readerPageRanges(big)),
      );

      expect(growth, greaterThan(2.5));
      expect(growth, lessThan(7));
    });
  });

  group('readerPageRangesOff', () {
    test(
      'un libro largo se parte en otro hilo y da las mismas páginas',
      () async {
        final content = book(1500);
        expect(content.length, greaterThan(kReaderInlineChars));

        expect(await readerPageRangesOff(content), readerPageRanges(content));
      },
    );

    test('no traba el hilo de la interfaz: partirlo acá lo deja sin atender '
        'todo el tiempo que lleva; en otro hilo, una fracción', () async {
      final content = book(6000);

      final inline = await stallShare(() async => readerPageRanges(content));
      final off = await stallShare(() => readerPageRangesOff(content));

      expect(inline, greaterThan(0.8));
      expect(off, lessThan(0.5));
    });

    test(
      'un texto corto se parte en el momento, con las mismas páginas',
      () async {
        const content = 'Página uno.\n\n---\n\nPágina dos.';

        expect(await readerPageRangesOff(content), readerPageRanges(content));
      },
    );

    test('los números sueltos que cruzan de un hilo al otro vuelven a ser las '
        'páginas', () {
      final content = book(300);
      final pages = readerPageRanges(content);

      expect(readerPagesFromBounds(readerPageBounds(content)), pages);
    });
  });
}
