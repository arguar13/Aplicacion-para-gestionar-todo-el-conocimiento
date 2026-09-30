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
      markdown: _DocxReader(archive, body).toMarkdown(),
      title: metadata.title,
      author: metadata.author,
    );
  }

  // -------------------------------------------------------------------
  // Metadatos
  // -------------------------------------------------------------------

  ({String? title, String? author}) _readMetadata(Archive archive) {
    final root = _optionalXml(archive, 'docProps/core.xml');
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
}

/// Recorre un documento ya abierto y arma su Markdown.
///
/// Es un objeto por lectura, y no métodos sueltos de [DocxParser], porque la
/// numeración y las notas son **estado del documento entero**: el "3." de
/// una lista depende de los dos párrafos numerados anteriores, estén donde
/// estén, y la nota `[^4]` es la cuarta que apareció.
class _DocxReader {
  _DocxReader(this._archive, this._body)
    : _numbering = _Numbering(
        _optionalXml(_archive, 'word/numbering.xml'),
        _optionalXml(_archive, 'word/styles.xml'),
      ),
      _footnotes = _Notes(
        _optionalXml(_archive, 'word/footnotes.xml'),
        'footnote',
        (n) => '$n',
      ),
      _endnotes = _Notes(
        _optionalXml(_archive, 'word/endnotes.xml'),
        'endnote',
        (n) => _roman(n).toLowerCase(),
      ),
      _comments = _Notes(
        _optionalXml(_archive, 'word/comments.xml'),
        'comment',
        (n) => 'c$n',
      );

  final Archive _archive;
  final XmlElement _body;
  final _Numbering _numbering;
  final _Notes _footnotes;
  final _Notes _endnotes;
  final _Notes _comments;

