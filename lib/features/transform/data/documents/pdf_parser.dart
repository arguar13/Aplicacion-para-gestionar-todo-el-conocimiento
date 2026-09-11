import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Saca el texto de un PDF.
///
/// Usa [`pdfrx`](https://pub.dev/packages/pdfrx), que es MIT y va sobre el
/// PDFium de Chromium — el mismo motor con el que Chrome muestra PDFs. Se
/// eligió en lugar de `syncfusion_flutter_pdf`, que el plan original
/// proponía: su licencia community es **propietaria** y solo permite el uso
/// gratuito por debajo de cierta facturación. Ver la decisión 3 en
/// `docs/arquitectura.md`.
///
/// **Solo extrae el texto que el PDF ya tiene.** Un PDF escaneado es un
/// álbum de fotos de páginas: no contiene ni una letra, y de ahí no sale
/// texto por mucho que se insista. Esos se reconocen porque salen vacíos, y
/// su contenido va a llegar cuando esté el reconocimiento óptico de la fase
/// 7. Mientras tanto el archivo queda guardado, que es lo que importa.
class PdfParser implements DocumentParser {
  const PdfParser({PdfEngineInitializer? initialize})
    : _initialize = initialize ?? pdfrxInitialize;

  /// Cómo se prepara el motor nativo.
  ///
  /// Se inyecta para poder apuntar a una copia concreta de PDFium en las
  /// pruebas. En la app es [pdfrxInitialize], que la resuelve sola.
  final PdfEngineInitializer _initialize;

  @override
  bool canParse(FileFormat format) => format == FileFormat.pdf;

  @override
  Future<ParsedDocument> parse(Uint8List bytes) async {
    await _initialize();

    final document = await _open(bytes);
    try {
      final pages = <String>[];
      for (final page in document.pages) {
        final text = (await page.loadText())?.fullText ?? '';
        final cleaned = cleanPdfPageText(text);
        if (cleaned.isNotEmpty) pages.add(cleaned);
      }

      return ParsedDocument(
        markdown: pages.join('\n\n---\n\n'),
        pageCount: document.pages.length,
      );
    } finally {
      // Sin esto se filtra memoria nativa, que el recolector de Dart no ve ni
      // puede liberar: leer cien PDFs dejaría cien documentos abiertos.
      await document.dispose();
    }
  }

  Future<PdfDocument> _open(Uint8List bytes) async {
    try {
      return await PdfDocument.openData(bytes);
      // PDFium informa sus fallos de varias formas —archivo corrupto, cifrado,
      // versión no soportada— y ninguna tiene un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      throw UnreadableDocumentException(FileFormat.pdf, '$e');
    }
  }
}

/// Deja el texto de una página de PDF en algo legible.
///
/// PDFium devuelve el texto tal como está puesto en la página, y una página
/// maquetada trae rarezas que no son parte de lo que el autor escribió:
///
/// - **Saltos de línea en medio de las frases**, porque el salto es del
///   ancho de la página y no del párrafo. Se unen: si no, el índice de
///   búsqueda guarda medias frases y buscar una expresión de cuatro palabras
///   no encuentra nada. Dos saltos seguidos sí marcan un párrafo nuevo y se
///   respetan.
/// - **Guiones de corte de palabra** al final del renglón: `cono-` y
///   `cimiento` se juntan en `conocimiento`, o la palabra queda partida en
///   dos mitades que no se encuentran nunca.
///
/// Lo segundo tiene un costo conocido y aceptado: una palabra compuesta que
/// caiga justo al final de un renglón —`teórico-práctico`— también se junta,
/// y pierde su guion. No hay forma de distinguirlas mirando el texto: las
/// dos son un guion al final de la línea. Se elige juntar porque los cortes
/// de palabra son muchísimo más frecuentes que un compuesto cayendo
/// exactamente ahí, y porque el daño es asimétrico: un compuesto sin guion
/// se sigue leyendo y se sigue encontrando, y una palabra partida en dos no.
/// Es lo mismo que hacen las herramientas clásicas de extracción.
///
/// El guion suave —el carácter invisible que algunos PDFs usan para marcar
/// justamente un corte— sí es inequívoco, y se trata igual.
///
/// Se expone para poder probarlo por su cuenta: es lo que decide si el texto
/// de un libro entero se puede buscar o no.
String cleanPdfPageText(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final unhyphenated = text.replaceAllMapped(
    RegExp(r'(\w)[-\u00AD]\n(\w)'),
    (m) => '${m[1]}${m[2]}',
  );

  final joined = unhyphenated.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), ' ');

  return joined
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .trim();
}

/// Prepara el motor nativo de PDF. Se inyecta para poder probarlo.
typedef PdfEngineInitializer = Future<void> Function();
