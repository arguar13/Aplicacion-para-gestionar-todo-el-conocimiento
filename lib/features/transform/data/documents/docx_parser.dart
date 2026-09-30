import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/clients/html_text_decoder.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:xml/xml.dart';

/// Lee un documento de Word.
///
/// Un `.docx` es un ZIP con XML adentro: el cuerpo suele estar en
/// `word/document.xml` y los metadatos en `docProps/core.xml`. Por eso se lee
/// con `archive` + `xml` y no con un paquete dedicado — ver la decisión 3 en
/// `docs/arquitectura.md`.
///
/// Lo que se conserva es la **estructura**: encabezados, listas, tablas y
/// negritas. Un informe convertido a un muro de párrafos deja de ser un
/// informe, y el usuario que lo guardó lo guardó por lo que decía **y** por
/// cómo estaba organizado.
///
/// Y, antes que la estructura, **el texto, carácter por carácter** (F22): el
/// marcado de Markdown —`#`, `-`, `**`, `|`— se agrega alrededor del texto,
/// nunca a costa de él. Lo que Word muestra y no vive en el cuerpo también
/// se guarda, con una forma fija:
///
/// - **Encabezados y pies de página**, una sola vez cada texto distinto —no
///   uno por sección—: los encabezados arriba del cuerpo y los pies abajo,
///   separados por `---` para que no se lean como un párrafo más.
/// - **Notas al pie, notas finales y comentarios**, con la sintaxis de notas
///   de Markdown: la marca en el lugar (`[^1]` las notas al pie, `[^i]` las
///   finales —la numeración que Word les da de fábrica— y `[^c1]` los
///   comentarios) y el texto al final (`[^1]: …`), en el orden en que
///   aparecen. El comentario lleva su autor adelante, entre paréntesis.
/// - **Numeración real**: "1.", "a)", "3.2.1", calculada con `numbering.xml`
///   como la calcula Word; solo las viñetas pasan a `- `.
/// - **Ecuaciones** en notación lineal (ver [_MathWriter]), **SmartArt** y
///   **gráficos** con su texto como un bloque en su lugar, y los fragmentos
///   incrustados (`w:altChunk`) de HTML, texto o Word, convertidos.
class DocxParser implements DocumentParser {
  const DocxParser({AppLogger? logger}) : _logger = logger;

  /// Dónde queda registrado lo que el documento trae y no se pudo leer —una
  /// parte dañada, un fragmento incrustado en un formato desconocido— (F22).
  /// `null` en las pruebas a las que no les interesa.
  final AppLogger? _logger;

  @override
  bool canParse(FileFormat format) => format == FileFormat.docx;

  // `Isolate.run` y no un método `async` con trabajo síncrono adentro: nada
  // de lo que hace `_parseDocx` —descomprimir el ZIP, recorrer el XML, armar
  // el Markdown— espera nunca una E/S de verdad, así que sin esto un
  // documento de cientos de páginas congela la interfaz entera durante todo
  // ese tiempo, por más que la firma diga `Future`. Lo que corre en el otro
  // isolate es una función suelta que recibe solo los bytes: el registro de
  // la app no viaja, y lo que haya que registrar vuelve como texto.
  @override
  Future<ParsedDocument> parse(
    DocumentSource source, {
    DocumentParseSession session = DocumentParseSession.detached,
  }) async {
    // Un ZIP se descomprime entero: se lee entero, fuera del hilo principal.
    final bytes = await source.readAll();
    final (:document, :warnings) = await Isolate.run(() => _parseDocx(bytes));

    // Lo que no se pudo leer no frena el documento, pero tampoco se saltea
    // en silencio: queda registrado para saber que el texto guardado no es
    // el documento completo (F22).
    for (final warning in warnings) {
      _logger?.warning('El DOCX ${source.name} $warning');
    }
    return document;
  }
}

/// Cuántos documentos de Word incrustados uno dentro de otro se leen. Un
/// documento que se incrusta a sí mismo no puede colgar la lectura.
const _maxNesting = 4;

({ParsedDocument document, List<String> warnings}) _parseDocx(
  Uint8List bytes, {
  int depth = 0,
}) {
  final package = _Package(_decode(bytes));

  // El cuerpo es la parte que la relación `officeDocument` del paquete
  // nombra, no un nombre fijo (F22): casi siempre es `word/document.xml`,
  // pero un programa que no es Word puede llamarlo de otra forma. El nombre
  // de siempre queda de respaldo, para un paquete sin relaciones.
  final documentPart =
      package
          .relationships('')
          .byType('officeDocument')
          .where(package.has)
          .firstOrNull ??
      'word/document.xml';

  final documentBytes = package.bytes(documentPart, required: true);
  if (documentBytes == null) {
    throw UnreadableDocumentException(FileFormat.docx, 'no trae $documentPart');
  }

  final body = _parseXml(
    utf8.decode(documentBytes, allowMalformed: true),
  ).rootElement.getElement('body', namespace: _w);
  if (body == null) {
    throw const UnreadableDocumentException(
      FileFormat.docx,
      'el documento no tiene cuerpo',
    );
  }

  final metadata = _readMetadata(package);
  final markdown = _DocxReader(
    package,
    documentPart,
    body,
    depth: depth,
  ).toMarkdown();

  return (
    document: ParsedDocument(
      markdown: markdown,
      title: metadata.title,
      author: metadata.author,
    ),
    warnings: package.warnings,
  );
}

// ---------------------------------------------------------------------
// Metadatos
// ---------------------------------------------------------------------

({String? title, String? author}) _readMetadata(_Package package) {
  final part =
      package
          .relationships('')
          .byType('core-properties')
          .where(package.has)
          .firstOrNull ??
      'docProps/core.xml';
  final root = package.optionalXml(part);
  if (root == null) return (title: null, author: null);

  return (
    title: _nonEmpty(root.getElement('title', namespace: _dc)?.innerText),
    author: _nonEmpty(root.getElement('creator', namespace: _dc)?.innerText),
  );
}

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

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

// ---------------------------------------------------------------------
// El paquete: partes, relaciones y tipos
// ---------------------------------------------------------------------

/// El ZIP de un documento, con sus partes por nombre y sus relaciones.
///
/// Las partes se buscan **por las relaciones**, como las busca Word, y no
/// por nombres fijos (F22): la numeración, los estilos, las notas, los
/// encabezados, los gráficos son lo que la relación del tipo que
/// corresponde dice que son.
class _Package {
  _Package(Archive archive)
    : _files = {
        for (final file in archive.files)
          if (file.isFile) _key(file.name): file,
      };

  final Map<String, ArchiveFile> _files;
  final _relationships = <String, _Relationships>{};
  final _xml = <String, XmlElement?>{};
  Map<String, String>? _contentTypes;

  /// Lo que no se pudo leer, para registrarlo afuera del isolate.
  final warnings = <String>[];

  /// Los nombres de las partes no distinguen mayúsculas (así lo dice el
  /// formato del paquete), y una relación puede nombrar `Word/Media` lo que
  /// el ZIP guarda como `word/media`.
  static String _key(String name) => name.toLowerCase();

  bool has(String name) => _files.containsKey(_key(name));

  /// Los bytes de la parte [name], o `null` si no está.
  ///
  /// Una parte dañada —un CRC que no coincide, un bloque comprimido roto—
  /// hace lanzar a `archive` (F22). Si es una parte opcional —estilos,
  /// numeración, notas, un encabezado— se lee el documento sin ella y queda
  /// registrado; si es [required], el documento es ilegible.
  Uint8List? bytes(String name, {bool required = false}) {
    final file = _files[_key(name)];
    if (file == null) return null;
    try {
      return file.readBytes() ?? Uint8List(0);
      // Igual que al abrir el ZIP: `archive` lanza sin un tipo propio.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (required) {
        throw UnreadableDocumentException(
          FileFormat.docx,
          'la parte $name está dañada: $e',
        );
      }
      warnings.add('trae la parte $name dañada ($e): se leyó sin ella.');
      return null;
    }
  }

  /// La raíz de una parte que puede faltar o venir rota —metadatos, estilos,
  /// notas, encabezados—: el documento se lee igual sin ella.
  XmlElement? optionalXml(String name) => _xml.putIfAbsent(_key(name), () {
    final data = bytes(name);
    if (data == null) return null;
    try {
      // `allowMalformed`: un byte suelto corrupto en medio de un documento
      // de cien páginas no puede costar las otras noventa y nueve.
      return XmlDocument.parse(
        utf8.decode(data, allowMalformed: true),
      ).rootElement;
    } on XmlException catch (e) {
      warnings.add('trae la parte $name ilegible ($e): se leyó sin ella.');
      return null;
    }
  });

  /// Las relaciones de la parte [part]; las del paquete con `''`.
  _Relationships relationships(String part) =>
      _relationships.putIfAbsent(_key(part), () {
        final folder = p.url.dirname(part) == '.' ? '' : p.url.dirname(part);
        final name = part.isEmpty ? '' : p.url.basename(part);
        final relsPath = p.url.join(folder, '_rels', '$name.rels');
        return _Relationships.parse(optionalXml(relsPath), folder);
      });

  /// El tipo de contenido de una parte, como lo declara
  /// `[Content_Types].xml`: por su nombre, o por su extensión.
  String? contentType(String part) {
    final types = _contentTypes ??= _readContentTypes();
    return types['/${_key(part)}'] ??
        types[p.url.extension(part).replaceFirst('.', '').toLowerCase()];
  }

  Map<String, String> _readContentTypes() {
    final root = optionalXml('[Content_Types].xml');
    if (root == null) return const {};
    return {
      for (final element in root.childElements)
        if (element.getAttribute('ContentType') case final type?)
          if (element.getAttribute('PartName') case final name?)
            '/${_key(name.startsWith('/') ? name.substring(1) : name)}': type
          else if (element.getAttribute('Extension') case final extension?)
            extension.toLowerCase(): type,
    };
  }
}

/// Las relaciones de una parte: a qué parte apunta cada `r:id`, y de qué
/// tipo es.
class _Relationships {
  const _Relationships(this._targets);

