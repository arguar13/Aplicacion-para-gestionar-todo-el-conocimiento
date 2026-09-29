import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/pdf_metadata_reader.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// Saca el texto de un PDF.
///
/// Usa [`pdfrx`](https://pub.dev/packages/pdfrx), que es MIT y va sobre el
/// PDFium de Chromium — el mismo motor con el que Chrome muestra PDFs. Se
/// eligió en lugar de `syncfusion_flutter_pdf`, que el plan original
/// proponía: su licencia community es **propietaria** y solo permite el uso
/// gratuito por debajo de cierta facturación. Ver la decisión 3 en
/// `docs/arquitectura.md`.
///
/// **Primero, el texto que el PDF ya tiene.** Es instantáneo y exacto: se lee
/// página por página.
///
/// **Después, las páginas escaneadas** —las que no traen ni una letra: una
/// foto de la página—, siempre y automáticamente (F21, decisión A), si hay
/// con qué reconocerlas (`ocrExtractor`): cada una se renderiza como imagen y
/// se le pide el mismo reconocimiento óptico que ya usa `ImageTransformer`
/// para una foto suelta —Google ML Kit en Android, Tesseract en la web y en
/// escritorio—. Es trabajo largo: pasa al carril largo de la cola, avisa el
/// avance página por página y guarda cada página reconocida, así que un
/// libro de cientos de páginas escaneadas que se interrumpe sigue desde
/// donde quedó. Las páginas con texto propio no se tocan: mezclarles lo que
/// reconoce un OCR —que siempre tiene algún error— degradaría lo único que
/// ya se sabe exacto. Una página en blanco de verdad tampoco se manda a
/// reconocer.
///
/// Sin `ocrExtractor` —o si el reconocimiento no encuentra nada— las páginas
/// escaneadas quedan vacías en vez de fallar: el archivo original queda
/// guardado, que es lo que importa.
class PdfParser implements DocumentParser {
  const PdfParser({
    PdfEngineInitializer? initialize,
    ImageTextExtractor? ocrExtractor,
    FileStore? ocrFileStore,
  }) : _initialize = initialize ?? pdfrxFlutterInitialize,
       _ocrExtractor = ocrExtractor,
       _ocrFileStore = ocrFileStore;

  /// Cómo se prepara el motor nativo.
  ///
  /// Se inyecta para poder apuntar a una copia concreta de PDFium en las
  /// pruebas. En la app es [pdfrxFlutterInitialize] y no [pdfrxInitialize]:
  /// la segunda es la versión pensada para un programa de Dart de escritorio
  /// sin Flutter, y para encontrar dónde cachear resuelve el directorio con
  /// `Platform.environment['HOME']` —que en Android y iOS no existe—, así
  /// que revienta con un null-check antes incluso de abrir el archivo, en
  /// cualquier PDF, sin que el archivo tenga nada de malo. La versión de
  /// Flutter resuelve ese directorio con `path_provider`, que sí funciona en
  /// todas las plataformas que soporta la app.
  final PdfEngineInitializer _initialize;

  /// El reconocimiento óptico para el respaldo de páginas escaneadas. `null`
  /// en las pruebas que no lo necesitan: un PDF sin texto sale vacío como
  /// siempre, en vez de reventar por no tener con qué reconocer nada.
  final ImageTextExtractor? _ocrExtractor;

  /// Dónde escribir, de paso, la imagen renderizada de cada página que se
  /// manda a reconocer. [ImageTextExtractor.extractText] pide una ruta, no
  /// bytes —lo mismo que ya resuelve `ImageTransformer` para una foto real—,
  /// así que hace falta un lugar donde esa imagen exista, aunque sea un
  /// instante.
  final FileStore? _ocrFileStore;

  /// A cuánto se renderiza cada página para el OCR, relativo a su tamaño a
  /// 72 dpi. Los 72 dpi nativos son ilegibles para un motor de
  /// reconocimiento; 2.5x (180 dpi aprox.) es el punto donde Tesseract y ML
  /// Kit reconocen bien un documento escaneado típico sin generar una
  /// imagen tan pesada que la vuelva lenta página por página.
  static const _ocrRenderScale = 2.5;

  @override
  bool canParse(FileFormat format) => format == FileFormat.pdf;

