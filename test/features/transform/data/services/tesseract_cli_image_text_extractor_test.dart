import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/tesseract_cli_image_text_extractor.dart';

void main() {
  /// Un Tesseract falso que responde con estos bytes, como el de verdad.
  TesseractCliImageTextExtractor tesseract(
    List<int> stdout, {
    int exitCode = 0,
    List<int> stderr = const [],
    List<List<String>>? calls,
  }) => TesseractCliImageTextExtractor(
    runProcess: (executable, args) async {
      calls?.add([executable, ...args]);
      return ProcessResult(1, exitCode, stdout, stderr);
    },
  );

  test('pide el texto de la imagen en espanol e ingles', () async {
    final calls = <List<String>>[];

    await tesseract(
      utf8.encode('x'),
      calls: calls,
    ).extractText('C:/fotos/pagina.png');

    expect(calls, [
      ['tesseract', 'C:/fotos/pagina.png', 'stdout', '-l', 'spa+eng'],
    ]);
  });

  test('la salida se lee como UTF-8, sea cual sea el sistema (F22)', () async {
    // En Windows, `Process.run` la decodificaba con la codificacion ANSI y
    // "cancion" con tilde llegaba como "canciÃ³n".
    final text = await tesseract(
      utf8.encode('Canción del año\n'),
    ).extractText('foto.png');

    expect(text, 'Canción del año\n');
  });

  test('se quita solo el salto de pagina final del motor (F22)', () async {
    // Tesseract cierra cada pagina con `\f`: es su separador, no un
    // caracter de la imagen. Uno que este en medio no se toca.
    final text = await tesseract(
      utf8.encode('Primera\n\fSegunda\n\f'),
    ).extractText('foto.tif');

    expect(text, 'Primera\n\fSegunda\n');
  });

  test('un fallo del motor avisa con su mensaje, en UTF-8', () async {
    final extractor = tesseract(
      const [],
      exitCode: 1,
      stderr: utf8.encode('Falta el idioma «spa»'),
    );

    expect(
      () => extractor.extractText('foto.png'),
      throwsA(
        isA<TesseractNotAvailableException>().having(
          (e) => e.message,
          'message',
          'Falta el idioma «spa»',
        ),
      ),
    );
  });

  test('sin Tesseract instalado lanza la excepcion propia', () async {
    final extractor = TesseractCliImageTextExtractor(
      runProcess: (executable, args) =>
          throw const ProcessException('tesseract', [], 'no encontrado'),
    );

    expect(
      () => extractor.extractText('foto.png'),
      throwsA(isA<TesseractNotAvailableException>()),
    );
  });
}