  String toMarkdown() {
    // El orden de lectura importa: el cuerpo primero, para que las notas y
    // las listas se numeren como en la página. Los encabezados y pies se
    // leen después aunque se escriban arriba y abajo.
    final body = _blocks(_body).join('\n\n');
    final headers = _headersOrFooters('header');
    final footers = _headersOrFooters('footer');

    return [
      if (headers.isNotEmpty) ...[...headers, '---'],
      if (body.isNotEmpty) body,
      if (footers.isNotEmpty) ...['---', ...footers],
      ..._footnotes.definitions(_blocks),
      ..._endnotes.definitions(_blocks),
      ..._comments.definitions(_blocks),
    ].join('\n\n');
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
      }
    }

    return blocks;
  }

  /// Un párrafo, seguido de los cuadros de texto que tenga anclados.
  ///
  /// Un cuadro de texto vive dentro de un pedazo del párrafo, pero es otro
  /// texto con sus propios párrafos: pegado en el medio de la frase quedaba
  /// ilegible y sin separación. Va como bloques propios, a continuación.
  List<String> _paragraph(XmlElement paragraph, {required bool inTable}) {
    final properties = paragraph.getElement('pPr', namespace: _w);
    // La numeración avanza aunque el párrafo esté vacío: Word también le da
    // su número, y el siguiente sale "3." y no "2.".
    final item = _numbering.next(properties);

    final line = _Line(inTable: inTable);
    final textBoxes = <String>[];
    _inline(paragraph, line, textBoxes);

    final text = line.toMarkdown();
    return [
      // Los párrafos vacíos no se guardan: Word los usa para espaciar, y
      // en Markdown serían saltos que no dicen nada. Lo que sí se guarda
      // entero es el texto: la sangría de adelante —una tabulación, unos
      // espacios— es del original, y no se recorta (F22).
      if (text.trim().isNotEmpty)
        _withStructure(text, properties, item, inTable: inTable),
      ...textBoxes,
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
      return '${'#' * heading} ${item?.bullet ?? false ? '' : label}$text';
    }

    if (item == null || label.isEmpty) return text;
    final indent = inTable ? '' : '  ' * item.level;
    return '$indent$label$text';
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
    // `outlineLvl` cuenta desde cero: el 0 es un encabezado de nivel 1.
    return level == null ? null : (level + 1).clamp(1, 6);
  }

  // -------------------------------------------------------------------
  // Texto de un párrafo
  // -------------------------------------------------------------------

  /// Junta el texto de [parent] en [line], y los cuadros de texto que
  /// aparezcan en [textBoxes].
  ///
  /// Se recorre el árbol a mano, en vez de buscar todos los `w:t` que haya
  /// abajo, porque no todo lo que hay abajo es texto de este párrafo: un
  /// cuadro de texto trae sus propios párrafos, y las dos versiones de un
  /// `mc:AlternateContent` traen **el mismo** texto dos veces —se leían las
  /// dos y el cuadro salía duplicado (F22)—.
  void _inline(XmlElement parent, _Line line, List<String> textBoxes) {
    for (final node in _unwrap(parent)) {
      if (node.name.namespaceUri != _w) continue;

      switch (node.name.local) {
        case 'r':
          _run(node, line, textBoxes);
        // Las propiedades no son texto; lo borrado con control de cambios
        // no está en el documento que se ve.
        case 'pPr' || 'rPr' || 'del' || 'moveFrom':
          break;
        default:
          _inline(node, line, textBoxes);
      }
    }
  }

  void _run(XmlElement run, _Line line, List<String> textBoxes) {
    final properties = run.getElement('rPr', namespace: _w);
    final bold = properties != null && _isEnabled(properties, 'b');
    final italic = properties != null && _isEnabled(properties, 'i');

    void text(String value) => line.add(value, bold: bold, italic: italic);

    for (final node in _unwrap(run)) {
      if (node.name.namespaceUri != _w) {
        textBoxes.addAll(_textBoxes(node, inTable: line.inTable));
        continue;
      }

      switch (node.name.local) {
        case 't':
          text(node.innerText);
        case 'tab' || 'ptab':
          line.add('\t');
        // `w:cr` es el retorno de carro de Word: el mismo salto de línea que
        // `w:br`, sin abrir párrafo.
        case 'br' || 'cr':
          line.add(line.lineBreak);
        // El guion que no se corta a fin de línea: "e‑mail". Sin esto el
        // guion desaparecía y quedaba "email" (F22).
        case 'noBreakHyphen':
          text('\u2011');
        // El guion opcional: invisible salvo que Word corte la palabra ahí.
        // Es un carácter del original y se guarda como tal.
        case 'softHyphen':
          text('\u00AD');
        case 'sym':
          text(_symbol(node));
        case 'footnoteReference':
          line.add(_footnotes.marker(node));
        case 'endnoteReference':
          line.add(_endnotes.marker(node));
        case 'commentReference':
          line.add(_comments.marker(node));
        case 'drawing' || 'pict' || 'object':
          textBoxes.addAll(_textBoxes(node, inTable: line.inTable));
      }
    }
  }

  /// Los párrafos de los cuadros de texto que haya dentro de [node].
  List<String> _textBoxes(XmlElement node, {required bool inTable}) {
    final blocks = <String>[];
    for (final child in _unwrap(node)) {
      if (child.name.namespaceUri == _w && child.name.local == 'txbxContent') {
        blocks.addAll(_blocks(child, inTable: inTable));
      } else {
        blocks.addAll(_textBoxes(child, inTable: inTable));
      }
    }
    return blocks;
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
        [
          // La única alteración del texto que se admite, y solo acá: una
          // `|` dentro de una celda partiría la fila en una columna de más,
          // así que se escapa como `\|`, que es como Markdown la muestra.
          for (final cell in _cells(row))
            _cellText(cell).replaceAll('|', r'\|'),
        ],
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
    for (final row in _rows(table))
      [for (final cell in _cells(row)) _cellText(cell)].join(' | '),
  ].where((row) => row.trim().isNotEmpty).join(_cellBreak);

  /// El texto de una celda, con sus párrafos separados por `<br>`.
  ///
  /// Un salto de línea de verdad partiría la fila de la tabla de Markdown en
  /// dos. `<br>` es el salto que las tablas de Markdown aceptan: antes los
  /// párrafos de una celda se pegaban con un espacio y no se distinguían
  /// (F22).
  String _cellText(XmlElement cell) =>
      _blocks(cell, inTable: true).join(_cellBreak);

  Iterable<XmlElement> _rows(XmlElement table) => _unwrap(
    table,
  ).where((node) => node.name.namespaceUri == _w && node.name.local == 'tr');

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
  /// secciones y el mismo pie lo repetiría diez veces; se guarda una.
  List<String> _headersOrFooters(String kind) {
    final parts = _relationshipTargets();
    final settings = _optionalXml(_archive, 'word/settings.xml');
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

        final part = parts[reference.getAttribute('id', namespace: _r)];
        final root = part == null ? null : _optionalXml(_archive, part);
        if (root == null) continue;

        final text = _blocks(root).join('\n\n');
        if (text.trim().isNotEmpty && seen.add(text)) texts.add(text);
      }
    }
    return texts;
  }

  /// A qué parte del ZIP apunta cada relación del documento.
  Map<String, String> _relationshipTargets() {
    final rels = _optionalXml(_archive, 'word/_rels/document.xml.rels');
    if (rels == null) return const {};

    return {
      for (final relation in rels.findElements('Relationship', namespace: _rel))
        if (relation.getAttribute('Id') case final id?)
          if (relation.getAttribute('Target') case final target?)
            id: target.startsWith('/') ? target.substring(1) : 'word/$target',
    };
  }
}

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

  void add(String text, {bool bold = false, bool italic = false}) {
    if (text.isEmpty) return;

    final last = _pieces.lastOrNull;
    if (last != null && last.bold == bold && last.italic == italic) {
      _pieces.last = (text: last.text + text, bold: bold, italic: italic);
    } else {
      _pieces.add((text: text, bold: bold, italic: italic));
    }
  }

  String toMarkdown() => _pieces.map(_decorate).join();

  static String _decorate(_Piece piece) {
    final text = piece.text;
    if (!piece.bold && !piece.italic) return text;

    // Los espacios de los bordes van **afuera** de las marcas: `** texto **`
    // no es negrita en Markdown, es un asterisco literal.
    final leading = RegExp(r'^\s*').firstMatch(text)!.group(0)!;
    final trailing = RegExp(r'\s*$').firstMatch(text)!.group(0)!;
    if (leading.length == text.length) return text;
    final core = text.substring(leading.length, text.length - trailing.length);

    var marked = core;
    if (piece.italic) marked = '*$marked*';
    if (piece.bold) marked = '**$marked**';

    return '$leading$marked$trailing';
  }
}

