import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/mark_locator.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:xml/xml.dart';

/// Marca tramos en un Word (`.docx`) y lo devuelve como el mismo documento
/// (F38): el resumen, la síntesis o las palabras clave de F36, o los
/// resaltados de la persona, pintados en el cuerpo del texto.
///
/// **Cómo se marca.** Cada tramo se parte en los `w:r` (runs) donde empieza
/// y termina, conservando el `w:rPr` de cada uno —la fuente, la negrita, el
/// tamaño—, y a los runs del tramo se les agrega:
///
/// - **fondo** ([HighlightStyle.fill]): `w:shd w:val="clear" w:fill="RRGGBB"`.
///   `w:highlight`, el resaltador de Word, solo admite 16 colores con nombre
///   —amarillo, verde, turquesa…—, y ninguno es el color exacto que la
///   persona eligió o que F36 usa en pantalla. El sombreado del carácter
///   admite cualquier color y se ve igual en Word, LibreOffice y Google
///   Docs. A cambio se borra el `w:highlight` que el run ya tuviera: Word lo
///   pinta por encima del sombreado y taparía el color. Un color con
///   transparencia se mezcla con el blanco del papel, porque el sombreado
///   es opaco.
/// - **subrayado** ([HighlightStyle.underline]): `w:u w:val="single"
///   w:color="RRGGBB"`, con el color exacto de la línea.
///
/// **Dónde está cada tramo.** Las posiciones de [DocumentMark] son del texto
/// extraído, que es Markdown armado a partir del Word y no coincide con el
/// texto del archivo. Se ubican por las letras y números, no por posición:
/// ver [locateMarks]. El texto que se recorre es el de los `w:t` del cuerpo
/// (`word/document.xml` o la parte que nombre la relación `officeDocument`),
/// en el orden del documento, incluidas las tablas y los cuadros de texto; no
/// el de los encabezados, los pies ni las notas al pie, que no se marcan.
/// Un tramo que no se encuentra se saltea.
///
/// **Si dos tramos se pisan**, gana el que viene después en la lista: quien
/// llama pone al final lo que debe quedar por encima.
///
/// **Notas.** La nota de un tramo va como comentario de Word: queda en
/// `word/comments.xml` —se arma o se le agrega a la que ya había—, con su
/// relación y su tipo de contenido, y en el cuerpo un rango que abarca el
/// tramo. Es lo que Word, LibreOffice y Google Docs muestran en el margen.
///
/// Lo que no cambia queda **tal cual**: las demás entradas del ZIP se
/// copian con sus bytes comprimidos sin tocar. Cambian el cuerpo y, si hubo
/// notas, los comentarios, las relaciones del cuerpo y los tipos de
/// contenido.
class DocxMarkWriter {
  const DocxMarkWriter();

  /// El Word [docx] con [marks] marcados. [text] es el texto extraído al que
  /// se refieren las posiciones de [marks].
  ///
  /// Se hace en otro isolate: descomprimir y recorrer el XML de un documento
  /// de cientos de páginas congelaría la interfaz, igual que al leerlo.
  ///
  /// Lanza si [docx] no es un Word legible (un ZIP roto, un cuerpo sin XML).
  Future<Uint8List> write({
    required Uint8List docx,
    required String text,
    required List<DocumentMark> marks,
  }) {
    if (marks.isEmpty) return Future.value(docx);
    return Isolate.run(() => writeSync(docx: docx, text: text, marks: marks));
  }

