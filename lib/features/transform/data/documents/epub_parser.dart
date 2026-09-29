import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_format.dart';
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
  const EpubParser();

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
    return Isolate.run(() => _parse(bytes));
  }

  ParsedDocument _parse(Uint8List bytes) {
    final archive = _decode(bytes);

    final opfPath = _findOpfPath(archive);
    final opf = _parseXml(_requireEntry(archive, opfPath), opfPath).rootElement;

    // Las rutas del manifiesto son relativas al OPF, no a la raíz del ZIP.
    // Resolverlas contra la raíz es el error clásico y deja un libro sin un
    // solo capítulo, porque ninguna ruta encuentra su archivo.
    final base = p.url.dirname(opfPath);

    final chapters = _readSpine(archive, opf, base);
    if (chapters.isEmpty) {
      throw const UnreadableDocumentException(
        FileFormat.epub,
        'no se encontró ningún capítulo',
      );
    }

    final metadata = _readMetadata(opf);

    return ParsedDocument(
      markdown: chapters.join('\n\n---\n\n'),
      title: metadata.title,
      author: metadata.author,
      pageCount: chapters.length,
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

  List<String> _readSpine(Archive archive, XmlElement opf, String base) {
    // El manifiesto asocia cada identificador con su archivo; el spine dice
    // en qué orden van esos identificadores.
    final hrefById = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) hrefById[id] = href;
    }

    final chapters = <String>[];
    for (final reference in opf.findAllElements('itemref')) {
      final href = hrefById[reference.getAttribute('idref')];
      if (href == null) continue;

      // Un capítulo marcado como no lineal es material auxiliar —notas al
      // pie, publicidad de la editorial— que no forma parte del hilo de
      // lectura. Incluirlo mezclaría el texto del libro con el que no lo es.
      if (reference.getAttribute('linear') == 'no') continue;

      final entry = _entryBytes(archive, _resolve(base, href));
      if (entry == null) continue;

      final markdown = _htmlToMarkdown(
        utf8.decode(entry, allowMalformed: true),
      );
      if (markdown.trim().isNotEmpty) chapters.add(markdown);
    }

    return chapters;
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

  /// `headingStyle: 'atx'` por la misma razón que en el extractor de
  /// artículos: por defecto la librería escribe los encabezados de nivel 1 y
  /// 2 subrayados con `===` y `---`, y del 3 en adelante con almohadillas, de
  /// modo que un mismo libro sale con dos convenciones mezcladas.
  String _htmlToMarkdown(String html) =>
      html2md.convert(html, styleOptions: const {'headingStyle': 'atx'}).trim();

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

    return utf8.decode(bytes, allowMalformed: true);
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
