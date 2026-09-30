import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/clients/html_text_decoder.dart';

/// La codificación de una página, decidida como la decide un navegador
/// (F22). Cada prueba compara el texto entero: una tilde perdida es
/// exactamente lo que se busca que no pase.
void main() {
  // "Año, niño — “café” €" en Windows-1252: ñ = F1, — = 97, “ ” = 93 94,
  // € = 80.
  final windows1252 = [
    ...latin1.encode('A'),
    0xF1,
    ...latin1.encode('o, ni'),
    0xF1,
    ...latin1.encode('o '),
    0x97,
    ...latin1.encode(' '),
    0x93,
    ...latin1.encode('caf'),
    0xE9,
    0x94,
    ...latin1.encode(' '),
    0x80,
  ];
  const expected = 'Año, niño — “café” €';

  test('sin declarar nada y en UTF-8, se lee como UTF-8', () {
    expect(decodeHtmlBytes(utf8.encode(expected)), expected);
  });

  test('el charset del Content-Type manda', () {
    expect(
      decodeHtmlBytes(
        windows1252,
        contentType: 'text/html; charset=windows-1252',
      ),
      expected,
    );
  });

  test('iso-8859-1 se lee como Windows-1252, igual que en un navegador', () {
    // Las páginas que dicen iso-8859-1 usan las comillas y las rayas de
    // Windows-1252; en Latin-1 estricto serían caracteres de control.
    expect(
      decodeHtmlBytes(
        windows1252,
        contentType: 'text/html; charset=ISO-8859-1',
      ),
      expected,
    );
  });

  test('sin Content-Type, vale el <meta charset> del documento', () {
    final page = [
      ...ascii.encode('<html><head><meta charset="windows-1252"></head><p>'),
      ...windows1252,
    ];

    expect(
      decodeHtmlBytes(page),
      '<html><head><meta charset="windows-1252"></head><p>$expected',
    );
  });

  test('y también el <meta http-equiv> de las páginas viejas', () {
    final page = [
      ...ascii.encode(
        '<meta http-equiv="Content-Type" '
        'content="text/html; charset=iso-8859-1">',
      ),
      ...windows1252,
    ];

    expect(decodeHtmlBytes(page), endsWith(expected));
  });

  test('ISO-8859-15 tiene su euro en otro lugar', () {
    expect(
      decodeHtmlBytes([
        0xA4,
        0x20,
        0xF1,
      ], contentType: 'text/html; charset=iso-8859-15'),
      '€ ñ',
    );
  });

  test('la marca de orden de bytes gana sobre lo declarado', () {
    final page = [0xEF, 0xBB, 0xBF, ...utf8.encode(expected)];

    expect(
      decodeHtmlBytes(page, contentType: 'text/html; charset=iso-8859-1'),
      expected,
    );
  });

  test('UTF-16 con su marca', () {
    final page = [
      0xFF,
      0xFE,
      for (final unit in expected.codeUnits) ...[unit & 0xFF, unit >> 8],
    ];

    expect(decodeHtmlBytes(page), expected);
  });

  test('sin declarar nada y con bytes que no son UTF-8, es una página vieja '
      'en Windows-1252', () {
    expect(decodeHtmlBytes(windows1252), expected);
  });

  // Lo que encontró la revisión independiente de F22.
  group('la revisión (F22)', () {
    test('un byte suelto no manda la página entera a Windows-1252', () {
      // Antes: "AÃ±o, niÃ±o y ño", cada tilde del resto como dos letras.
      final page = [...utf8.encode('Año, niño y '), 0xF1, ...utf8.encode('o')];

      expect(decodeHtmlBytes(page), 'Año, niño y ño');
    });

    test('Windows-1251, KOI8-R e ISO-8859-2 se leen con su tabla', () {
      expect(
        decodeHtmlBytes([
          207,
          240,
          232,
          226,
          229,
          242,
        ], contentType: 'text/html; charset=windows-1251'),
        'Привет',
      );
      expect(
        decodeHtmlBytes([
          240,
          210,
          201,
          215,
          197,
          212,
        ], contentType: 'text/html; charset=KOI8-R'),
        'Привет',
      );
      expect(
        decodeHtmlBytes([
          0xA3,
          0xF3,
          0x64,
          0xBC,
        ], contentType: 'text/html; charset=iso-8859-2'),
        'Łódź',
      );
    });

    test('una codificación que no se conoce se avisa, y la página se lee '
        'como sin declarar', () {
      final reported = <String>[];

      final text = decodeHtmlBytes(
        utf8.encode('こんにちは'),
        contentType: 'text/html; charset=Shift_JIS',
        onUnsupportedCharset: reported.add,
      );

      expect(text, 'こんにちは');
      expect(reported, ['Shift_JIS']);
    });

    test('un <meta charset> dentro de un comentario o de un script no '
        'declara nada', () {
      final page = [
        ...ascii.encode(
          [
            '<!-- <meta charset="koi8-r"> -->',
            '<script>var m = \'<meta charset="koi8-r">\';</script>',
            '<meta charset="windows-1252"><p>',
          ].join(),
        ),
        ...windows1252,
      ];

      expect(decodeHtmlBytes(page), endsWith('<p>$expected'));
    });

    test('un "charset=" en otro atributo del <meta> no declara nada', () {
      final page = utf8.encode(
        '<meta name="description" content="charset=koi8-r"><p>Año',
      );

      expect(
        decodeHtmlBytes(page),
        '<meta name="description" content="charset=koi8-r"><p>Año',
      );
    });
  });
}
