import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

/// Lee un libro en EPUB.
///
/// Un EPUB es un ZIP con XHTML adentro y un archivo que dice en qué orden se
/// leen: el OPF. Se lee con `archive` + `xml` y no con un paquete dedicado
/// porque los candidatos estaban abandonados —`epubx` lleva tres años sin
/// publicar— y este es el formato en el que alguien guarda su biblioteca; una
/// dependencia muerta en ese camino no es aceptable. Ver la decisión 3 en
/// `docs/arquitectura.md`.
///
/// **El orden de lectura sale del spine, no del ZIP.** Dentro del archivo los
/// capítulos pueden estar en cualquier orden, y sus nombres pueden ser
/// `id12.xhtml`, `part0004.html` o cualquier cosa. El spine es la lista
/// ordenada que el editor dejó escrita, y es lo único que garantiza que el
/// capítulo tres vaya después del dos.
///
/// Funciona igual con EPUB 2 y 3: el spine existe en los dos y con la misma
/// forma. Es justamente por eso que se usa ese y no el índice de navegación,
/// que sí cambió de formato entre versiones.
class EpubParser implements DocumentParser {
  const EpubParser({AppLogger? logger}) : _logger = logger;

  /// Dónde queda registrado un capítulo que el libro nombra y no trae
  /// (F22). `null` en las pruebas a las que no les interesa.
  final AppLogger? _logger;

  @override
  bool canParse(FileFormat format) => format == FileFormat.epub;

  // Ver el mismo cambio y el mismo motivo en `DocxParser.parse`: nada acá
  // adentro espera una E/S de verdad, así que un libro de miles de páginas
  // se procesa en otro isolate en vez de congelar la interfaz mientras
  // dura.
  @override
  Future<ParsedDocument> parse(
    DocumentSource source, {
    DocumentParseSession session = DocumentParseSession.detached,
  }) async {
    // Un ZIP se descomprime entero: se lee entero, fuera del hilo principal.
    final bytes = await source.readAll();
    final (document, missing) = await Isolate.run(() => _parse(bytes));

    // Un capítulo que falta no frena el libro —perderlo entero por una línea
    // sobrante del índice sería desproporcionado—, pero tampoco se saltea en
    // silencio: queda registrado, con su nombre, para saber que el texto
    // guardado no es el libro completo (F22). Se registra acá y no adentro
    // del isolate porque el registro de la app vive en este.
    for (final href in missing) {
      _logger?.warning(
        'El EPUB ${source.name} nombra el capítulo "$href" y no lo trae: '
        'se guardó el libro sin él.',
      );
    }

    return document;
  }

  (ParsedDocument, List<String>) _parse(Uint8List bytes) {
    final archive = _decode(bytes);

    final opfPath = _findOpfPath(archive);
    final opf = _parseXml(_requireEntry(archive, opfPath), opfPath).rootElement;

    // Las rutas del manifiesto son relativas al OPF, no a la raíz del ZIP.
    // Resolverlas contra la raíz es el error clásico y deja un libro sin un
    // solo capítulo, porque ninguna ruta encuentra su archivo.
    final base = p.url.dirname(opfPath);

    final (:chapters, :missing) = _readSpine(archive, opf, base);
    if (chapters.isEmpty) {
      throw const UnreadableDocumentException(
        FileFormat.epub,
        'no se encontró ningún capítulo',
      );
    }

    final metadata = _readMetadata(opf);

    return (
      ParsedDocument(
        markdown: chapters.join('\n\n---\n\n'),
        title: metadata.title,
        author: metadata.author,
        pageCount: chapters.length,
      ),
      missing,
    );
  }

  // -------------------------------------------------------------------
  // Dónde está el OPF
  // -------------------------------------------------------------------

  /// El OPF puede llamarse y estar donde el editor quiera.
  ///
  /// Lo único fijo en un EPUB es `META-INF/container.xml`, que dice dónde
  /// está. Dar por sentado `OEBPS/content.opf` —el nombre que usa la mayoría—
  /// funcionaría con casi todos los libros y fallaría en silencio con el
  /// resto.
  String _findOpfPath(Archive archive) {
    const containerPath = 'META-INF/container.xml';
    final container = _parseXml(
      _requireEntry(archive, containerPath),
      containerPath,
    );

    final rootfile = container.rootElement
        .findAllElements('rootfile')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .firstOrNull;

    if (rootfile == null || rootfile.isEmpty) {
      throw const UnreadableDocumentException(
        FileFormat.epub,
        'el contenedor no dice dónde está el OPF',
      );
    }

    return rootfile;
  }

  // -------------------------------------------------------------------
  // Capítulos
  // -------------------------------------------------------------------