  factory _Relationships.parse(XmlElement? rels, String folder) {
    if (rels == null) return const _Relationships({});
    return _Relationships({
      for (final relation in rels.findElements('Relationship', namespace: _rel))
        if (relation.getAttribute('TargetMode') != 'External')
          if (relation.getAttribute('Id') case final id?)
            if (relation.getAttribute('Target') case final target?)
              id: (
                // El tipo es una dirección larga; lo que distingue uno de
                // otro es el último tramo (`header`, `numbering`, `chart`),
                // igual en la versión transicional y en la estricta.
                type: (relation.getAttribute('Type') ?? '').split('/').last,
                target: _resolve(folder, target),
              ),
    });
  }

  final Map<String, ({String type, String target})> _targets;

  /// La parte a la que apunta la relación [id].
  String? target(String? id) => id == null ? null : _targets[id]?.target;

  /// Las partes a las que apuntan las relaciones del tipo [type].
  Iterable<String> byType(String type) => _targets.values
      .where((relation) => relation.type == type)
      .map((relation) => relation.target);

  /// Un destino relativo a la carpeta de la parte, o absoluto desde la raíz
  /// del paquete si empieza con `/`.
  static String _resolve(String folder, String target) {
    // Un destino puede venir con escapes (`%20`). Se deshacen a mano, y no
    // con `Uri.decodeFull`, que lanza ante un `%` suelto.
    final decoded = target.contains('%')
        ? utf8.decode(_percentDecoded(target), allowMalformed: true)
        : target;
    if (decoded.startsWith('/')) return p.url.normalize(decoded.substring(1));
    return p.url.normalize(p.url.join(folder, decoded));
  }

  static List<int> _percentDecoded(String text) {
    final bytes = <int>[];
    final units = utf8.encode(text);
    for (var i = 0; i < units.length; i++) {
      final escaped = units[i] == 0x25 && i + 2 < units.length
          ? int.tryParse(
              String.fromCharCodes(units.sublist(i + 1, i + 3)),
              radix: 16,
            )
          : null;
      if (escaped == null) {
        bytes.add(units[i]);
      } else {
        bytes.add(escaped);
        i += 2;
      }
    }
    return bytes;
  }
}

/// Recorre un documento ya abierto y arma su Markdown.
///
/// Es un objeto por lectura, y no funciones sueltas, porque la numeración,
/// las notas y los campos son **estado del documento entero**: el "3." de
/// una lista depende de los dos párrafos numerados anteriores, estén donde
/// estén; la nota `[^4]` es la cuarta que apareció, y un índice (un campo
/// TOC) empieza en un párrafo y termina muchos párrafos después.
class _DocxReader {
  _DocxReader(this._package, this._documentPart, this._body, {int depth = 0})
    : _depth = depth,
      _documentRels = _package.relationships(_documentPart),
      _rels = _package.relationships(_documentPart) {
    String part(String type) =>
        _documentRels.byType(type).where(_package.has).firstOrNull ??
        // El nombre de siempre, junto al cuerpo, para un documento sin
        // relaciones.
        p.url.join(p.url.dirname(_documentPart), '$type.xml');

    _numbering = _Numbering(
      _package.optionalXml(part('numbering')),
      _package.optionalXml(part('styles')),
    );
    _footnotes = _Notes(
      part('footnotes'),
      _package.optionalXml(part('footnotes')),
      'footnote',
      (n) => '$n',
    );
    _endnotes = _Notes(
      part('endnotes'),
      _package.optionalXml(part('endnotes')),
      'endnote',
      (n) => _roman(n).toLowerCase(),
    );
    _comments = _Notes(
      part('comments'),
      _package.optionalXml(part('comments')),
      'comment',
      (n) => 'c$n',
    );
    _settings = _package.optionalXml(part('settings'));
  }

  final _Package _package;
  final String _documentPart;
  final XmlElement _body;
  final int _depth;
  final _Relationships _documentRels;
  late final _Numbering _numbering;
  late final _Notes _footnotes;
  late final _Notes _endnotes;
  late final _Notes _comments;
  late final XmlElement? _settings;

  /// Las relaciones de la parte que se está leyendo: las del cuerpo, las de
  /// un encabezado, las de las notas. Un gráfico o un SmartArt se nombran
  /// con un `r:id` de la parte en la que están.
  _Relationships _rels;

  /// Los campos abiertos en el texto que se está leyendo, del más externo al
  /// más interno (ver [_run]).
  List<_Field> _fields = [];

  /// Las marcas de campo sin pareja —un comienzo que nunca termina, un fin
  /// que nunca empezó—: se ignoran, para que un campo roto no se lleve el
  /// resto del documento.
  final _strayFieldChars = Set<XmlElement>.identity();

  /// El texto de cada encabezado o pie ya leído, por parte.
  final _partTexts = <String, String>{};

  String toMarkdown() {
    // El orden de lectura importa: el cuerpo primero, para que las notas y
    // las listas se numeren como en la página. Los encabezados y pies se
    // leen después aunque se escriban arriba y abajo.
    final body = _story(_body, () => _blocks(_body)).join('\n\n');
    final headers = _headersOrFooters('header');
    final footers = _headersOrFooters('footer');

    return [
      if (headers.isNotEmpty) ...[...headers, '---'],
      if (body.isNotEmpty) body,
      if (footers.isNotEmpty) ...['---', ...footers],
      ..._notes(_footnotes),
      ..._notes(_endnotes),
      ..._notes(_comments),
    ].join('\n\n');
  }

  List<String> _notes(_Notes notes) => _inPart(
    notes.part,
    () => notes.definitions((note) => _story(note, () => _blocks(note))),
  );

  /// Lee [read] con las relaciones de la parte [part].
  T _inPart<T>(String part, T Function() read) {
    final saved = _rels;
    _rels = _package.relationships(part);
    try {
      return read();
    } finally {
      _rels = saved;
    }
  }

  /// Lee [read] como un texto aparte —el cuerpo, un encabezado, una nota, un
  /// cuadro de texto—, con sus propios campos: un campo no empieza en el
  /// cuerpo y termina en una nota.
  T _story<T>(XmlElement root, T Function() read) {
    _scanFields(root);
    final saved = _fields;
    _fields = [];
    try {
      return read();
    } finally {
      _fields = saved;
    }
  }

  // -------------------------------------------------------------------
  // Bloques
  // -------------------------------------------------------------------

  /// Los bloques de un contenedor —el cuerpo, una celda, un cuadro de texto,
  /// una nota— en el orden del documento.
  ///
  /// Se recorre con [_unwrap] y no con los hijos directos (F22): los
  /// controles de contenido (`w:sdt`) y el XML personalizado envuelven
  /// párrafos y tablas enteros —portadas, índices, las secciones de una
  /// plantilla—, y mirando solo `w:p` y `w:tbl` del cuerpo se perdían.
  List<String> _blocks(XmlElement container, {bool inTable = false}) {
    final blocks = <String>[];

    for (final node in _unwrap(container)) {
      if (node.name.namespaceUri != _w) continue;

      switch (node.name.local) {
        case 'p':
          blocks.addAll(_paragraph(node, inTable: inTable));
        case 'tbl':
          final table = inTable ? _flattenTable(node) : _table(node);
          if (table.trim().isNotEmpty) blocks.add(table);
        case 'altChunk':
          blocks.addAll(_altChunk(node, inTable: inTable));
      }
    }

    return blocks;
  }

  /// Un párrafo, seguido de los cuadros de texto, SmartArt y gráficos que
  /// tenga anclados.
  ///
  /// Un cuadro de texto vive dentro de un pedazo del párrafo, pero es otro
  /// texto con sus propios párrafos: pegado en el medio de la frase quedaba
  /// ilegible y sin separación. Va como bloques propios, a continuación.
  List<String> _paragraph(XmlElement paragraph, {required bool inTable}) {
    final properties = paragraph.getElement('pPr', namespace: _w);

    final line = _Line(inTable: inTable);
    final embedded = <String>[];
    _inline(paragraph, line, embedded);
    final text = line.toMarkdown();

    // Un párrafo borrado con control de cambios —su marca de párrafo y todo
    // su texto borrados— no está en el documento que se ve: no se guarda y,
    // sobre todo, no avanza la numeración, o la lista seguiría en "3." donde
    // Word muestra "2." (F22).
    if (_isDeleted(properties?.getElement('rPr', namespace: _w)) &&
        text.trim().isEmpty &&
        embedded.isEmpty) {
      return const [];
    }

    // La numeración avanza aunque el párrafo esté vacío: Word también le da
    // su número, y el siguiente sale "3." y no "2.".
    final item = _numbering.next(properties);

    return [
      // Los párrafos vacíos no se guardan: Word los usa para espaciar, y
      // en Markdown serían saltos que no dicen nada. Lo que sí se guarda
      // entero es el texto: la sangría de adelante —una tabulación, unos
      // espacios— es del original, y no se recorta (F22).
      if (text.trim().isNotEmpty)
        _withStructure(text, properties, item, inTable: inTable),
      ...embedded,
    ];
  }

  String _withStructure(
    String text,
    XmlElement? properties,
    _ListItem? item, {
    required bool inTable,
  }) {
    final label = switch (item) {
      null => '',
      _ListItem(bullet: true) => '- ',
      _ListItem(:final label?) when label.isNotEmpty => label,
      _ => '',
    };

    // Dentro de una celda un `#` sería un carácter más: el encabezado se
    // pierde como marca, pero su número no.
    final heading = inTable ? null : _headingLevel(properties);
    if (heading != null) {
      // Un título de Markdown es una sola línea: un salto adentro dejaba la
      // almohadilla sola y el resto como párrafo —"#   ⏎Capítulo 2", con el
      // salto con que Word empieza una página—. Cada línea lleva su
      // almohadilla, como en el lector de HTML, y las líneas vacías de los
      // bordes, que no tienen ningún carácter, no se escriben (F22).
      final number = item?.bullet ?? false ? '' : label;
      final lines = text
          .split(_markdownBreak)
          .where((line) => line.trim().isNotEmpty)
          .toList();
      return [
        for (final (i, line) in lines.indexed)
          '${'#' * heading} ${i == 0 ? number : ''}$line',
      ].join('\n');
    }

    if (item == null || label.isEmpty) return text;
    final indent = inTable ? '' : '  ' * item.level;
    // Lo mismo con el número de una lista: nunca delante de un salto.
    return '$indent$label${_withoutLeadingBreaks(text)}';
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

    final byName = RegExp(
      r'^(?:heading|t.?tulo|titre|berschrift|titolo)\s*(\d)$',
      caseSensitive: false,
    ).firstMatch(_styleId(properties) ?? '');
    if (byName != null) return int.parse(byName.group(1)!).clamp(1, 6);

    final outline = _val(properties.getElement('outlineLvl', namespace: _w));
    final level = int.tryParse(outline ?? '');
    // `outlineLvl` cuenta desde cero: el 0 es un encabezado de nivel 1. Solo
    // del 0 al 8 son títulos; el 9 es "texto independiente", lo que Word
    // pone para decir que el párrafo **no** es un título (F22).
    if (level == null || level < 0 || level > 8) return null;
    return (level + 1).clamp(1, 6);
  }

