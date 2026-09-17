import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

/// Lee un documento de Word.
///
/// Un `.docx` es un ZIP con XML adentro: el cuerpo está en
/// `word/document.xml` y los metadatos en `docProps/core.xml`. Por eso se lee
/// con `archive` + `xml` y no con un paquete dedicado — ver la decisión 3 en
/// `docs/arquitectura.md`.
///
/// Lo que se conserva es la **estructura**: encabezados, listas, tablas y
/// negritas. Un informe convertido a un muro de párrafos deja de ser un
/// informe, y el usuario que lo guardó lo guardó por lo que decía **y** por
/// cómo estaba organizado.
class DocxParser implements DocumentParser {
  const DocxParser();

  @override
  bool canParse(FileFormat format) => format == FileFormat.docx;

  // `Isolate.run` y no un método `async` con trabajo síncrono adentro: nada
  // de lo que hace `_parse` —descomprimir el ZIP, recorrer el XML, armar el
  // Markdown— espera nunca una E/S de verdad, así que sin esto un documento
  // de cientos de páginas congela la interfaz entera durante todo ese
  // tiempo, por más que la firma diga `Future`. Es seguro moverlo a otro
  // isolate porque `DocxParser` no tiene estado propio —es un `const` sin
  // campos— y todo lo que entra y sale (`Uint8List`, `ParsedDocument`, la
  // excepción de documento ilegible) son datos simples, transferibles entre
  // isolates sin depender de ningún canal de plataforma.
  @override
  Future<ParsedDocument> parse(Uint8List bytes) =>
      Isolate.run(() => _parse(bytes));

  ParsedDocument _parse(Uint8List bytes) {
    final archive = _decode(bytes);

    final documentXml = _textEntry(archive, 'word/document.xml');
    if (documentXml == null) {
      throw const UnreadableDocumentException(
        FileFormat.docx,
        'no trae word/document.xml',
      );
    }

    final body = _parseXml(
      documentXml,
    ).rootElement.getElement('body', namespace: _w);
    if (body == null) {
      throw const UnreadableDocumentException(
        FileFormat.docx,
        'el documento no tiene cuerpo',
      );
    }

    final metadata = _readMetadata(archive);

    return ParsedDocument(
      markdown: _blocksToMarkdown(body),
      title: metadata.title,
      author: metadata.author,
    );
  }

  // -------------------------------------------------------------------
  // Cuerpo
  // -------------------------------------------------------------------

  String _blocksToMarkdown(XmlElement body) {
    final blocks = <String>[];

    for (final node in body.childElements) {
      final block = switch (node.name.local) {
        'p' => _paragraphToMarkdown(node),
        'tbl' => _tableToMarkdown(node),
        _ => null,
      };

      if (block != null && block.trim().isNotEmpty) blocks.add(block);
    }

    return blocks.join('\n\n');
  }

  String? _paragraphToMarkdown(XmlElement paragraph) {
    final text = _runsToMarkdown(paragraph);
    if (text.trim().isEmpty) return null;

    final properties = paragraph.getElement('pPr', namespace: _w);

    final heading = _headingLevel(properties);
    if (heading != null) return '${'#' * heading} $text';

    final bullet = _listIndent(properties);
    if (bullet != null) return '${'  ' * bullet}- $text';

    return text;
  }

  /// Qué nivel de encabezado es este párrafo, o `null` si no lo es.
  ///
  /// Se miran dos cosas porque Word usa las dos y no siempre las mismas. El
  /// nombre del estilo es lo habitual (`Heading1`), pero **depende del idioma
  /// en que se creó el documento**: un Word en español escribe `Ttulo1`. El
  /// `outlineLvl` es numérico y no depende del idioma, así que sirve de
  /// respaldo para todo lo demás.
  int? _headingLevel(XmlElement? properties) {
    if (properties == null) return null;

    final styleId =
        properties
            .getElement('pStyle', namespace: _w)
            ?.getAttribute('val', namespace: _w) ??
        '';

    final byName = RegExp(
      r'^(?:heading|t.?tulo|titre|berschrift|titolo)\s*(\d)$',
      caseSensitive: false,
    ).firstMatch(styleId);
    if (byName != null) return int.parse(byName.group(1)!).clamp(1, 6);

    final outline = properties
        .getElement('outlineLvl', namespace: _w)
        ?.getAttribute('val', namespace: _w);
    final level = int.tryParse(outline ?? '');
    // `outlineLvl` cuenta desde cero: el 0 es un encabezado de nivel 1.
    return level == null ? null : (level + 1).clamp(1, 6);
  }

  /// La sangría del punto de lista, o `null` si el párrafo no es uno.
  int? _listIndent(XmlElement? properties) {
    final numbering = properties?.getElement('numPr', namespace: _w);
    if (numbering == null) return null;

    final level = numbering
        .getElement('ilvl', namespace: _w)
        ?.getAttribute('val', namespace: _w);
    return int.tryParse(level ?? '') ?? 0;
  }

  /// Junta el texto de un párrafo con sus negritas y cursivas.
  ///
  /// Word parte el texto en "runs" cada vez que cambia algún atributo, así
  /// que una sola frase puede venir en seis pedazos. Se emiten las marcas
  /// pegadas a cada pedazo y después se fusionan las adyacentes: sin eso, una
  /// frase entera en negrita saldría como `**Una** **frase** **entera**`, que
  /// se ve mal y además rompe el resaltado en algunos editores.
  String _runsToMarkdown(XmlElement paragraph) {
    final buffer = StringBuffer();

    for (final node in paragraph.descendantElements) {
      if (node.name.namespaceUri != _w) continue;

      switch (node.name.local) {
        case 't':
          buffer.write(_decorate(node.innerText, node.parentElement));
        case 'br':
          // Dos espacios y un salto: el salto de línea de Markdown que no
          // abre un párrafo nuevo.
          buffer.write('  \n');
        case 'tab':
          buffer.write('\t');
      }
    }

    return _mergeAdjacentMarks(buffer.toString()).trim();
  }