  ({List<String> chapters, List<String> missing}) _readSpine(
    Archive archive,
    XmlElement opf,
    String base,
  ) {
    // El manifiesto asocia cada identificador con su archivo; el spine dice
    // en qué orden van esos identificadores.
    final hrefById = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) hrefById[id] = href;
    }

    final chapters = <String>[];
    // Un capítulo marcado como no lineal —notas al final, apéndices, un
    // glosario— no va en el hilo de lectura, pero es texto del libro: los
    // lectores lo muestran cuando se toca una nota. Antes se descartaba, y
    // con él las notas de libros enteros (F22). Va al final, después de lo
    // lineal, en el orden en que el spine los nombra: así no interrumpe la
    // lectura y tampoco se pierde.
    final auxiliary = <String>[];
    final missing = <String>[];
    for (final reference in opf.findAllElements('itemref')) {
      final idref = reference.getAttribute('idref');
      final href = hrefById[idref];
      if (href == null) {
        missing.add(idref ?? '(sin identificador)');
        continue;
      }

      final entry = _entryBytes(archive, _resolve(base, href));
      if (entry == null) {
        missing.add(href);
        continue;
      }

      final markdown = xhtmlToMarkdown(_decodeText(entry));
      if (markdown.trim().isEmpty) continue;
      if (reference.getAttribute('linear') == 'no') {
        auxiliary.add(markdown);
      } else {
        chapters.add(markdown);
      }
    }

    return (chapters: [...chapters, ...auxiliary], missing: missing);
  }

  /// Resuelve una ruta del manifiesto contra la carpeta del OPF.
  ///
  /// Las rutas vienen además con los caracteres especiales escapados, porque
  /// son URL: un capítulo llamado `El niño.xhtml` aparece como
  /// `El%20ni%C3%B1o.xhtml` y no encontraría su archivo sin desescaparlo.
  String _resolve(String base, String href) {
    final decoded = Uri.decodeComponent(href.split('#').first);
    return base.isEmpty ? decoded : p.url.normalize(p.url.join(base, decoded));
  }

  // -------------------------------------------------------------------
  // Metadatos
  // -------------------------------------------------------------------

  ({String? title, String? author}) _readMetadata(XmlElement opf) => (
    title: _nonEmpty(
      opf.findAllElements('title', namespace: _dc).firstOrNull?.innerText,
    ),
    author: _nonEmpty(
      opf.findAllElements('creator', namespace: _dc).firstOrNull?.innerText,
    ),
  );

  // -------------------------------------------------------------------
  // Utilidades
  // -------------------------------------------------------------------

  Archive _decode(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
      // `archive` lanza de varias formas según por dónde esté cortado el
      // archivo, y ninguna de ellas tiene un tipo propio.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      throw UnreadableDocumentException(FileFormat.epub, 'ZIP ilegible: $e');
    }
  }

  List<int>? _entryBytes(Archive archive, String name) =>
      archive.files.where((f) => f.name == name).firstOrNull?.readBytes();

  String _requireEntry(Archive archive, String name) {
    final bytes = _entryBytes(archive, name);
    if (bytes == null) {
      throw UnreadableDocumentException(FileFormat.epub, 'falta $name');
    }

    return _decodeText(bytes);
  }

  /// El texto de un archivo del libro.
  ///
  /// EPUB 3 exige UTF-8, pero EPUB 2 también admite UTF-16, que se reconoce
  /// por la marca con la que empieza el archivo. Leído como UTF-8, un
  /// capítulo en UTF-16 sale entero como caracteres rotos (F22). La marca de
  /// UTF-8, si está, se descarta: no es texto, y delante del XML hace que no
  /// se lo reconozca como XML.
  String _decodeText(List<int> bytes) {
    if (bytes.length >= 2) {
      final bigEndian = bytes[0] == 0xFE && bytes[1] == 0xFF;
      final littleEndian = bytes[0] == 0xFF && bytes[1] == 0xFE;
      if (bigEndian || littleEndian) {
        final units = <int>[
          for (var i = 2; i + 1 < bytes.length; i += 2)
            if (bigEndian)
              bytes[i] << 8 | bytes[i + 1]
            else
              bytes[i + 1] << 8 | bytes[i],
        ];
        return String.fromCharCodes(units);
      }
    }
    final hasUtf8Mark =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    return utf8.decode(
      hasUtf8Mark ? bytes.sublist(3) : bytes,
      allowMalformed: true,
    );
  }

  XmlDocument _parseXml(String source, String name) {
    try {
      return XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw UnreadableDocumentException(FileFormat.epub, '$name ilegible: $e');
    }
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// Dublin Core, el vocabulario de los metadatos.
const _dc = 'http://purl.org/dc/elements/1.1/';