  /// Lo mismo que [write], en este hilo.
  Uint8List writeSync({
    required Uint8List docx,
    required String text,
    required List<DocumentMark> marks,
  }) {
    if (marks.isEmpty) return docx;
    final archive = ZipDecoder().decodeBytes(docx);
    final parts = _Parts(archive);

    final documentPart = parts.documentPart;
    final documentBytes = parts.read(documentPart);
    if (documentBytes == null) {
      throw FormatException('El Word no trae la parte $documentPart');
    }
    final document = XmlDocument.parse(
      utf8.decode(documentBytes, allowMalformed: true),
    );
    final body = document.rootElement.childElements
        .where((e) => _isWord(e, 'body'))
        .firstOrNull;
    if (body == null) return docx;

    // 1. Los textos del cuerpo, en orden.
    final texts = <_Text>[];
    final haystack = StringBuffer();
    _collectTexts(body, texts, haystack);
    if (texts.isEmpty) return docx;
    final spans = locateMarks(
      haystack: haystack.toString(),
      extracted: text,
      marks: marks,
    );

    // 2. A quién le toca cada letra.
    final paint = Int32List(haystack.length)..fillRange(0, haystack.length, -1);
    var found = false;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      if (span == null) continue;
      paint.fillRange(span.start, span.end, i);
      found = true;
    }
    if (!found) return docx;

    // 3. Partir los runs y pintarlos.
    final marked = _markRuns(texts, paint, marks);
    if (marked == null) return docx;

    // 4. Las notas, como comentarios.
    final replaced = <String, Uint8List>{};
    final commentMarks = [
      for (final i in marked.runsByMark.keys)
        if ((marks[i].note ?? '').trim().isNotEmpty) i,
    ]..sort();
    if (commentMarks.isNotEmpty) {
      _addComments(
        parts: parts,
        document: document,
        prefix: marked.prefix,
        marks: marks,
        commentMarks: commentMarks,
        runsByMark: marked.runsByMark,
        replaced: replaced,
      );
    }
    replaced[parts.key(documentPart)] = Uint8List.fromList(
      utf8.encode(document.toXmlString()),
    );

    return parts.rebuild(docx, replaced);
  }
}

// ---------------------------------------------------------------------
// Los textos del cuerpo
// ---------------------------------------------------------------------

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _mc = 'http://schemas.openxmlformats.org/markup-compatibility/2006';
const _declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const _rels = 'http://schemas.openxmlformats.org/package/2006/relationships';

bool _isWord(XmlElement e, String local) =>
    e.name.local == local && e.name.namespaceUri == _w;

/// Un `w:t` y dónde empieza su texto en el texto de todo el cuerpo.
class _Text {
  _Text(this.element, this.start, this.text);

  final XmlElement element;
  final int start;
  final String text;
}

void _collectTexts(XmlElement parent, List<_Text> into, StringBuffer all) {
  for (final child in parent.childElements) {
    if (_isWord(child, 't')) {
      final text = child.innerText;
      into.add(_Text(child, all.length, text));
      all.write(text);
    } else if (child.name.local == 'Fallback' &&
        child.name.namespaceUri == _mc) {
      // Un cuadro de texto viene dos veces —la versión nueva y la de
      // respaldo para lectores viejos—: con una alcanza.
      continue;
    } else {
      _collectTexts(child, into, all);
    }
  }
}

// ---------------------------------------------------------------------
// Partir los runs
// ---------------------------------------------------------------------

/// Un tramo de un run con un mismo destino: sin marca ([mark] `-1`) o de una.
class _Piece {
  _Piece(this.mark);

  final int mark;
  final nodes = <XmlNode>[];
}