  @override
  Future<ParsedDocument> parse(
    DocumentSource source, {
    DocumentParseSession session = DocumentParseSession.detached,
  }) async {
    await _initialize();

    final document = await _open(source);
    try {
      // Cada página ocupa su lugar aunque esté en blanco: el segmento número
      // N del texto es la página N. Descartar las vacías corría todas las
      // siguientes, y con ellas el número de página que un resultado de
      // búsqueda cita (ver `ChunkingService`).
      final pages = <String>[];
      for (final page in document.pages) {
        session.context.throwIfCancelled();
        final text = (await page.loadText())?.fullText ?? '';
        pages.add(cleanPdfPageText(text));
      }

      final scanned = [
        for (var i = 0; i < pages.length; i++)
          if (pages[i].isEmpty) i,
      ];
      if (scanned.isNotEmpty) {
        await _recognizeScanned(document, pages, scanned, session);
      }

      // El título y el autor, si el PDF los trae en su diccionario `Info` o
      // en su paquete XMP —ver `readPdfMetadata`—. El resto de lo que esa
      // lectura encuentra —DOI, revista, volumen— no cabe acá: sale como
      // sugerencia de referencia (F15), no como algo que se escribe solo.
      // Por tramos: un libro escaneado de cientos de megas no pasa entero por
      // memoria para leerle el título (F21).
      final metadata = await readPdfMetadataFrom(
        size: source.size,
        readRange: source.readRange,
      );

      // Un documento sin una sola letra sale vacío, no como una fila de
      // separadores.
      return ParsedDocument(
        markdown: pages.every((page) => page.isEmpty)
            ? ''
            : pages.join('\n\n---\n\n'),
        title: metadata.title,
        author: _authorLine(metadata.reference.contributors),
        pageCount: document.pages.length,
      );
    } finally {
      // Sin esto se filtra memoria nativa, que el recolector de Dart no ve ni
      // puede liberar: leer cien PDFs dejaría cien documentos abiertos.
      await document.dispose();
    }
  }

  /// Reconoce las páginas [scanned] de [document] y deja su texto en
  /// [pages], en el carril largo, página por página: avisa el avance, guarda
  /// cada una y saltea las que ya se reconocieron en un intento anterior.
  Future<void> _recognizeScanned(
    PdfDocument document,
    List<String> pages,
    List<int> scanned,
    DocumentParseSession session,
  ) async {
    final extractor = _ocrExtractor;
    final files = _ocrFileStore;
    if (extractor == null || files == null) return;

    final context = session.context;
    await context.enterLongLane();

    final already = await session.recognizedPages();
    var done = 0;
    context.reportProgress(done, scanned.length);

    for (final index in scanned) {
      context.throwIfCancelled();

      var text = already[index];
      if (text == null) {
        text = await _recognizePage(document.pages[index], files, extractor);
        await session.saveRecognizedPage(index, text);
      }
      pages[index] = text;

      done++;
      context.reportProgress(done, scanned.length);
    }
  }

  /// El texto reconocido de [page], limpio, o vacío si está en blanco o si
  /// no se pudo reconocer.
  Future<String> _recognizePage(
    PdfPage page,
    FileStore files,
    ImageTextExtractor extractor,
  ) async {
    try {
      if (await _looksBlank(page)) return '';
      return cleanPdfPageText(await _ocrPage(page, files, extractor));
      // Una página que no se pudo renderizar o reconocer no tira abajo el
      // resto del documento: queda vacía y se sigue con la próxima. Ninguna
      // de las dos fallas tiene un tipo propio en Dart —vienen de PDFium y de
      // un motor de OCR de terceros—.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return '';
    }
  }