typedef _Piece = ({String text, bool bold, bool italic});

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
        if (id != null) _abstracts[id] = _levels(abstract);
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

  final _abstracts = <String, Map<int, _Level>>{};
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
    final levels = num == null ? null : _abstracts[num.abstractId];
    // Sin definición —un documento a medio armar, o sin numbering.xml— no
    // hay número que calcular: queda como viñeta, como siempre.
    if (num == null || levels == null) {
      return _ListItem(level: level ?? 0, bullet: true);
    }

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

    final counters = _counters.putIfAbsent(num.abstractId, () => {});
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
  _Notes(XmlElement? part, String element, this._label) {
    if (part == null) return;
    for (final note in part.findElements(element, namespace: _w)) {
      final id = note.getAttribute('id', namespace: _w);
      if (id != null) _parts[id] = note;
    }
  }

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
  return String.fromCharCode(mapped ?? code);
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

/// La raíz de una parte que puede faltar o venir rota —metadatos, estilos,
/// notas, encabezados—: el documento se lee igual sin ella.
XmlElement? _optionalXml(Archive archive, String name) {
  final xml = _textEntry(archive, name);
  if (xml == null) return null;
  try {
    return XmlDocument.parse(xml).rootElement;
  } on XmlException {
    return null;
  }
}

String? _textEntry(Archive archive, String name) {
  final file = archive.files.where((f) => f.name == name).firstOrNull;
  if (file == null) return null;

  // `utf8.decode` con `allowMalformed`: un byte suelto corrupto en medio de
  // un documento de cien páginas no puede costar las otras noventa y nueve.
  return utf8.decode(file.readBytes() ?? const [], allowMalformed: true);
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
