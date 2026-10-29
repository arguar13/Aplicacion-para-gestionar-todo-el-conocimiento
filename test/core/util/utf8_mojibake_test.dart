import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/utf8_mojibake.dart';

/// [text] en UTF-8 leído como Latin-1: lo que hacía la app con el título.
String broken(String text) => latin1.decode(utf8.encode(text));

void main() {
  const title =
      'Declaración de los Derechos del Hombre y del Ciudadano de 1789';

  test('el caso de la captura: «DeclaraciÃ³n» vuelve a ser «Declaración»', () {
    expect(broken(title), startsWith('DeclaraciÃ³n'));
    expect(repairUtf8Mojibake(broken(title)), title);
  });

  test('las letras de dos, tres y cuatro bytes', () {
    const text = 'Ñandú — «canción» 1–2 € 🎵';
    expect(repairUtf8Mojibake(broken(text)), text);
  });

  test('lo leído mal dos veces se deshace entero', () {
    expect(repairUtf8Mojibake(broken(broken(title))), title);
  });

  group('no toca lo que no es eso', () {
    for (final text in [
      title,
      'Año, señor, pingüino',
      'Plain ASCII title',
      '',
      // Tiene la firma, pero no es UTF-8 válido: la última «Ã» abre una
      // letra que no sigue.
      'DeclaraciÃ³n y Ã',
      // Una letra que no cabe en un byte: no salió de leer bytes de a uno.
      'DeclaraciÃ³n — ✓',
      // Daría un carácter de control.
      'Â\u0085',
    ]) {
      test('«$text»', () {
        expect(repairUtf8Mojibake(text), isNull);
        expect(withUtf8MojibakeRepaired(text), text);
      });
    }
  });

  test('aplicarlo a lo ya arreglado no hace nada', () {
    final once = withUtf8MojibakeRepaired(broken(title));
    expect(withUtf8MojibakeRepaired(once), once);
    expect(repairUtf8Mojibake(once), isNull);
  });

  test('la firma', () {
    expect(hasUtf8MojibakeSignature(broken(title)), isTrue);
    expect(hasUtf8MojibakeSignature(title), isFalse);
  });
}
