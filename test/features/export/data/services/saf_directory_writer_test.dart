import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/export/data/services/saf_directory_writer.dart';

/// Solo cubre `mimeTypeForFileName`: es la única lógica propia de
/// [SafDirectoryWriter], el resto es un llamado directo al plugin
/// `saf_stream`, que se prueba con un doble en las pruebas del caso de uso
/// que lo usa, no acá.
void main() {
  group('mimeTypeForFileName', () {
    test('un archivo .md es text/markdown', () {
      expect(mimeTypeForFileName('00-indice.md'), 'text/markdown');
    });

    test('un archivo .txt es text/plain', () {
      expect(mimeTypeForFileName('nota.txt'), 'text/plain');
    });

    test('un archivo .pdf es application/pdf', () {
      expect(mimeTypeForFileName('articulo.pdf'), 'application/pdf');
    });

    test('la extensión no distingue mayúsculas', () {
      expect(mimeTypeForFileName('NOTA.MD'), 'text/markdown');
    });

    test('un nombre sin extensión conocida cae en el tipo genérico', () {
      expect(
        mimeTypeForFileName('archivo.desconocido'),
        'application/octet-stream',
      );
    });

    test('un nombre sin ningún punto también cae en el tipo genérico', () {
      expect(mimeTypeForFileName('sinextension'), 'application/octet-stream');
    });

    test('un nombre con varios puntos usa la extensión, no lo de antes', () {
      expect(mimeTypeForFileName('Trémolo (electrónica).md'), 'text/markdown');
    });
  });
}