  /// Si [page] está en blanco: se la renderiza chiquita —un instante— y se
  /// mira si hay algo que no sea casi blanco. Un libro con texto propio y
  /// una docena de páginas en blanco no tiene por qué pasar al carril largo a
  /// reconocer papel vacío.
  Future<bool> _looksBlank(PdfPage page) async {
    final scale = _blankProbeWidth / page.width;
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null) return true;
    try {
      final pixels = rendered.pixels;
      for (var i = 0; i + 2 < pixels.length; i += 4) {
        if (pixels[i] < _inkThreshold ||
            pixels[i + 1] < _inkThreshold ||
            pixels[i + 2] < _inkThreshold) {
          return false;
        }
      }
      return true;
    } finally {
      rendered.dispose();
    }
  }

  Future<String> _ocrPage(
    PdfPage page,
    FileStore files,
    ImageTextExtractor extractor,
  ) async {
    final rendered = await page.render(
      fullWidth: page.width * _ocrRenderScale,
      fullHeight: page.height * _ocrRenderScale,
    );
    if (rendered == null) return '';

    final Uint8List png;
    try {
      png = await _encodePng(
        rendered.pixels,
        width: rendered.width,
        height: rendered.height,
      );
    } finally {
      rendered.dispose();
    }

    final tempPath = await files.save(
      bytes: png,
      suggestedName: 'pagina-${page.pageNumber}.png',
      id: 'ocr-pdf-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      final extractorPath = kIsWeb ? tempPath : await files.resolve(tempPath);
      return await extractor.extractText(extractorPath);
    } finally {
      await files.delete(tempPath);
    }
  }

  Future<PdfDocument> _open(DocumentSource source) async {
    try {
      // Desde el disco, si está en uno: PDFium lee solo las partes que
      // necesita, y un libro de cientos de páginas no pasa entero por la
      // memoria de Dart —ni se copia a la nativa— para sacarle el texto
      // (F21).
      final localPath = source.localPath;
      if (localPath != null) return await PdfDocument.openFile(localPath);

      // En la web no hay ruta: se abre desde los bytes.
      final bytes = await source.readAll();
      return await PdfDocument.openData(
        bytes,
        // Por debajo de este tamaño, `pdfrx_engine` copia los bytes a
        // memoria nativa de una vez (`FPDF_LoadMemDocument`) — el mismo
        // camino, simple y bien probado, que usa para abrir un archivo del
        // disco. Por encima, en cambio, pasa a leer por bloques a través de
        // un callback de Dart hacia el código nativo
        // (`FPDF_LoadCustomDocument`), un camino mucho más nuevo y más
        // frágil: ahí es donde fallan PDFs que PDFium abre sin problema por
        // cualquier otra vía, sin que el archivo tenga nada de malo. Como
        // los bytes ya están enteros acá, no hay ningún ahorro de memoria
        // real en evitar la copia; subir el umbral bien por encima de lo que
        // pesa un documento típico es forzar el camino robusto sin costo. Se
        // deja un techo (64 MB) para no intentarlo con un archivo
        // verdaderamente enorme, donde sí importa no duplicarlo en memoria
        // nativa de una sola vez.
        maxSizeToCacheOnMemory: bytes.length <= _maxDirectLoadBytes
            ? bytes.length
            : null,
      );
      // PDFium informa sus fallos de varias formas —archivo corrupto, cifrado,
      // versión no soportada— y ninguna tiene un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      throw UnreadableDocumentException(FileFormat.pdf, '$e');
    }
  }
}

/// Hasta acá, se fuerza la carga directa a memoria nativa en vez del camino
/// de lectura por bloques (ver [PdfParser._open]). 64 MB cubre con margen
/// cualquier PDF de texto o escaneado a resolución normal — un libro de
/// varios cientos de páginas escaneadas ronda las decenas de MB, no el
/// centenar—, así que el camino frágil queda reservado para el caso
/// verdaderamente atípico.
const _maxDirectLoadBytes = 64 * 1024 * 1024;

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

/// Los autores que `readPdfMetadata` encontró, como un único texto —«Gabriel
/// García Márquez; Jane Doe»—: lo que trae `ParsedDocument.author`, igual que
/// ya lo devuelven el EPUB y el DOCX. Vacío si no encontró a nadie.
String? _authorLine(List<Contributor> contributors) {
  if (contributors.isEmpty) return null;
  return contributors.map((c) => c.name.displayName).join('; ');
}

/// Prepara el motor nativo de PDF. Se inyecta para poder probarlo.
typedef PdfEngineInitializer = Future<void> Function();

/// Hasta qué ancho se renderiza una página para ver si está en blanco.
const _blankProbeWidth = 64.0;

/// Un canal por debajo de esto es tinta, no papel: deja pasar el gris muy
/// claro de un escaneo "en blanco" y el ruido del papel.
const _inkThreshold = 200;

/// La imagen BGRA de una página, como PNG, **fuera del hilo principal**: una
/// página a 180 dpi son unos 12 MB de píxeles, y comprimirlos en Dart puro
/// en el hilo de la interfaz la trababa página tras página (F21). En la web
/// no hay isolates: se comprime ahí mismo.
///
/// Compresión mínima: el PNG vive un instante —lo lee el reconocimiento y se
/// borra—, y comprimir más cuesta tiempo sin ahorrar nada que importe.
Future<Uint8List> _encodePng(
  Uint8List bgra, {
  required int width,
  required int height,
}) async {
  Uint8List encode(Uint8List pixels) => img.encodePng(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    ),
    level: 1,
  );

  if (kIsWeb) return encode(bgra);

  final transferable = TransferableTypedData.fromList([bgra]);
  return Isolate.run(() => encode(transferable.materialize().asUint8List()));
}