  // -------------------------------------------------------------------
  // Texto de un párrafo
  // -------------------------------------------------------------------

  /// Junta el texto de [parent] en [line], y los cuadros de texto, SmartArt
  /// y gráficos que aparezcan en [embedded].
  ///
  /// Se recorre el árbol a mano, en vez de buscar todos los `w:t` que haya
  /// abajo, porque no todo lo que hay abajo es texto de este párrafo: un
  /// cuadro de texto trae sus propios párrafos, y las dos versiones de un
  /// `mc:AlternateContent` traen **el mismo** texto dos veces —se leían las
  /// dos y el cuadro salía duplicado (F22)—.
  void _inline(XmlElement parent, _Line line, List<String> embedded) {
    for (final node in _unwrap(parent)) {
      final name = node.name;

      // Las ecuaciones viven en su propio espacio de nombres, y antes se
      // descartaban enteras con todo lo que no fuera `w:`: un párrafo que
      // era solo una ecuación desaparecía (F22).
      if (name.namespaceUri == _m) {
        if (name.local == 'oMathPara' || name.local == 'oMath') {
          if (_showingText) _math(node, line);
        }
        continue;
      }
      if (name.namespaceUri != _w) continue;

      switch (name.local) {
        case 'r':
          _run(node, line, embedded);
        // Las propiedades no son texto; lo borrado con control de cambios
        // no está en el documento que se ve.
        case 'pPr' || 'rPr' || 'del' || 'moveFrom':
          break;
        default:
          _inline(node, line, embedded);
      }
    }
  }

  /// Una ecuación, en la notación lineal de [_MathWriter]. Las de un bloque
  /// de ecuaciones (`m:oMathPara`) van una por línea.
  void _math(XmlElement math, _Line line) {
    final writer = _MathWriter(line.lineBreak);
    if (math.name.local == 'oMath') {
      line.add(writer.write(math));
      return;
    }
    var first = true;
    for (final equation in math.findElements('oMath', namespace: _m)) {
      if (!first) line.addBreak();
      line.add(writer.write(equation));
      first = false;
    }
  }

  /// Si el texto que viene se ve: fuera de todo campo, o en el resultado de
  /// todos los campos abiertos.
  bool get _showingText => _fields.every((field) => field.separated);

  /// Un pedazo de texto (`w:r`).
  ///
  /// **Campos.** Un campo de Word —un índice, una referencia, una fecha, una
  /// combinación de correspondencia— es un código y su resultado, marcados
  /// con `w:fldChar` de tipo `begin`, `separate` y `end`, y puede abarcar
  /// muchos pedazos y párrafos. Se guarda **el resultado**, lo que se ve.
  /// Los campos se anidan: en `{ IF { MERGEFIELD Sexo } = "F" "Estimada"
  /// "Estimado" }` el "F" es el resultado del campo de adentro, pero está
  /// dentro del **código** del de afuera, y no se ve; antes salía
  /// "FEstimada" (F22). Por eso se lleva la pila de campos abiertos entre
  /// pedazos y párrafos, y solo se escribe texto cuando todos pasaron su
  /// `separate`. `w:fldSimple` ya trae solo su resultado, y se lee siempre.
  ///
  /// **Texto oculto.** El que tiene `w:vanish` se guarda igual: es texto del
  /// documento que el autor escribió —notas para sí, respuestas de un
  /// ejercicio— y Word lo muestra con solo activar "mostrar todo". Perderlo
  /// sería perder texto; mostrar de más no altera nada de lo que se ve.
  void _run(XmlElement run, _Line line, List<String> embedded) {
    final properties = run.getElement('rPr', namespace: _w);
    final bold = properties != null && _isEnabled(properties, 'b');
    final italic = properties != null && _isEnabled(properties, 'i');

    void text(String value) => line.add(value, bold: bold, italic: italic);

    for (final node in _unwrap(run)) {
      if (node.name.namespaceUri == _w && node.name.local == 'fldChar') {
        _fieldChar(node);
        continue;
      }
      if (!_showingText) continue;

      if (node.name.namespaceUri != _w) {
        embedded.addAll(_embedded(node, inTable: line.inTable));
        continue;
      }

      switch (node.name.local) {
        case 't':
          text(node.innerText);
        case 'tab' || 'ptab':
          line.add('\t');
        // Un salto de página o de columna es diseño: dice dónde empieza la
        // página, no parte el texto. Al principio o al final del párrafo no
        // se escribe —antes quedaba "#   ⏎Capítulo 2"—; en el medio es el
        // mismo salto de línea que Word muestra ahí (F22).
        case 'br'
            when const {
              'page',
              'column',
            }.contains(node.getAttribute('type', namespace: _w)):
          line.addLayoutBreak();
        // `w:cr` es el retorno de carro de Word: el mismo salto de línea que
        // `w:br`, sin abrir párrafo.
        case 'br' || 'cr':
          line.addBreak();
        // El guion que no se corta a fin de línea: "e‑mail". Sin esto el
        // guion desaparecía y quedaba "email" (F22).
        case 'noBreakHyphen':
          text('‑');
        // El guion opcional: invisible salvo que Word corte la palabra ahí.
        // Es un carácter del original y se guarda como tal.
        case 'softHyphen':
          text('­');
        case 'sym':
          text(_symbol(node));
        // La lectura de un texto (furigana, pinyin): encima del texto en la
        // página; acá, a continuación y entre paréntesis. Antes se perdían
        // las dos (F22).
        case 'ruby':
          final base = node.getElement('rubyBase', namespace: _w);
          final reading = node.getElement('rt', namespace: _w);
          if (base != null) _inline(base, line, embedded);
          if (reading != null) {
            line.add('(');
            _inline(reading, line, embedded);
            line.add(')');
          }
        case 'footnoteReference':
          line.add(_footnotes.marker(node));
        case 'endnoteReference':
          line.add(_endnotes.marker(node));
        case 'commentReference':
          line.add(_comments.marker(node));
        case 'drawing' || 'pict' || 'object':
          embedded.addAll(_embedded(node, inTable: line.inTable));
      }
    }
  }

  void _fieldChar(XmlElement fieldChar) {
    if (_strayFieldChars.contains(fieldChar)) return;
    switch (fieldChar.getAttribute('fldCharType', namespace: _w)) {
      case 'begin':
        _fields.add(_Field());
      case 'separate':
        _fields.lastOrNull?.separated = true;
      case 'end':
        if (_fields.isNotEmpty) _fields.removeLast();
    }
  }

  /// Marca como sueltas las marcas de campo de [root] que no tienen pareja.
  ///
  /// Un comienzo sin fin callaría todo lo que viene después; se ignora, y el
  /// texto se lee como si el campo no estuviera. Se recorre lo mismo que lee
  /// [_inline]: sin lo borrado ni la segunda versión de un
  /// `mc:AlternateContent`.
  void _scanFields(XmlElement root) {
    final open = <XmlElement>[];
    for (final element in root.descendantElements) {
      if (element.name.namespaceUri != _w || element.name.local != 'fldChar') {
        continue;
      }
      if (_isDiscarded(element, root)) continue;
      switch (element.getAttribute('fldCharType', namespace: _w)) {
        case 'begin':
          open.add(element);
        case 'separate' when open.isEmpty:
          _strayFieldChars.add(element);
        case 'end':
          if (open.isEmpty) {
            _strayFieldChars.add(element);
          } else {
            open.removeLast();
          }
      }
    }
    _strayFieldChars.addAll(open);
  }

  static bool _isDiscarded(XmlElement element, XmlElement root) {
    for (
      var parent = element.parentElement;
      parent != null && parent != root;
      parent = parent.parentElement
    ) {
      final name = parent.name;
      if (name.namespaceUri == _w &&
          (name.local == 'del' || name.local == 'moveFrom')) {
        return true;
      }
      if (name.namespaceUri == _mc && name.local == 'Fallback') return true;
    }
    return false;
  }

  /// Los cuadros de texto, SmartArt y gráficos que haya dentro de [node].
  List<String> _embedded(XmlElement node, {required bool inTable}) {
    final blocks = <String>[];
    for (final child in _unwrap(node)) {
      final name = child.name;
      if (name.namespaceUri == _w && name.local == 'txbxContent') {
        blocks.addAll(_story(child, () => _blocks(child, inTable: inTable)));
      } else if (name.namespaceUri == _dgm && name.local == 'relIds') {
        final text = _smartArt(child, inTable: inTable);
        if (text.trim().isNotEmpty) blocks.add(text);
      } else if ((name.namespaceUri == _c || name.namespaceUri == _cx) &&
          name.local == 'chart') {
        final text = _chart(child, inTable: inTable);
        if (text.trim().isNotEmpty) blocks.add(text);
      } else {
        blocks.addAll(_embedded(child, inTable: inTable));
      }
    }
    return blocks;
  }

  // -------------------------------------------------------------------
  // SmartArt, gráficos y fragmentos incrustados
  // -------------------------------------------------------------------