({String prefix, Map<int, ({XmlElement first, XmlElement last})> runsByMark})?
_markRuns(List<_Text> texts, Int32List paint, List<DocumentMark> marks) {
  // Los runs (el padre directo de un w:t) con algo pintado, en orden del
  // documento.
  final seen = <XmlElement>{};
  final order = <XmlElement>[];
  for (final text in texts) {
    final run = text.element.parent;
    if (run is! XmlElement || !_isWord(run, 'r')) continue;
    var painted = false;
    for (var i = 0; i < text.text.length; i++) {
      if (paint[text.start + i] >= 0) {
        painted = true;
        break;
      }
    }
    if (painted && seen.add(run)) order.add(run);
  }
  if (order.isEmpty) return null;

  // Sin el prefijo del espacio de nombres no hay cómo escribir los
  // elementos nuevos: casi todos los Word usan `w`.
  final prefix = order.first.name.prefix;
  if (prefix == null) return null;

  final starts = {for (final text in texts) text.element: text};
  final firstOfMark = <int, ({int order, XmlElement run})>{};
  final lastOfMark = <int, ({int order, XmlElement run})>{};

  // De atrás para adelante: un run que contiene a otro (un cuadro de texto
  // dentro de un run) copia al de adentro ya cambiado.
  for (var runIndex = order.length - 1; runIndex >= 0; runIndex--) {
    final run = order[runIndex];
    final parent = run.parent;
    if (parent is! XmlElement) continue;

    final pieces = <_Piece>[];
    _Piece pieceFor(int mark) {
      if (pieces.isEmpty || pieces.last.mark != mark) pieces.add(_Piece(mark));
      return pieces.last;
    }

    XmlElement? originalProperties;
    for (final child in run.children) {
      if (child is XmlElement && _isWord(child, 'rPr')) {
        originalProperties = child;
        continue;
      }
      final text = child is XmlElement ? starts[child] : null;
      if (text == null) {
        // Una tabulación, un salto, una imagen: se queda con el trozo en que
        // va, sin abrir uno nuevo que partiría una marca en dos.
        (pieces.isEmpty ? pieceFor(-1) : pieces.last).nodes.add(child.copy());
        continue;
      }
      var i = 0;
      final length = text.text.length;
      while (i < length) {
        final mark = paint[text.start + i];
        var j = i + 1;
        while (j < length && paint[text.start + j] == mark) {
          j++;
        }
        pieceFor(
          mark,
        ).nodes.add(_textLike(text.element, text.text.substring(i, j)));
        i = j;
      }
    }

    final newRuns = <XmlElement>[];
    for (final piece in pieces) {
      final newRun = XmlElement(
        run.name.copy(),
        run.attributes.map((a) => a.copy()),
      );
      var properties = originalProperties?.copy();
      if (piece.mark >= 0) {
        properties ??= XmlElement(XmlName.fromString('$prefix:rPr'));
        _paintProperties(properties, prefix, marks[piece.mark]);
      }
      if (properties != null) newRun.children.add(properties);
      newRun.children.addAll(piece.nodes);
      newRuns.add(newRun);

      if (piece.mark >= 0) {
        final m = piece.mark;
        final first = firstOfMark[m];
        if (first == null || first.order > runIndex) {
          firstOfMark[m] = (order: runIndex, run: newRun);
        }
        final last = lastOfMark[m];
        if (last == null || last.order < runIndex) {
          lastOfMark[m] = (order: runIndex, run: newRun);
        }
      }
    }

    final at = parent.children.indexOf(run);
    parent.children
      ..removeAt(at)
      ..insertAll(at, newRuns);
  }

  return (
    prefix: prefix,
    runsByMark: {
      for (final MapEntry(key: m, value: first) in firstOfMark.entries)
        m: (first: first.run, last: lastOfMark[m]!.run),
    },
  );
}

/// Un `w:t` igual a [original] pero con [text]. Con `xml:space="preserve"`,
/// porque al partir un run los espacios quedan en los bordes y Word los
/// recortaría.
XmlElement _textLike(XmlElement original, String text) {
  final copy = original.copy()
    ..children.clear()
    ..children.add(XmlText(text));
  _preserveSpace(copy);
  return copy;
}

void _preserveSpace(XmlElement element) {
  element.attributes.removeWhere(
    (a) => a.name.prefix == 'xml' && a.name.local == 'space',
  );
  element.attributes.add(
    XmlAttribute(XmlName.fromString('xml:space'), 'preserve'),
  );
}

// ---------------------------------------------------------------------
// Las propiedades de un run marcado
// ---------------------------------------------------------------------

/// El orden en que el esquema de Word manda los hijos de `w:rPr`: Word se
/// queja de un archivo con el sombreado antes del tamaño.
const _rPrOrder = [
  'rStyle',
  'rFonts',
  'b',
  'bCs',
  'i',
  'iCs',
  'caps',
  'smallCaps',
  'strike',
  'dstrike',
  'outline',
  'shadow',
  'emboss',
  'imprint',
  'noProof',
  'snapToGrid',
  'vanish',
  'webHidden',
  'color',
  'spacing',
  'w',
  'kern',
  'position',
  'sz',
  'szCs',
  'highlight',
  'u',
  'effect',
  'bdr',
  'shd',
  'fitText',
  'vertAlign',
  'rtl',
  'cs',
  'em',
  'lang',
  'eastAsianLayout',
  'specVanish',
  'oMath',
];