  String _decorate(String text, XmlElement? run) {
    if (text.isEmpty) return text;

    final properties = run?.getElement('rPr', namespace: _w);
    if (properties == null) return text;

    // Los espacios de los bordes van **afuera** de las marcas: `** texto **`
    // no es negrita en Markdown, es un asterisco literal.
    final leading = RegExp(r'^\s*').firstMatch(text)!.group(0)!;
    final trailing = RegExp(r'\s*$').firstMatch(text)!.group(0)!;
    final core = text.substring(leading.length, text.length - trailing.length);
    if (core.isEmpty) return text;

    var marked = core;
    if (_isEnabled(properties, 'i')) marked = '*$marked*';
    if (_isEnabled(properties, 'b')) marked = '**$marked**';

    return '$leading$marked$trailing';
  }

  /// Si un atributo booleano está puesto.
  ///
  /// En OOXML, `<w:b/>` significa activado y `<w:b w:val="0"/>` desactivado.
  /// Mirar solo si la etiqueta existe pondría en negrita el texto que el
  /// usuario **des**activó a mano.
  bool _isEnabled(XmlElement properties, String name) {
    final element = properties.getElement(name, namespace: _w);
    if (element == null) return false;

    final value = element.getAttribute('val', namespace: _w);
    return value == null || value == '1' || value == 'true' || value == 'on';
  }

  /// Fusiona las marcas de dos pedazos consecutivos con el mismo atributo.
  ///
  /// Word parte el texto cada vez que cambia algo —incluso una corrección
  /// ortográfica— así que una frase entera en negrita puede llegar en seis
  /// pedazos y salir como `**Una****frase****entera**`. El cierre pegado a la
  /// apertura siguiente se anula.
  String _mergeAdjacentMarks(String text) => text.replaceAll('****', '');

  // -------------------------------------------------------------------
  // Tablas
  // -------------------------------------------------------------------

  /// Convierte una tabla de Word a una tabla de Markdown.
  ///
  /// Las tablas son de lo que peor sobrevive a una conversión descuidada: un
  /// cuadro comparativo aplastado a texto corrido pierde exactamente la
  /// información por la que era un cuadro.
  String _tableToMarkdown(XmlElement table) {
    final rows = <List<String>>[];

    for (final row in table.findElements('tr', namespace: _w)) {
      final cells = <String>[];
      for (final cell in row.findElements('tc', namespace: _w)) {
        final paragraphs = cell
            .findElements('p', namespace: _w)
            .map(_runsToMarkdown)
            .where((text) => text.isNotEmpty);

        // Dentro de una celda no puede haber saltos de línea: partirían la
        // fila en dos. Se juntan con un espacio.
        cells.add(paragraphs.join(' ').replaceAll('|', r'\|'));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }

    if (rows.isEmpty) return '';

    final columns = rows
        .map((row) => row.length)
        .reduce((a, b) => a > b ? a : b);
    final lines = <String>[
      _row(rows.first, columns),
      // Markdown exige la línea separadora: sin ella no se ve como tabla.
      '| ${List.filled(columns, '---').join(' | ')} |',
      for (final row in rows.skip(1)) _row(row, columns),
    ];

    return lines.join('\n');
  }

  String _row(List<String> cells, int columns) {
    final padded = [...cells, ...List.filled(columns - cells.length, '')];
    return '| ${padded.join(' | ')} |';
  }

  // -------------------------------------------------------------------
  // Metadatos
  // -------------------------------------------------------------------

  ({String? title, String? author}) _readMetadata(Archive archive) {
    final xml = _textEntry(archive, 'docProps/core.xml');
    if (xml == null) return (title: null, author: null);

    try {
      final root = _parseXml(xml).rootElement;
      return (
        title: _nonEmpty(root.getElement('title', namespace: _dc)?.innerText),
        author: _nonEmpty(
          root.getElement('creator', namespace: _dc)?.innerText,
        ),
      );
      // Los metadatos son un extra: si vienen rotos, el documento se lee igual.
    } on XmlException {
      return (title: null, author: null);
    }
  }

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
      throw UnreadableDocumentException(FileFormat.docx, 'ZIP ilegible: $e');
    }
  }

  XmlDocument _parseXml(String source) {
    try {
      return XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw UnreadableDocumentException(FileFormat.docx, 'XML ilegible: $e');
    }
  }

  String? _textEntry(Archive archive, String name) {
    final file = archive.files.where((f) => f.name == name).firstOrNull;
    if (file == null) return null;

    // `utf8.decode` con `allowMalformed`: un byte suelto corrupto en medio de
    // un documento de cien páginas no puede costar las otras noventa y nueve.
    return utf8.decode(file.readBytes() ?? const [], allowMalformed: true);
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// El espacio de nombres del formato de Word. Se compara contra él en vez de
/// contra el prefijo `w:` porque el prefijo lo elige quien escribe el archivo
/// y puede ser cualquier otro.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Dublin Core, el vocabulario de los metadatos.
const _dc = 'http://purl.org/dc/elements/1.1/';