  /// El texto de un SmartArt, como un bloque: un elemento por línea.
  ///
  /// El dibujo no trae el texto: nombra con `r:dm` la parte de datos
  /// (`word/diagrams/dataN.xml`), donde está cada elemento con sus
  /// párrafos. Antes se perdía entero (F22). Los elementos van en el orden
  /// del diagrama —de cada uno a sus hijos, en el orden que Word les da—,
  /// que es el orden en que se leen; los que no cuelgan de ninguno, al
  /// final, en el orden del archivo.
  String _smartArt(XmlElement relIds, {required bool inTable}) {
    final part = _rels.target(relIds.getAttribute('dm', namespace: _r));
    final data = part == null ? null : _package.optionalXml(part);
    if (data == null) return '';

    final points = <String, XmlElement>{};
    String? root;
    for (final point in data.findAllElements('pt', namespace: _dgm)) {
      final id = point.getAttribute('modelId');
      if (id == null) continue;
      points[id] = point;
      if (point.getAttribute('type') == 'doc') root ??= id;
    }

    final children = <String, List<(int, String)>>{};
    for (final connection in data.findAllElements('cxn', namespace: _dgm)) {
      final type = connection.getAttribute('type') ?? 'parOf';
      final source = connection.getAttribute('srcId');
      final destination = connection.getAttribute('destId');
      if (type != 'parOf' || source == null || destination == null) continue;
      final order = int.tryParse(connection.getAttribute('srcOrd') ?? '') ?? 0;
      children.putIfAbsent(source, () => []).add((order, destination));
    }

    final ordered = <String>[];
    final seen = <String>{};
    void visit(String id) {
      if (!seen.add(id)) return;
      ordered.add(id);
      final next = children[id]?..sort((a, b) => a.$1.compareTo(b.$1));
      for (final (_, child) in next ?? const <(int, String)>[]) {
        visit(child);
      }
    }

    if (root != null) visit(root);
    for (final id in points.keys) {
      visit(id);
    }

    final lineBreak = inTable ? _cellBreak : _markdownBreak;
    return [
      for (final id in ordered)
        if (points[id]?.getElement('t', namespace: _dgm) case final text?)
          ..._drawingParagraphs(text),
    ].join(lineBreak);
  }

  /// El texto de un gráfico —su título, los de sus ejes, las etiquetas
  /// escritas—, como un bloque: un párrafo por línea. El dibujo nombra con
  /// `r:id` la parte del gráfico (`word/charts/chartN.xml`) (F22).
  String _chart(XmlElement chart, {required bool inTable}) {
    final part = _rels.target(chart.getAttribute('id', namespace: _r));
    final root = part == null ? null : _package.optionalXml(part);
    if (root == null) return '';
    return _drawingParagraphs(root).join(inTable ? _cellBreak : _markdownBreak);
  }

  /// Los párrafos de DrawingML (`a:p`) con texto que haya dentro de [root].
  static List<String> _drawingParagraphs(XmlElement root) => [
    for (final paragraph in root.findAllElements('p', namespace: _a))
      if (paragraph
              .findAllElements('t', namespace: _a)
              .map((text) => text.innerText)
              .join()
          case final text when text.trim().isNotEmpty)
        text,
  ];

  /// Un fragmento incrustado (`w:altChunk`): otro archivo —HTML, texto,
  /// otro Word— que Word muestra en ese lugar como parte del documento.
  ///
  /// Antes se perdía (F22). HTML se convierte con el mismo conversor que las
  /// páginas web y los EPUB; texto, con la misma lectura de codificación que
  /// un `.txt`; un Word, leyéndolo entero con este lector. Otro formato
  /// —RTF, MHT— no se sabe leer: no frena el documento, y queda registrado.
  List<String> _altChunk(XmlElement chunk, {required bool inTable}) {
    final id = chunk.getAttribute('id', namespace: _r);
    final part = _rels.target(id);
    final data = part == null ? null : _package.bytes(part);
    if (part == null || data == null) {
      _package.warnings.add(
        'trae un fragmento incrustado ($id) que no se encontró: se leyó '
        'sin él.',
      );
      return const [];
    }

    final type = (_package.contentType(part) ?? '').toLowerCase();
    final extension = p.url.extension(part).toLowerCase();
    String markdown;
    if (type.contains('html') ||
        const {'.htm', '.html', '.xhtml'}.contains(extension)) {
      markdown = htmlToMarkdown(decodeHtmlBytes(data));
    } else if (type == 'text/plain' || extension == '.txt') {
      markdown = decodePlainText(data);
    } else if (type.contains('wordprocessingml.document') ||
        const {'.docx', '.docm'}.contains(extension)) {
      if (_depth >= _maxNesting) {
        _package.warnings.add(
          'trae documentos incrustados más de $_maxNesting veces uno dentro '
          'de otro: se leyó sin $part.',
        );
        return const [];
      }
      try {
        final nested = _parseDocx(data, depth: _depth + 1);
        _package.warnings.addAll(nested.warnings);
        markdown = nested.document.markdown;
      } on UnreadableDocumentException catch (e) {
        _package.warnings.add(
          'trae un documento incrustado ($part) ilegible (${e.detail}): se '
          'leyó sin él.',
        );
        return const [];
      }
    } else {
      _package.warnings.add(
        'trae un fragmento incrustado ($part, '
        '${type.isEmpty ? 'sin tipo' : type}) '
        'en un formato que no se sabe leer: se leyó sin él.',
      );
      return const [];
    }

    if (markdown.trim().isEmpty) return const [];
    // Dentro de una celda, un salto de verdad partiría la fila.
    return [
      if (inTable)
        markdown.replaceAll(RegExp(r'\r\n|\r|\n'), _cellBreak)
      else
        markdown,
    ];
  }

  // -------------------------------------------------------------------
  // Tablas
  // -------------------------------------------------------------------

  /// Convierte una tabla de Word a una tabla de Markdown.
  ///
  /// Las tablas son de lo que peor sobrevive a una conversión descuidada: un
  /// cuadro comparativo aplastado a texto corrido pierde exactamente la
  /// información por la que era un cuadro.
  String _table(XmlElement table) {
    final rows = [
      for (final row in _rows(table))
        // La única alteración del texto que se admite, y solo acá: una `|`
        // dentro de una celda partiría la fila en una columna de más, así
        // que se escapa como `\|`, que es como Markdown la muestra.
        _rowCells(row).map((cell) => cell.replaceAll('|', r'\|')).toList(),
    ].where((cells) => cells.isNotEmpty).toList();

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

  /// Una tabla dentro de una celda.
  ///
  /// Markdown no tiene tablas anidadas, y antes se perdían enteras (F22).
  /// Quedan aplanadas en su lugar: una línea por fila y las celdas separadas
  /// por `|`, que la tabla de afuera escapa y se ve tal cual.
  String _flattenTable(XmlElement table) => [
    for (final row in _rows(table)) _rowCells(row).join(' | '),
  ].where((row) => row.trim().isNotEmpty).join(_cellBreak);

  /// El texto de las celdas de una fila, alineadas con la grilla.
  ///
  /// Una celda combinada (`w:gridSpan`) ocupa varias columnas, y una fila
  /// puede empezar o terminar con columnas sin celda (`w:gridBefore`,
  /// `w:gridAfter`). Markdown no combina celdas: la combinada va seguida de
  /// tantas vacías como columnas de más ocupa, y las que faltan al principio
  /// van vacías, para que cada texto quede en su columna (F22).
  List<String> _rowCells(XmlElement row) {
    final rowProperties = row.getElement('trPr', namespace: _w);
    int grid(XmlElement? properties, String name) =>
        (int.tryParse(
                  _val(properties?.getElement(name, namespace: _w)) ?? '',
                ) ??
                0)
            .clamp(0, _maxColumns);

    return [
      ...List.filled(grid(rowProperties, 'gridBefore'), ''),
      for (final cell in _cells(row)) ...[
        _cellText(cell),
        ...List.filled(
          (grid(cell.getElement('tcPr', namespace: _w), 'gridSpan') - 1).clamp(
            0,
            _maxColumns,
          ),
          '',
        ),
      ],
      ...List.filled(grid(rowProperties, 'gridAfter'), ''),
    ];
  }

  /// El texto de una celda, con sus párrafos separados por `<br>`.
  ///
  /// Un salto de línea de verdad partiría la fila de la tabla de Markdown en
  /// dos. `<br>` es el salto que las tablas de Markdown aceptan: antes los
  /// párrafos de una celda se pegaban con un espacio y no se distinguían
  /// (F22).
  String _cellText(XmlElement cell) =>
      _blocks(cell, inTable: true).join(_cellBreak);

  /// Las filas de una tabla, sin las borradas con control de cambios: no
  /// están en la tabla que se ve (F22).
  Iterable<XmlElement> _rows(XmlElement table) => _unwrap(table).where(
    (node) =>
        node.name.namespaceUri == _w &&
        node.name.local == 'tr' &&
        !_isDeleted(node.getElement('trPr', namespace: _w)),
  );

  Iterable<XmlElement> _cells(XmlElement row) => _unwrap(
    row,
  ).where((node) => node.name.namespaceUri == _w && node.name.local == 'tc');

  String _row(List<String> cells, int columns) {
    final padded = [...cells, ...List.filled(columns - cells.length, '')];
    return '| ${padded.join(' | ')} |';
  }

  // -------------------------------------------------------------------
  // Encabezados y pies de página
  // -------------------------------------------------------------------

  /// Los encabezados (o pies) que el documento muestra, cada texto una vez.
  ///
  /// Se leen los que nombra cada sección, en orden, y no todos los
  /// `header*.xml` del ZIP: Word conserva el de "primera página distinta"
  /// aunque se haya desactivado, y ese no se ve. Un documento con diez
  /// secciones y el mismo pie lo repetiría diez veces; se guarda una. Y cada
  /// parte se lee una vez, aunque la nombren las diez (F22).
  List<String> _headersOrFooters(String kind) {
    final settings = _settings;
    final evenAndOdd =
        settings != null && _isEnabled(settings, 'evenAndOddHeaders');

    final seen = <String>{};
    final texts = <String>[];
    for (final section in _body.findAllElements('sectPr', namespace: _w)) {
      final titlePage = _isEnabled(section, 'titlePg');

      for (final reference in section.findElements(
        '${kind}Reference',
        namespace: _w,
      )) {
        final type = reference.getAttribute('type', namespace: _w);
        if (type == 'first' && !titlePage) continue;
        if (type == 'even' && !evenAndOdd) continue;

        final part = _documentRels.target(
          reference.getAttribute('id', namespace: _r),
        );
        if (part == null) continue;

        final text = _partTexts.putIfAbsent(part, () {
          final root = _package.optionalXml(part);
          if (root == null) return '';
          return _inPart(
            part,
            () => _story(root, () => _blocks(root)),
          ).join('\n\n');
        });
        if (text.trim().isNotEmpty && seen.add(text)) texts.add(text);
      }
    }
    return texts;
  }
}

/// Un campo abierto: si ya pasó del código a su resultado.
class _Field {
  bool separated = false;
}

/// Sin los saltos de línea del principio.
String _withoutLeadingBreaks(String text) {
  var rest = text;
  while (true) {
    if (rest.startsWith(_markdownBreak)) {
      rest = rest.substring(_markdownBreak.length);
    } else if (rest.startsWith(_cellBreak)) {
      rest = rest.substring(_cellBreak.length);
    } else {
      return rest;
    }
  }
}

/// Si unas propiedades (de un párrafo, de una fila) dicen que el elemento
/// fue borrado con control de cambios.
bool _isDeleted(XmlElement? properties) =>
    properties != null &&
    (properties.getElement('del', namespace: _w) != null ||
        properties.getElement('moveFrom', namespace: _w) != null);

/// El máximo de columnas de una tabla de Word: un `gridSpan` más grande es
/// un archivo roto, no una tabla.
const _maxColumns = 63;

// ---------------------------------------------------------------------
// Negritas y cursivas
// ---------------------------------------------------------------------

/// El texto de un párrafo en pedazos, cada uno con su negrita y su cursiva.
///
/// Word parte el texto en "runs" cada vez que cambia algún atributo —incluso
/// por una corrección ortográfica—, así que una sola frase puede venir en
/// seis pedazos. Los pedazos consecutivos con el mismo formato se juntan
/// **antes** de marcarlos: sin eso, una frase entera en negrita saldría como
/// `**Una****frase**`. Antes se juntaban después, borrando todo `****` del
/// texto, y se llevaba puesto un "****" que estuviera escrito en el
/// documento ("Clave: ****" quedaba "Clave: ", F22).
class _Line {
  _Line({required this.inTable});