void _paintProperties(XmlElement rPr, String prefix, DocumentMark mark) {
  switch (mark.style) {
    case HighlightStyle.fill:
      _remove(rPr, prefix, 'highlight');
      _remove(rPr, prefix, 'shd');
      _insertOrdered(rPr, prefix, 'shd', {
        'val': 'clear',
        'color': 'auto',
        'fill': _fillHex(mark.color),
      });
    case HighlightStyle.underline:
      _remove(rPr, prefix, 'u');
      _insertOrdered(rPr, prefix, 'u', {
        'val': 'single',
        'color': _rgbHex(mark.color),
      });
  }
}

/// Los hijos de `rPr` se comparan por nombre y no por espacio de nombres: un
/// `rPr` copiado queda suelto del documento y no sabe a cuál pertenece.
void _remove(XmlElement rPr, String prefix, String local) {
  rPr.children.removeWhere(
    (c) => c is XmlElement && c.name.local == local && c.name.prefix == prefix,
  );
}

void _insertOrdered(
  XmlElement rPr,
  String prefix,
  String local,
  Map<String, String> attributes,
) {
  final element = XmlElement(XmlName.fromString('$prefix:$local'), [
    for (final MapEntry(:key, :value) in attributes.entries)
      XmlAttribute(XmlName.fromString('$prefix:$key'), value),
  ]);
  final rank = _rPrOrder.indexOf(local);
  var at = rPr.children.length;
  for (var i = 0; i < rPr.children.length; i++) {
    final child = rPr.children[i];
    if (child is! XmlElement) continue;
    final childRank = _rPrOrder.indexOf(child.name.local);
    // Lo que no está en la lista —un cambio de formato registrado, una
    // extensión— va después de todo lo conocido.
    if (childRank < 0 || childRank > rank) {
      at = i;
      break;
    }
  }
  rPr.children.insert(at, element);
}

