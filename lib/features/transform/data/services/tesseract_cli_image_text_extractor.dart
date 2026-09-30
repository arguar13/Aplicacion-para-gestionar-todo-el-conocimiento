import 'dart:convert';
import 'dart:io';

import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// `ImageTextExtractor` sobre el Tesseract instalado en el sistema, para
/// escritorio —Windows, Linux, macOS—, donde Google ML Kit no tiene ninguna
/// versión nativa. Ver la decisión 15 en docs/arquitectura.md.
///
/// A diferencia de Android (ML Kit, empaquetado con la app) y la web
/// (Tesseract en WebAssembly, servido con los propios assets), acá no se
/// bundlea ningún motor: se asume una instalación de Tesseract en el
/// sistema, con `tesseract` alcanzable desde el `PATH`. Sumar un binario de
/// terceros al repositorio —o descargarlo en silencio— repetiría el problema
/// que la decisión 3 ya evitó con `syncfusion_flutter_pdf` y `ffmpeg_kit`:
/// una dependencia binaria sin una forma clara de fijar versión ni de
/// verificar que siga viva. Que falte no es un fallo distinto a un enlace
/// roto: [extractText] lanza [TesseractNotAvailableException], el elemento
/// queda marcado como fallido, y se reintenta con el mismo botón que
/// cualquier otra transformación.
class TesseractCliImageTextExtractor implements ImageTextExtractor {
  const TesseractCliImageTextExtractor({
    this.executable = 'tesseract',
    this.runProcess = _runForBytes,
  });

  final String executable;

  /// Inyectable para las pruebas: por defecto, `Process.run` sin decodificar
  /// la salida —la decodifica [extractText]—.
  final Future<ProcessResult> Function(String executable, List<String> args)
  runProcess;

  @override
  Future<String> extractText(String path) async {
    final ProcessResult result;
    try {
      result = await runProcess(executable, [path, 'stdout', '-l', 'spa+eng']);
    } on ProcessException catch (e) {
      throw TesseractNotAvailableException(e.message);
    }

    if (result.exitCode != 0) {
      throw TesseractNotAvailableException(_text(result.stderr));
    }

    return _withoutPageSeparators(_text(result.stdout));
  }

  /// Tesseract termina cada página con un salto de página (`\f`): es el
  /// separador del motor, no un carácter de la imagen (F22).
  ///
  /// El del final no separa nada y se quita. Los del medio —un TIFF de varias
  /// páginas— sí separan: cada uno pasa a ser un salto de párrafo, una línea
  /// en blanco entre página y página, que es como se separan los bloques en
  /// lo que la app guarda. Tesseract ya cierra cada página con su propio
  /// salto de línea; se completa solo lo que falta para la línea en blanco, y
  /// una página sin texto no deja un hueco. El texto de cada página no se
  /// toca.
  String _withoutPageSeparators(String text) {
    final pages = text.split('\f');
    // Lo que queda después del último `\f`: vacío cuando el motor cerró la
    // última página, como hace siempre.
    if (pages.length > 1 && pages.last.isEmpty) pages.removeLast();

    final withText = pages.where((page) => page.isNotEmpty).toList();
    if (withText.isEmpty) return '';

    final buffer = StringBuffer();
    for (final (i, page) in withText.indexed) {
      buffer.write(page);
      if (i == withText.length - 1) break;
      if (page.endsWith('\n\n')) continue;
      buffer.write(page.endsWith('\n') ? '\n' : '\n\n');
    }
    return buffer.toString();
  }
}

/// La salida de Tesseract es siempre UTF-8, sea cual sea el sistema.
///
/// `Process.run` la decodificaba con la codificación del sistema, que en
/// Windows es la ANSI del país: "canción" llegaba como "canciÃ³n" (F22).
/// Por eso se piden los bytes y se decodifican acá.
String _text(Object? output) => switch (output) {
  final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
  _ => '${output ?? ''}',
};

Future<ProcessResult> _runForBytes(String executable, List<String> args) =>
    Process.run(executable, args, stdoutEncoding: null, stderrEncoding: null);

/// El sistema no tiene Tesseract instalado, o la llamada falló por otra
/// razón —falta el idioma entrenado, el binario está roto—. Se distingue de
/// un texto vacío (una foto sin ninguna letra), que no es un error.
class TesseractNotAvailableException implements Exception {
  const TesseractNotAvailableException(this.message);

  final String message;

  @override
  String toString() => 'Tesseract no está disponible en el sistema: $message';
}