  /// Si el párrafo está dentro de una celda de tabla.
  final bool inTable;

  /// Cómo se escribe un salto de línea que no abre párrafo: distinto dentro
  /// de una celda, donde un salto de verdad partiría la fila.
  String get lineBreak => inTable ? _cellBreak : _markdownBreak;

  final _pieces = <_Piece>[];

  /// Un salto de página o de columna que espera a ver si hay texto después.
  bool _layoutBreak = false;

  // Cada pedazo junta su texto en un `StringBuffer`, y no sumando cadenas:
  // un párrafo de miles de pedazos con el mismo formato —un documento
  // generado por otro programa— se copiaba entero en cada uno (F22).
  void add(String text, {bool bold = false, bool italic = false}) {
    if (text.isEmpty) return;
    _flushLayoutBreak();

    final last = _pieces.lastOrNull;
    if (last != null &&
        !last.isBreak &&
        last.bold == bold &&
        last.italic == italic) {
      last.text.write(text);
    } else {
      _pieces.add(_Piece(bold: bold, italic: italic)..text.write(text));
    }
  }

  /// Un salto de línea sin párrafo nuevo.
  void addBreak() {
    _flushLayoutBreak();
    _pieces.add(_Piece(isBreak: true)..text.write(lineBreak));
  }

  /// Un salto de página o de columna: un salto de línea si queda entre dos
  /// textos; nada si está al principio o al final del párrafo.
  void addLayoutBreak() {
    if (_pieces.isNotEmpty) _layoutBreak = true;
  }

  void _flushLayoutBreak() {
    if (!_layoutBreak) return;
    _layoutBreak = false;
    _pieces.add(_Piece(isBreak: true)..text.write(lineBreak));
  }

  /// El párrafo con sus marcas de negrita y cursiva.
  ///
  /// Las marcas se abren y se cierran como una pila, anidadas: una palabra
  /// en negrita y cursiva en medio de una frase en negrita queda
  /// `**super*cali*fragil**`, y no `**super*****cali*****fragil**`, que se
  /// lee de más de una forma (F22). Cuando dos marcas empiezan juntas, va
  /// afuera la que dura más, para que la otra se cierre adentro. Los
  /// espacios de los bordes van **afuera** de las marcas: `** texto **` no
  /// es negrita en Markdown, es un asterisco literal. Un salto de línea
  /// cierra todo: un título de varias líneas se escribe línea por línea.
  String toMarkdown() {
    final out = StringBuffer();
    final open = <_Mark>[];
    final spaces = StringBuffer();

    void closeFrom(int index) {
      while (open.length > index) {
        out.write(open.removeLast().delimiter);
      }
    }

    for (final (i, piece) in _pieces.indexed) {
      final text = piece.text.toString();
      if (piece.isBreak) {
        closeFrom(0);
        out
          ..write(spaces)
          ..write(text);
        spaces.clear();
        continue;
      }

      final core = text.trim();
      if (core.isEmpty) {
        spaces.write(text);
        continue;
      }
      final leading = text.substring(0, text.indexOf(core));
      final trailing = text.substring(leading.length + core.length);

      final wanted = {
        if (piece.bold) _Mark.bold,
        if (piece.italic) _Mark.italic,
      };
      final firstUnwanted = open.indexWhere((mark) => !wanted.contains(mark));
      if (firstUnwanted != -1) closeFrom(firstUnwanted);

      out
        ..write(spaces)
        ..write(leading);
      spaces.clear();

      final missing = wanted.where((mark) => !open.contains(mark)).toList()
        ..sort((a, b) {
          final longer = _reach(i, b).compareTo(_reach(i, a));
          return longer != 0 ? longer : a.index.compareTo(b.index);
        });
      for (final mark in missing) {
        out.write(mark.delimiter);
        open.add(mark);
      }

      out.write(core);
      spaces.write(trailing);
    }

    closeFrom(0);
    out.write(spaces);
    return out.toString();
  }

  /// Cuántos pedazos con texto seguidos, desde [start], llevan [mark].
  int _reach(int start, _Mark mark) {
    var count = 0;
    for (final piece in _pieces.skip(start)) {
      if (piece.isBreak) break;
      if (piece.text.toString().trim().isEmpty) continue;
      if (!(mark == _Mark.bold ? piece.bold : piece.italic)) break;
      count++;
    }
    return count;
  }
}

class _Piece {
  _Piece({this.bold = false, this.italic = false, this.isBreak = false});

  final bool bold;
  final bool italic;

  /// Un salto de línea: no lleva marcas, y las cierra.
  final bool isBreak;

  final text = StringBuffer();
}

enum _Mark {
  bold('**'),
  italic('*');

  const _Mark(this.delimiter);

  final String delimiter;
}

// ---------------------------------------------------------------------
// Ecuaciones
// ---------------------------------------------------------------------

/// Una ecuación de Word (OMML, `m:oMath`) en notación lineal.
///
/// Lo que importa es no perder ningún carácter de la ecuación (`m:t`), en el
/// orden en que se lee. La estructura se escribe con una notación lineal
/// mínima, la de UnicodeMath —la que Word mismo usa al escribir ecuaciones
/// en una línea—, que se lee sin saberla (F22):
///
/// - Superíndice `x^2`, subíndice `x_i`, los dos `x_i^2`; a la izquierda de
///   la base, `_(92)^(235)U`. Límites de abajo y de arriba, igual:
///   `lim_(n→∞)`.
/// - Fracción `(a+b)/c`; la fracción sin raya (un apilado), `a¦b`.
/// - Raíz `√x`, `∛x`, `∜x`, y la de otro índice `√(n&x)`.
/// - Suma, integral y compañía: el operador con sus límites y un espacio
///   antes de lo que abarca, `∑_(i=1)^n a_i`. Sin operador escrito, Word
///   dibuja una integral.
/// - Delimitadores, los que dice la ecuación: `(a+b)`, `[0,1]`, `|x|`, con
///   su separador entre elementos.
/// - Función `sin x`; acento, el carácter combinado (`x̂`); raya encima o
///   debajo, combinada (`x̅`), o `¯(ab)` y `▁(ab)` si abarca más de uno;
///   llave de agrupación `⏟(a+b)`.
/// - Matriz `■(a&b@c&d)`: `&` entre columnas y `@` entre filas. Un sistema
///   de ecuaciones, una por línea.
///
/// Los paréntesis se agregan solo si hacen falta: `x^2` y `x^10`, pero
/// `x^(n+1)`. El texto oculto de un fantasma (`m:phant` sin mostrar) no se
/// ve en la ecuación y no se escribe.
class _MathWriter {
  const _MathWriter(this.lineBreak);

  /// Con qué se separan las filas de un sistema de ecuaciones.
  final String lineBreak;

  String write(XmlElement math) => _children(math).text;

  _MathText _children(XmlElement? parent) {
    if (parent == null) return const (text: '', kind: _MathKind.atom);
    final parts = [
      for (final child in _unwrap(parent))
        if (!_skipped(child)) _element(child),
    ].where((part) => part.text.isNotEmpty).toList();
    if (parts.length == 1) return parts.single;
    return _plain(parts.map((part) => part.text).join());
  }

  static bool _skipped(XmlElement element) {
    final name = element.name;
    // Las propiedades no son texto, y lo borrado no está.
    if (name.local.endsWith('Pr')) return true;
    return name.namespaceUri == _w &&
        const {'del', 'moveFrom', 'rPr'}.contains(name.local);
  }

