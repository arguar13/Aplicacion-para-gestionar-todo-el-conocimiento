import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';

import '../../../../support/document_parsing.dart';

void main() {
  const parser = PlainTextParser();

  Future<String> textOf(List<int> bytes) async =>
      (await parser.parseBytes(Uint8List.fromList(bytes))).markdown;

  /// [text] en UTF-16, con los bytes en el orden pedido.
  List<int> utf16(String text, {required bool littleEndian}) => [
    for (final unit in text.codeUnits)
      ...littleEndian ? [unit & 0xFF, unit >> 8] : [unit >> 8, unit & 0xFF],
  ];

  group('que sabe leer', () {
    test('texto suelto y Markdown', () {
      expect(parser.canParse(FileFormat.plainText), isTrue);
      expect(parser.canParse(FileFormat.markdown), isTrue);
      expect(parser.canParse(FileFormat.docx), isFalse);
    });
  });

  group('codificacion (F22)', () {
    test('UTF-8 sin marca llega tal cual', () async {
      expect(
        await textOf(utf8.encode('Canción del año\n')),
        'Canción del año\n',
      );
    });

    test('la marca de UTF-8 no se guarda', () async {
      expect(
        await textOf([0xEF, 0xBB, 0xBF, ...utf8.encode('Canción')]),
        'Canción',
      );
    });

    test('UTF-16 con marca, en los dos ordenes', () async {
      // Es lo que guarda el Bloc de notas de Windows al elegir "Unicode".
      expect(
        await textOf([
          0xFF,
          0xFE,
          ...utf16('Año 1990 — ñandú', littleEndian: true),
        ]),
        'Año 1990 — ñandú',
      );
      expect(
        await textOf([
          0xFE,
          0xFF,
          ...utf16('Año 1990 — ñandú', littleEndian: false),
        ]),
        'Año 1990 — ñandú',
      );
    });

    test('UTF-16 sin marca se reconoce por sus ceros', () async {
      expect(
        await textOf(utf16('Una línea\nY otra.', littleEndian: true)),
        'Una línea\nY otra.',
      );
      expect(
        await textOf(utf16('Una línea\nY otra.', littleEndian: false)),
        'Una línea\nY otra.',
      );
    });

    test('UTF-16 con caracteres fuera del plano basico', () async {
      // Un emoji son dos unidades de UTF-16: tienen que volver a juntarse.
      expect(
        await textOf([0xFF, 0xFE, ...utf16('Hola 🎵', littleEndian: true)]),
        'Hola 🎵',
      );
    });

    test('UTF-32 con marca', () async {
      final bytes = [0xFF, 0xFE, 0x00, 0x00];
      for (final rune in 'Sí 🎵'.runes) {
        bytes.addAll([
          rune & 0xFF,
          (rune >> 8) & 0xFF,
          (rune >> 16) & 0xFF,
          rune >> 24,
        ]);
      }

      expect(await textOf(bytes), 'Sí 🎵');
    });

    test('Latin-1 conserva las tildes', () async {
      // Antes salia "a�o": se leia todo como UTF-8.
      expect(
        await textOf(latin1.encode('El año de la canción.')),
        'El año de la canción.',
      );
    });

    test('Windows-1252 conserva comillas, rayas y el euro', () async {
      // Del 0x80 al 0x9F, Windows-1252 no es Latin-1.
      final bytes = [
        0x93,
        ...latin1.encode('Cita'),
        0x94,
        0x20,
        0x97,
        0x20,
        0x80,
        ...latin1.encode('5 '),
        0x85,
      ];

      expect(await textOf(bytes), '“Cita” — €5 …');
    });

    test('UTF-8 con un byte roto sigue siendo UTF-8', () async {
      // Un solo byte dañado no puede convertir el resto en "canciÃ³n": se
      // marca ese carácter y lo demás llega bien.
      expect(
        await textOf([
          ...utf8.encode('canción '),
          0xFF,
          ...utf8.encode(' más'),
        ]),
        'canción \uFFFD más',
      );
    });
  });

  group('sin recortar nada (F22)', () {
    test('los espacios y los saltos de los bordes se conservan', () async {
      expect(
        await textOf(utf8.encode('  Sangría inicial.\r\nFin.\r\n\r\n')),
        '  Sangría inicial.\r\nFin.\r\n\r\n',
      );
    });
  });

  group('titulo', () {
    test('de un Markdown sale su primer encabezado', () async {
      final result = await parser.parseBytes(
        Uint8List.fromList([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('\n# La idea buena\n\nY el desarrollo.'),
        ]),
      );

      expect(result.title, 'La idea buena');
    });

    test('un texto que no empieza con encabezado no tiene titulo', () async {
      final result = await parser.parseBytes(
        Uint8List.fromList(utf8.encode('Notas sueltas.\n# Mas abajo')),
      );

      expect(result.title, isNull);
    });
  });
}