String _rgbHex(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// El color de un fondo, sobre el blanco del papel: el sombreado de Word es
/// opaco, y un color con transparencia se vería más oscuro de lo que es.
String _fillHex(int argb) {
  final alpha = (argb >>> 24) & 0xFF;
  int over(int channel) =>
      ((channel * alpha + 255 * (255 - alpha)) / 255).round().clamp(0, 255);
  final r = over((argb >>> 16) & 0xFF);
  final g = over((argb >>> 8) & 0xFF);
  final b = over(argb & 0xFF);
  return ((r << 16) | (g << 8) | b)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();
}

// ---------------------------------------------------------------------
// Comentarios
// ---------------------------------------------------------------------

const _commentsType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'comments';
const _commentsContentType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.'
    'comments+xml';

/// Quien firma los comentarios.
const _commentAuthor = 'Sinapsis';

void _addComments({
  required _Parts parts,
  required XmlDocument document,
  required String prefix,
  required List<DocumentMark> marks,
  required List<int> commentMarks,
  required Map<int, ({XmlElement first, XmlElement last})> runsByMark,
  required Map<String, Uint8List> replaced,
}) {
  final documentPart = parts.documentPart;
  final folder = _folderOf(documentPart);
  final relsName = '$folder/_rels/${documentPart.split('/').last}.rels'
      .replaceFirst(RegExp('^/'), '');

  // Las relaciones del cuerpo, y de ahí dónde están los comentarios.
  final relsBytes = parts.read(relsName);
  final rels = relsBytes == null
      ? XmlDocument.parse('$_declaration<Relationships xmlns="$_rels"/>')
      : XmlDocument.parse(utf8.decode(relsBytes, allowMalformed: true));
  final relsRoot = rels.rootElement;

  String? commentsPart;
  for (final rel in relsRoot.childElements) {
    final type = rel.getAttribute('Type') ?? '';
    if (type == _commentsType) {
      commentsPart = _resolve(folder, rel.getAttribute('Target') ?? '');
      break;
    }
  }
  var newRelationship = false;
  if (commentsPart == null) {
    commentsPart = _join(folder, 'comments.xml');
    var highest = 0;
    for (final rel in relsRoot.childElements) {
      final id = RegExp(r'^rId(\d+)$').firstMatch(rel.getAttribute('Id') ?? '');
      if (id != null) {
        final n = int.parse(id.group(1)!);
        if (n > highest) highest = n;
      }
    }
    relsRoot.children.add(
      XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), 'rId${highest + 1}'),
        XmlAttribute(XmlName('Type'), _commentsType),
        XmlAttribute(XmlName('Target'), 'comments.xml'),
      ]),
    );
    newRelationship = true;
  }

  // El archivo de comentarios: el que había, o uno nuevo.
  final existing = parts.read(commentsPart);
  final comments = existing == null
      ? XmlDocument.parse('$_declaration<w:comments xmlns:w="$_w"/>')
      : XmlDocument.parse(utf8.decode(existing, allowMalformed: true));
  final commentsRoot = comments.rootElement;
  final commentPrefix = commentsRoot.name.prefix ?? prefix;

  // Los números de comentario que ya existen no se repiten.
  var nextId = 0;
  void takeMax(XmlNode node) {
    for (final e in node.descendantElements) {
      if (e.name.namespaceUri != _w) continue;
      final id = int.tryParse(e.getAttribute('id', namespace: _w) ?? '');
      if (id != null && id >= nextId) nextId = id + 1;
    }
  }

  takeMax(commentsRoot);
  for (final e in document.rootElement.descendantElements) {
    if (e.name.local.startsWith('comment') && e.name.namespaceUri == _w) {
      final id = int.tryParse(e.getAttribute('id', namespace: _w) ?? '');
      if (id != null && id >= nextId) nextId = id + 1;
    }
  }

  XmlElement w(String ns, String local, [Map<String, String>? attrs]) =>
      XmlElement(XmlName.fromString('$ns:$local'), [
        for (final MapEntry(:key, :value) in (attrs ?? const {}).entries)
          XmlAttribute(XmlName.fromString('$ns:$key'), value),
      ]);

  for (final m in commentMarks) {
    final runs = runsByMark[m]!;
    final id = '${nextId++}';

    // El comentario, un párrafo por renglón de la nota.
    final comment = w(commentPrefix, 'comment', {
      'id': id,
      'author': _commentAuthor,
      'initials': 'S',
    });
    for (final line in marks[m].note!.trim().split(RegExp(r'\r\n|\r|\n'))) {
      final text = w(commentPrefix, 't')
        ..attributes.add(
          XmlAttribute(XmlName.fromString('xml:space'), 'preserve'),
        )
        ..children.add(XmlText(line));
      comment.children.add(
        w(commentPrefix, 'p')
          ..children.add(w(commentPrefix, 'r')..children.add(text)),
      );
    }
    commentsRoot.children.add(comment);

    // En el cuerpo: el rango y la marca del comentario después del último
    // run.
    final last = runs.last;
    final lastParent = last.parent! as XmlElement;
    var at = lastParent.children.indexOf(last) + 1;
    lastParent.children.insertAll(at, [
      w(prefix, 'commentRangeEnd', {'id': id}),
      w(prefix, 'r')..children.add(w(prefix, 'commentReference', {'id': id})),
    ]);
    final first = runs.first;
    final firstParent = first.parent! as XmlElement;
    at = firstParent.children.indexOf(first);
    firstParent.children.insert(at, w(prefix, 'commentRangeStart', {'id': id}));
  }

  replaced[parts.key(commentsPart)] = Uint8List.fromList(
    utf8.encode(comments.toXmlString()),
  );
  if (newRelationship || relsBytes == null) {
    replaced[parts.key(relsName)] = Uint8List.fromList(
      utf8.encode(rels.toXmlString()),
    );
  }

  // El tipo de contenido de los comentarios, si no está dicho.
  final typesBytes = parts.read('[Content_Types].xml');
  if (typesBytes != null) {
    final types = XmlDocument.parse(
      utf8.decode(typesBytes, allowMalformed: true),
    );
    final partName = '/${commentsPart.replaceFirst(RegExp('^/'), '')}';
    final declared = types.rootElement.childElements.any(
      (e) =>
          e.name.local == 'Override' &&
          (e.getAttribute('PartName') ?? '').toLowerCase() ==
              partName.toLowerCase(),
    );
    if (!declared) {
      // Sin prefijo: hereda el espacio de nombres del documento.
      types.rootElement.children.add(
        XmlElement(XmlName('Override'), [
          XmlAttribute(XmlName('PartName'), partName),
          XmlAttribute(XmlName('ContentType'), _commentsContentType),
        ]),
      );
      replaced[parts.key('[Content_Types].xml')] = Uint8List.fromList(
        utf8.encode(types.toXmlString()),
      );
    }
  }
}