  _MathText _element(XmlElement element) {
    final name = element.name;
    if (name.namespaceUri == _w) {
      return name.local == 't' ? _plain(element.innerText) : _children(element);
    }
    if (name.namespaceUri != _m) return _children(element);

    XmlElement? part(String local) => element.getElement(local, namespace: _m);
    XmlElement? properties(String local) => part('${name.local}Pr');
    String? property(String local) {
      final element = properties(local)?.getElement(local, namespace: _m);
      return element?.getAttribute('val', namespace: _m) ??
          (element == null ? null : '');
    }

    bool on(String local) => switch (property(local)) {
      null => false,
      '' || '1' || 'on' || 'true' => true,
      _ => false,
    };

    switch (name.local) {
      case 't':
        return _plain(element.innerText);
      case 'sSup':
        return _script(_children(part('e')), sup: _children(part('sup')));
      case 'sSub':
        return _script(_children(part('e')), sub: _children(part('sub')));
      case 'sSubSup':
        return _script(
          _children(part('e')),
          sub: _children(part('sub')),
          sup: _children(part('sup')),
        );
      case 'sPre':
        final base = _children(part('e'));
        final scripts = _script(
          const (text: '', kind: _MathKind.atom),
          sub: _children(part('sub')),
          sup: _children(part('sup')),
        );
        return (text: '${scripts.text}${_base(base)}', kind: _MathKind.other);
      case 'limLow':
        return _script(_children(part('e')), sub: _children(part('lim')));
      case 'limUpp':
        return _script(_children(part('e')), sup: _children(part('lim')));
      case 'f':
        final bar = property('type') == 'noBar' ? '¦' : '/';
        return (
          text:
              '${_argument(_children(part('num')))}$bar'
              '${_argument(_children(part('den')))}',
          kind: _MathKind.other,
        );
      case 'rad':
        final degree = on('degHide') ? '' : _children(part('deg')).text.trim();
        final radicand = _children(part('e'));
        return (
          text: switch (degree) {
            '' => '√${_argument(radicand)}',
            '3' => '∛${_argument(radicand)}',
            '4' => '∜${_argument(radicand)}',
            _ => '√($degree&${radicand.text})',
          },
          kind: _MathKind.other,
        );
      case 'nary':
        final operator = property('chr');
        final limits = _script(
          (
            text: operator == null || operator.isEmpty ? '∫' : operator,
            kind: _MathKind.atom,
          ),
          sub: on('subHide') ? null : _children(part('sub')),
          sup: on('supHide') ? null : _children(part('sup')),
        );
        final body = _children(part('e')).text;
        return (
          text: body.isEmpty ? limits.text : '${limits.text} $body',
          kind: _MathKind.other,
        );
      case 'd':
        final begin = property('begChr') ?? '(';
        final end = property('endChr') ?? ')';
        final separator = property('sepChr') ?? '|';
        final items = [
          for (final item in element.findElements('e', namespace: _m))
            _children(item).text,
        ];
        return (
          text: '$begin${items.join(separator)}$end',
          kind: _MathKind.group,
        );
      case 'func':
        final function = _children(part('fName')).text;
        final argument = _children(part('e')).text;
        final glue = argument.isEmpty || '([{|'.contains(argument[0])
            ? ''
            : ' ';
        return (text: '$function$glue$argument', kind: _MathKind.other);
      case 'acc':
        final accent = property('chr');
        final base = _children(part('e'));
        final text =
            _argument(base) + (accent == null || accent.isEmpty ? '̂' : accent);
        return (
          text: text,
          kind: _isAtomic(text) ? _MathKind.atom : _MathKind.other,
        );
      case 'bar':
        final top = property('pos') == 'top';
        final base = _children(part('e'));
        if (_isAtomic(base.text)) {
          return (text: '${base.text}${top ? '̅' : '̲'}', kind: _MathKind.atom);
        }
        return (
          text: '${top ? '¯' : '▁'}(${base.text})',
          kind: _MathKind.other,
        );
      case 'groupChr':
        final symbol = property('chr');
        return (
          text:
              '${symbol == null || symbol.isEmpty ? '⏟' : symbol}'
              '${_argument(_children(part('e')))}',
          kind: _MathKind.other,
        );
      case 'eqArr':
        return (
          text: [
            for (final row in element.findElements('e', namespace: _m))
              _children(row).text,
          ].join(lineBreak),
          kind: _MathKind.other,
        );
      case 'm':
        final rows = [
          for (final row in element.findElements('mr', namespace: _m))
            [
              for (final cell in row.findElements('e', namespace: _m))
                _children(cell).text,
            ].join('&'),
        ];
        return (text: '■(${rows.join('@')})', kind: _MathKind.group);
      case 'phant':
        final hidden = switch (property('show')) {
          '0' || 'off' || 'false' => true,
          _ => false,
        };
        return hidden
            ? const (text: '', kind: _MathKind.atom)
            : _children(part('e'));
      default:
        // `m:r`, `m:e`, `m:box`, `m:borderBox`, `m:oMath` y lo que no se
        // conozca: su contenido, en orden. Así ningún `m:t` se pierde.
        return _children(element);
    }
  }

  _MathText _script(_MathText base, {_MathText? sub, _MathText? sup}) {
    final buffer = StringBuffer(_base(base));
    if (sub != null && sub.text.isNotEmpty) {
      buffer.write('_${_argument(sub)}');
    }
    if (sup != null && sup.text.isNotEmpty) {
      buffer.write('^${_argument(sup)}');
    }
    return (text: buffer.toString(), kind: _MathKind.script);
  }

  /// Una base de índices: sin paréntesis si ya es una sola cosa —una letra,
  /// un número, algo entre delimitadores, otra base con índices—.
  static String _base(_MathText base) =>
      base.kind != _MathKind.other || _isAtomic(base.text)
      ? base.text
      : '(${base.text})';

  /// Un índice, un numerador, un radicando: sin paréntesis si es una letra,
  /// un número o algo que ya está entre delimitadores.
  static String _argument(_MathText argument) =>
      argument.kind == _MathKind.atom ||
          argument.kind == _MathKind.group ||
          _isAtomic(argument.text)
      ? argument.text
      : '(${argument.text})';

  static _MathText _plain(String text) =>
      (text: text, kind: _isAtomic(text) ? _MathKind.atom : _MathKind.other);

  /// Un solo carácter —con sus acentos combinados— o un número.
  static bool _isAtomic(String text) {
    if (text.isEmpty) return true;
    if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) return true;
    final runes = text.runes.toList();
    return runes
        .skip(1)
        .every(
          (rune) =>
              (rune >= 0x0300 && rune <= 0x036F) ||
              (rune >= 0x20D0 && rune <= 0x20FF),
        );
  }
}

enum _MathKind {
  /// Una letra, un número.
  atom,

  /// Algo entre delimitadores, o una matriz.
  group,

  /// Una base con índices.
  script,

  /// Lo demás: una suma de términos, una fracción.
  other,
}

typedef _MathText = ({String text, _MathKind kind});

// ---------------------------------------------------------------------
// Numeración
// ---------------------------------------------------------------------

/// Un párrafo numerado: su nivel y lo que Word escribe adelante.
class _ListItem {
  const _ListItem({required this.level, this.label, this.bullet = false});

  final int level;

  /// El número ya armado, con su separador: "1. ", "a) ", "3.2.1 ".
  final String? label;

  final bool bullet;
}

/// La numeración de las listas, calculada como la calcula Word (F22).
///
/// Antes todo párrafo numerado salía como `- `: un "a)" o un "3.2.1" del
/// original se perdía. El número no está escrito en el texto; Word lo arma
/// con la definición de `numbering.xml` —formato, plantilla como `%1.%2.`,
/// inicio— y un contador por lista y nivel.
///
/// Los contadores van por definición abstracta (`w:abstractNum`) y no por
/// `w:num`: Word continúa la numeración entre dos listas que comparten
/// definición, salvo que la segunda diga dónde reiniciar (`startOverride`),
/// que es como Word escribe "reiniciar en 1".
class _Numbering {
  _Numbering(XmlElement? numbering, XmlElement? styles) {
    if (numbering != null) {
      for (final abstract in numbering.findElements(
        'abstractNum',
        namespace: _w,
      )) {
        final id = abstract.getAttribute('abstractNumId', namespace: _w);
        if (id == null) continue;
        _abstracts[id] = (
          levels: _levels(abstract),
          styleLink: _val(abstract.getElement('numStyleLink', namespace: _w)),
        );
      }
      for (final num in numbering.findElements('num', namespace: _w)) {
        final id = num.getAttribute('numId', namespace: _w);
        final abstractId = _val(num.getElement('abstractNumId', namespace: _w));
        if (id == null || abstractId == null) continue;

        final starts = <int, int>{};
        final levels = <int, _Level>{};
        for (final override in num.findElements('lvlOverride', namespace: _w)) {
          final level = int.tryParse(
            override.getAttribute('ilvl', namespace: _w) ?? '',
          );
          if (level == null) continue;
          final start = int.tryParse(
            _val(override.getElement('startOverride', namespace: _w)) ?? '',
          );
          if (start != null) starts[level] = start;
          final lvl = override.getElement('lvl', namespace: _w);
          if (lvl != null) levels[level] = _Level.parse(lvl);
        }
        _nums[id] = (abstractId: abstractId, starts: starts, levels: levels);
      }
    }

    if (styles != null) {
      for (final style in styles.findElements('style', namespace: _w)) {
        final id = style.getAttribute('styleId', namespace: _w);
        if (id == null) continue;
        final numPr = style
            .getElement('pPr', namespace: _w)
            ?.getElement('numPr', namespace: _w);
        _styles[id] = (
          numId: _val(numPr?.getElement('numId', namespace: _w)),
          level: int.tryParse(
            _val(numPr?.getElement('ilvl', namespace: _w)) ?? '',
          ),
          basedOn: _val(style.getElement('basedOn', namespace: _w)),
        );
      }
    }
  }

  final _abstracts = <String, ({Map<int, _Level> levels, String? styleLink})>{};
  final _nums =
      <
        String,
        ({String abstractId, Map<int, int> starts, Map<int, _Level> levels})
      >{};
  final _styles = <String, ({String? numId, int? level, String? basedOn})>{};

  /// El valor actual de cada nivel, por definición abstracta.
  final _counters = <String, Map<int, int>>{};

  /// Las listas que ya aplicaron su reinicio.
  final _restarted = <String>{};