String _folderOf(String part) {
  final slash = part.lastIndexOf('/');
  return slash < 0 ? '' : part.substring(0, slash);
}

String _join(String folder, String name) =>
    folder.isEmpty ? name : '$folder/$name';

/// La parte a la que apunta [target] desde la carpeta [folder].
String _resolve(String folder, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = <String>[...folder.split('/').where((s) => s.isNotEmpty)];
  for (final segment in target.split('/')) {
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (segment != '.' && segment.isNotEmpty) {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

// ---------------------------------------------------------------------
// El paquete
// ---------------------------------------------------------------------

/// Las partes de un `.docx`. Los nombres no distinguen mayúsculas —así lo
/// dice el formato del paquete—.
class _Parts {
  _Parts(Archive archive)
    : _files = {
        for (final file in archive.files)
          if (file.isFile) _lower(file.name): file,
      };

  final Map<String, ArchiveFile> _files;

  static String _lower(String name) => name.toLowerCase();

  String key(String name) => _lower(name);

  Uint8List? read(String name) => _files[_lower(name)]?.readBytes();

  /// El cuerpo es la parte que la relación `officeDocument` del paquete
  /// nombra, no un nombre fijo, igual que al leerlo; `word/document.xml` es
  /// el respaldo para un paquete sin relaciones.
  late final String documentPart = _findDocumentPart();

  String _findDocumentPart() {
    final bytes = read('_rels/.rels');
    if (bytes != null) {
      try {
        final root = XmlDocument.parse(
          utf8.decode(bytes, allowMalformed: true),
        ).rootElement;
        for (final rel in root.childElements) {
          final type = rel.getAttribute('Type') ?? '';
          if (!type.endsWith('/officeDocument')) continue;
          final part = _resolve('', rel.getAttribute('Target') ?? '');
          if (_files.containsKey(_lower(part))) return part;
        }
      } on XmlException {
        // Se usa el nombre de siempre.
      }
    }
    return 'word/document.xml';
  }

  /// El mismo ZIP [docx] con las partes de [replaced] cambiadas y las que no
  /// existían agregadas al final. Las demás pasan con sus bytes comprimidos
  /// sin tocar.
  ///
  /// Se abre el ZIP de nuevo en vez de reusar el que se leyó: leer una
  /// entrada la descomprime y `archive` deja su flujo comprimido gastado, de
  /// modo que copiarla así sale rota.
  Uint8List rebuild(Uint8List docx, Map<String, Uint8List> replaced) {
    final original = ZipDecoder().decodeBytes(docx);
    final result = Archive();
    final done = <String>{};
    for (final file in original.files) {
      final name = _lower(file.name);
      final bytes = file.isFile ? replaced[name] : null;
      if (bytes == null) {
        result.add(file);
        continue;
      }
      done.add(name);
      result.add(_replacement(file, bytes));
    }
    for (final MapEntry(key: name, value: bytes) in replaced.entries) {
      if (done.contains(name)) continue;
      result.add(ArchiveFile.bytes(name, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(result));
  }

  ArchiveFile _replacement(ArchiveFile old, Uint8List bytes) {
    return ArchiveFile.bytes(old.name, bytes)
      ..mode = old.mode
      ..lastModTime = old.lastModTime;
  }
}