  /// El párrafo con estas [properties] como elemento de lista, avanzando la
  /// cuenta; `null` si no está numerado.
  _ListItem? next(XmlElement? properties) {
    final reference = _reference(properties);
    if (reference == null) return null;
    final (:numId, :level, :styleId) = reference;

    final num = _nums[numId];
    final abstract = num == null ? null : _resolve(num.abstractId);
    // Sin definición —un documento a medio armar, o sin numbering.xml— no
    // hay número que calcular: queda como viñeta, como siempre.
    if (num == null || abstract == null) {
      return _ListItem(level: level ?? 0, bullet: true);
    }
    final levels = abstract.levels;

    // Un estilo numerado sin nivel propio usa el nivel que lo nombra.
    final ilvl =
        level ??
        levels.entries
            .where((entry) => entry.value.styleId == styleId)
            .firstOrNull
            ?.key ??
        0;
    _Level? definition(int l) => num.levels[l] ?? levels[l];
    int start(int l) => num.starts[l] ?? definition(l)?.start ?? 1;

    final counters = _counters.putIfAbsent(abstract.id, () => {});
    if (_restarted.add(numId)) {
      for (final l in num.starts.keys) {
        counters.remove(l);
      }
    }
    counters[ilvl] = counters.containsKey(ilvl)
        ? counters[ilvl]! + 1
        : start(ilvl);
    // Un elemento de un nivel reinicia los de adentro: después de "2." viene
    // "2.1", no "1.4".
    counters.removeWhere((l, _) => l > ilvl);

    final current = definition(ilvl);
    if (current == null) return _ListItem(level: ilvl, bullet: true);
    if (current.format == 'bullet') return _ListItem(level: ilvl, bullet: true);

    final text = current.text.replaceAllMapped(RegExp('%([1-9])'), (match) {
      final l = int.parse(match.group(1)!) - 1;
      final value = counters[l] ?? start(l);
      // "Numeración legal": los niveles de arriba en arábigos, sea cual sea
      // su formato ("1.1" y no "I.1").
      final format = current.legal ? 'decimal' : definition(l)?.format;
      return _formatNumber(value, format ?? 'decimal');
    });
    if (text.isEmpty) return _ListItem(level: ilvl, label: '');

    return _ListItem(level: ilvl, label: '$text${current.suffix}');
  }

  /// La definición abstracta que de verdad tiene los niveles.
  ///
  /// Una lista definida con un **estilo de lista** tiene una definición
  /// vacía que solo dice qué estilo usar (`w:numStyleLink`). Hay que seguir
  /// el estilo hasta su lista (`w:numId`) y de ahí a la definición con los
  /// niveles; sin eso, la lista salía como viñetas "- " (F22). Los contadores
  /// van por la definición a la que se llega: dos listas con el mismo
  /// estilo continúan la misma numeración, como en Word.
  ({String id, Map<int, _Level> levels})? _resolve(String abstractId) {
    var id = abstractId;
    final visited = <String>{};
    while (visited.add(id)) {
      final abstract = _abstracts[id];
      if (abstract == null) return null;

      final link = abstract.styleLink;
      final linkedNum = link == null ? null : _styles[link]?.numId;
      final linked = linkedNum == null ? null : _nums[linkedNum]?.abstractId;
      if (linked == null) return (id: id, levels: abstract.levels);
      id = linked;
    }
    // Un estilo que termina nombrándose a sí mismo: la primera definición.
    final abstract = _abstracts[abstractId];
    return abstract == null ? null : (id: abstractId, levels: abstract.levels);
  }

  /// La lista y el nivel del párrafo: los propios, o los de su estilo —así
  /// numera Word los títulos "1.", "1.1"—.
  ({String numId, int? level, String? styleId})? _reference(
    XmlElement? properties,
  ) {
    final own = properties?.getElement('numPr', namespace: _w);
    var numId = _val(own?.getElement('numId', namespace: _w));
    var level = int.tryParse(
      _val(own?.getElement('ilvl', namespace: _w)) ?? '',
    );

    final styleId = properties == null ? null : _styleId(properties);
    var style = styleId;
    final visited = <String>{};
    while ((numId == null || level == null) &&
        style != null &&
        visited.add(style)) {
      final definition = _styles[style];
      if (definition == null) break;
      numId ??= definition.numId;
      level ??= definition.level;
      style = definition.basedOn;
    }

    // `numId` 0 es "sin numeración": así se le quita a un párrafo la que
    // hereda de su estilo.
    if (numId == null || numId == '0') return null;
    return (numId: numId, level: level, styleId: styleId);
  }

  static Map<int, _Level> _levels(XmlElement abstract) => {
    for (final lvl in abstract.findElements('lvl', namespace: _w))
      if (int.tryParse(lvl.getAttribute('ilvl', namespace: _w) ?? '')
          case final level?)
        level: _Level.parse(lvl),
  };
}

/// Un nivel de una definición de numeración (`w:lvl`).
class _Level {
  const _Level({
    required this.start,
    required this.format,
    required this.text,
    required this.suffix,
    required this.legal,
    required this.styleId,
  });

  factory _Level.parse(XmlElement lvl) => _Level(
    start:
        int.tryParse(_val(lvl.getElement('start', namespace: _w)) ?? '') ?? 1,
    format: _val(lvl.getElement('numFmt', namespace: _w)) ?? 'decimal',
    text: _val(lvl.getElement('lvlText', namespace: _w)) ?? '',
    // Lo que va entre el número y el texto: Word pone una tabulación por
    // defecto, que acá es un espacio —el que Markdown pide después de "1."—.
    suffix: _val(lvl.getElement('suff', namespace: _w)) == 'nothing' ? '' : ' ',
    legal: _isEnabled(lvl, 'isLgl'),
    styleId: _val(lvl.getElement('pStyle', namespace: _w)),
  );

  final int start;
  final String format;
  final String text;
  final String suffix;
  final bool legal;
  final String? styleId;
}

/// Un número en el formato de Word.
///
/// Los formatos que dependen del idioma —"primero", "1st"— o de un alfabeto
/// propio salen en arábigos: el número es el correcto aunque no luzca igual.
String _formatNumber(int value, String format) => switch (format) {
  'decimalZero' => value < 10 ? '0$value' : '$value',
  'upperRoman' => _roman(value),
  'lowerRoman' => _roman(value).toLowerCase(),
  'upperLetter' => _letters(value),
  'lowerLetter' => _letters(value).toLowerCase(),
  'decimalEnclosedParen' => '($value)',
  'decimalEnclosedCircle' when value >= 1 && value <= 20 => String.fromCharCode(
    0x2460 + value - 1,
  ),
  'none' => '',
  _ => '$value',
};

String _roman(int value) {
  if (value <= 0) return '$value';
  const numerals = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final buffer = StringBuffer();
  var rest = value;
  for (final (amount, numeral) in numerals) {
    while (rest >= amount) {
      buffer.write(numeral);
      rest -= amount;
    }
  }
  return buffer.toString();
}

/// "A" a "Z", y después "AA", "BB"…: Word repite la letra, no cuenta como
/// una planilla.
String _letters(int value) {
  if (value <= 0) return '$value';
  final letter = String.fromCharCode(0x41 + (value - 1) % 26);
  return letter * ((value - 1) ~/ 26 + 1);
}

// ---------------------------------------------------------------------
// Notas y comentarios
// ---------------------------------------------------------------------

/// Las notas al pie, las notas finales o los comentarios de un documento:
/// cada uno recibe su marca la primera vez que el texto lo nombra.
class _Notes {
  _Notes(this.part, XmlElement? root, String element, this._label) {
    if (root == null) return;
    for (final note in root.findElements(element, namespace: _w)) {
      final id = note.getAttribute('id', namespace: _w);
      if (id != null) _parts[id] = note;
    }
  }

  /// La parte del paquete donde están: sus relaciones son las de las notas.
  final String part;

  final String Function(int number) _label;
  final _parts = <String, XmlElement>{};
  final _labels = <String, String>{};

  /// La marca que va en el texto donde está [reference].
  String marker(XmlElement reference) {
    final id = reference.getAttribute('id', namespace: _w);
    if (id == null || !_parts.containsKey(id)) return '';
    return '[^${_labels.putIfAbsent(id, () => _label(_labels.length + 1))}]';
  }

  /// El texto de cada nota nombrada, en el orden de sus marcas.
  ///
  /// Una nota de varios párrafos sigue con sangría de cuatro espacios, que
  /// es como Markdown sabe que el párrafo es de la nota y no del documento.
  List<String> definitions(List<String> Function(XmlElement) blocks) => [
    for (final MapEntry(key: id, value: label) in _labels.entries.toList())
      _definition(label, _parts[id]!, blocks),
  ];

  String _definition(
    String label,
    XmlElement note,
    List<String> Function(XmlElement) blocks,
  ) {
    final author = note.getAttribute('author', namespace: _w);
    final lines = blocks(note).join('\n\n').split('\n');
    final text = [
      if (author != null && author.trim().isNotEmpty) '($author)',
      [
        lines.first,
        for (final line in lines.skip(1))
          if (line.isEmpty) line else '    $line',
      ].join('\n'),
    ].join(' ');

    // Word escribe un espacio después de la marca de la nota: si el texto ya
    // empieza con uno, no se agrega otro.
    final separator = text.isEmpty || text.startsWith(RegExp(r'\s')) ? '' : ' ';
    return '[^$label]:$separator$text';
  }
}

// ---------------------------------------------------------------------
// Símbolos
// ---------------------------------------------------------------------

/// El carácter de un `w:sym`: un símbolo insertado con una fuente propia.
///
/// Word guarda el código del carácter **en la fuente**, no en Unicode: en
/// Symbol, la "a" es una α. Los códigos de Symbol y los de Wingdings más
/// usados se traducen a su carácter Unicode; cualquier otro se guarda tal
/// cual viene, que es lo mismo que da Word al copiarlo. Antes el símbolo se
/// perdía (F22).
String _symbol(XmlElement symbol) {
  final code = int.tryParse(
    symbol.getAttribute('char', namespace: _w) ?? '',
    radix: 16,
  );
  if (code == null) return '';

  // Word suele escribir el código corrido a F000 —el área de uso privado—:
  // F061 es el 0x61 de la fuente.
  final byte = code >= 0xF000 && code <= 0xF0FF ? code - 0xF000 : code;
  final font = symbol.getAttribute('font', namespace: _w)?.toLowerCase();

  final mapped = switch (font) {
    'symbol' => _symbolFont[byte] ?? (_isSymbolAscii(byte) ? byte : null),
    'wingdings' => _wingdingsFont[byte],
    _ => null,
  };
  final character = mapped ?? code;
  // Un código que no es un carácter —fuera de Unicode, como `FFFFFFFF`, o
  // medio par sustituto— hacía lanzar `String.fromCharCode` y se llevaba el
  // documento entero. Queda el carácter de reemplazo en su lugar (F22).
  if (character > 0x10FFFF || (character >= 0xD800 && character <= 0xDFFF)) {
    return '�';
  }
  return String.fromCharCode(character);
}

/// Los códigos de Symbol que coinciden con ASCII: dígitos y la puntuación
/// que la fuente no reemplaza.
bool _isSymbolAscii(int byte) =>
    byte >= 0x20 && byte < 0x7F && !_symbolFont.containsKey(byte);

/// La fuente Symbol en Unicode: lo que difiere de ASCII.
// dart format off
const _symbolFont = <int, int>{
  0x22: 0x2200, 0x24: 0x2203, 0x27: 0x220B, 0x2A: 0x2217, 0x2D: 0x2212,
  0x40: 0x2245, 0x41: 0x0391, 0x42: 0x0392, 0x43: 0x03A7, 0x44: 0x0394,
  0x45: 0x0395, 0x46: 0x03A6, 0x47: 0x0393, 0x48: 0x0397, 0x49: 0x0399,
  0x4A: 0x03D1, 0x4B: 0x039A, 0x4C: 0x039B, 0x4D: 0x039C, 0x4E: 0x039D,
  0x4F: 0x039F, 0x50: 0x03A0, 0x51: 0x0398, 0x52: 0x03A1, 0x53: 0x03A3,
  0x54: 0x03A4, 0x55: 0x03A5, 0x56: 0x03C2, 0x57: 0x03A9, 0x58: 0x039E,
  0x59: 0x03A8, 0x5A: 0x0396, 0x5C: 0x2234, 0x5E: 0x22A5, 0x60: 0x203E,
  0x61: 0x03B1, 0x62: 0x03B2, 0x63: 0x03C7, 0x64: 0x03B4, 0x65: 0x03B5,
  0x66: 0x03C6, 0x67: 0x03B3, 0x68: 0x03B7, 0x69: 0x03B9, 0x6A: 0x03D5,
  0x6B: 0x03BA, 0x6C: 0x03BB, 0x6D: 0x03BC, 0x6E: 0x03BD, 0x6F: 0x03BF,
  0x70: 0x03C0, 0x71: 0x03B8, 0x72: 0x03C1, 0x73: 0x03C3, 0x74: 0x03C4,
  0x75: 0x03C5, 0x76: 0x03D6, 0x77: 0x03C9, 0x78: 0x03BE, 0x79: 0x03C8,
  0x7A: 0x03B6, 0x7E: 0x223C,
  0xA0: 0x20AC, 0xA1: 0x03D2, 0xA2: 0x2032, 0xA3: 0x2264, 0xA4: 0x2044,
  0xA5: 0x221E, 0xA6: 0x0192, 0xA7: 0x2663, 0xA8: 0x2666, 0xA9: 0x2665,
  0xAA: 0x2660, 0xAB: 0x2194, 0xAC: 0x2190, 0xAD: 0x2191, 0xAE: 0x2192,
  0xAF: 0x2193, 0xB0: 0x00B0, 0xB1: 0x00B1, 0xB2: 0x2033, 0xB3: 0x2265,
  0xB4: 0x00D7, 0xB5: 0x221D, 0xB6: 0x2202, 0xB7: 0x2022, 0xB8: 0x00F7,
  0xB9: 0x2260, 0xBA: 0x2261, 0xBB: 0x2248, 0xBC: 0x2026, 0xBD: 0x23D0,
  0xBE: 0x23AF, 0xBF: 0x21B5, 0xC0: 0x2135, 0xC1: 0x2111, 0xC2: 0x211C,
  0xC3: 0x2118, 0xC4: 0x2297, 0xC5: 0x2295, 0xC6: 0x2205, 0xC7: 0x2229,
  0xC8: 0x222A, 0xC9: 0x2283, 0xCA: 0x2287, 0xCB: 0x2284, 0xCC: 0x2282,
  0xCD: 0x2286, 0xCE: 0x2208, 0xCF: 0x2209, 0xD0: 0x2220, 0xD1: 0x2207,
  0xD2: 0x00AE, 0xD3: 0x00A9, 0xD4: 0x2122, 0xD5: 0x220F, 0xD6: 0x221A,
  0xD7: 0x22C5, 0xD8: 0x00AC, 0xD9: 0x2227, 0xDA: 0x2228, 0xDB: 0x21D4,
  0xDC: 0x21D0, 0xDD: 0x21D1, 0xDE: 0x21D2, 0xDF: 0x21D3, 0xE0: 0x25CA,
  0xE1: 0x2329, 0xE2: 0x00AE, 0xE3: 0x00A9, 0xE4: 0x2122, 0xE5: 0x2211,
  0xE6: 0x239B, 0xE7: 0x239C, 0xE8: 0x239D, 0xE9: 0x23A1, 0xEA: 0x23A2,
  0xEB: 0x23A3, 0xEC: 0x23A7, 0xED: 0x23A8, 0xEE: 0x23A9, 0xEF: 0x23AA,
  0xF1: 0x232A, 0xF2: 0x222B, 0xF3: 0x2320, 0xF4: 0x23AE, 0xF5: 0x2321,
  0xF6: 0x239E, 0xF7: 0x239F, 0xF8: 0x23A0, 0xF9: 0x23A4, 0xFA: 0x23A5,
  0xFB: 0x23A6, 0xFC: 0x23AB, 0xFD: 0x23AC, 0xFE: 0x23AD,
};
// dart format on

/// Los símbolos de Wingdings que Word ofrece de fábrica para viñetas y
/// casillas. El resto no tiene un equivalente seguro y queda con su código.
// dart format off
const _wingdingsFont = <int, int>{
  0x4A: 0x263A, 0x4C: 0x2639, 0x6C: 0x25CF, 0x6E: 0x25A0, 0x6F: 0x25A1,
  0x71: 0x2751, 0x76: 0x2756, 0xA7: 0x25AA, 0xD8: 0x27A2, 0xFB: 0x2718,
  0xFC: 0x2714, 0xFD: 0x2612, 0xFE: 0x2611,
};
// dart format on

// ---------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------

/// Los hijos de [parent], con los envoltorios abiertos.
///
/// Un control de contenido (`w:sdt`), un XML personalizado, un hipervínculo
/// o una inserción con control de cambios no son contenido: envuelven
/// párrafos, filas, celdas o pedazos de texto que sí lo son. Y de un
/// `mc:AlternateContent` —dos versiones del mismo dibujo, para programas
/// nuevos y viejos— se lee **una**: la primera opción, o la de respaldo si
/// no hay otra.
Iterable<XmlElement> _unwrap(XmlElement parent) sync* {
  for (final child in parent.childElements) {
    final name = child.name;
    if (name.namespaceUri == _mc && name.local == 'AlternateContent') {
      final chosen =
          child.getElement('Choice', namespace: _mc) ??
          child.getElement('Fallback', namespace: _mc);
      if (chosen != null) yield* _unwrap(chosen);
    } else if (name.namespaceUri == _w && name.local == 'sdt') {
      final content = child.getElement('sdtContent', namespace: _w);
      if (content != null) yield* _unwrap(content);
    } else if (name.namespaceUri == _w && _wrappers.contains(name.local)) {
      yield* _unwrap(child);
    } else {
      yield child;
    }
  }
}

const _wrappers = {
  'customXml',
  'smartTag',
  'hyperlink',
  'ins',
  'moveTo',
  'fldSimple',
  'dir',
  'bdo',
};

/// Si un atributo booleano de [properties] está puesto.
///
/// En OOXML, `<w:b/>` significa activado y `<w:b w:val="0"/>` desactivado.
/// Mirar solo si la etiqueta existe pondría en negrita el texto que el
/// usuario **des**activó a mano.
bool _isEnabled(XmlElement properties, String name) {
  final element = properties.getElement(name, namespace: _w);
  if (element == null) return false;

  final value = _val(element);
  return value == null || value == '1' || value == 'true' || value == 'on';
}

String? _val(XmlElement? element) =>
    element?.getAttribute('val', namespace: _w);

String? _styleId(XmlElement properties) =>
    _val(properties.getElement('pStyle', namespace: _w));

XmlDocument _parseXml(String source) {
  try {
    return XmlDocument.parse(source);
  } on XmlException catch (e) {
    throw UnreadableDocumentException(FileFormat.docx, 'XML ilegible: $e');
  }
}

/// Cómo se escribe un salto de línea sin párrafo nuevo: dos espacios y un
/// salto, el de Markdown.
const _markdownBreak = '  \n';

/// El salto de línea dentro de una celda de tabla, donde un salto de verdad
/// partiría la fila.
const _cellBreak = '<br>';

/// El espacio de nombres del formato de Word. Se compara contra él en vez de
/// contra el prefijo `w:` porque el prefijo lo elige quien escribe el archivo
/// y puede ser cualquier otro.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// El de las relaciones de una parte: con él se nombran los encabezados.
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// El del archivo de relaciones (`.rels`) en sí.
const _rel = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// Markup Compatibility: el de `mc:AlternateContent`.
const _mc = 'http://schemas.openxmlformats.org/markup-compatibility/2006';

/// Dublin Core, el vocabulario de los metadatos.
const _dc = 'http://purl.org/dc/elements/1.1/';

/// Las ecuaciones (OMML).
const _m = 'http://schemas.openxmlformats.org/officeDocument/2006/math';

/// DrawingML: el texto de los dibujos, los SmartArt y los gráficos (`a:t`).
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

/// Los SmartArt (`dgm:relIds`).
const _dgm = 'http://schemas.openxmlformats.org/drawingml/2006/diagram';

/// Los gráficos (`c:chart`).
const _c = 'http://schemas.openxmlformats.org/drawingml/2006/chart';

/// Los gráficos de los tipos nuevos de Office 2016 (`cx:chart`).
const _cx = 'http://schemas.microsoft.com/office/drawing/2014/chartex';
