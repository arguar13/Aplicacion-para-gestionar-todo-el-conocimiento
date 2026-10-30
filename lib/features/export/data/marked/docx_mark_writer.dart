import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/mark_locator.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
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
/// **Notas en el texto** (F45, mejora 19). Cada una es una nota al pie de
/// Word: la llamada —el número volado— va justo después del pedazo citado, y
/// lo que dice, en `word/footnotes.xml` —se arma o se le agrega a la que ya
/// había—, con su relación y su tipo de contenido. Word las numera solo, en el
/// orden del documento, y LibreOffice y Google Docs las leen igual. Se ubican
/// como los tramos, después de pintarlos: no son una capa de color, así que un
/// resaltado y una nota sobre el mismo pedazo conviven.
///
/// Lo que no cambia queda **tal cual**: las demás entradas del ZIP se
/// copian con sus bytes comprimidos sin tocar. Cambian el cuerpo y, si hubo
/// notas, los comentarios o las notas al pie, las relaciones del cuerpo y los
/// tipos de contenido.
class DocxMarkWriter {
  const DocxMarkWriter();

  /// El Word [docx] con [marks] marcados y [notes] como notas al pie. [text]
  /// es el texto extraído al que se refieren las posiciones de los dos.
  ///
  /// Se hace en otro isolate: descomprimir y recorrer el XML de un documento
  /// de cientos de páginas congelaría la interfaz, igual que al leerlo.
  ///
  /// Lanza si [docx] no es un Word legible (un ZIP roto, un cuerpo sin XML).
  Future<Uint8List> write({
    required Uint8List docx,
    required String text,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) {
    if (marks.isEmpty && notes.isEmpty) return Future.value(docx);
    return Isolate.run(
      () => writeSync(docx: docx, text: text, marks: marks, notes: notes),
    );
  }

  /// Lo mismo que [write], en este hilo.
  Uint8List writeSync({
    required Uint8List docx,
    required String text,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) {
    if (marks.isEmpty && notes.isEmpty) return docx;
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

    final replaced = <String, Uint8List>{};
    final painted =
        marks.isNotEmpty &&
        _paintMarks(
          parts: parts,
          document: document,
          body: body,
          text: text,
          marks: marks,
          replaced: replaced,
        );
    final noted =
        notes.isNotEmpty &&
        _addFootnotes(
          parts: parts,
          body: body,
          text: text,
          notes: notes,
          replaced: replaced,
        );
    if (!painted && !noted) return docx;
    replaced[parts.key(documentPart)] = Uint8List.fromList(
      utf8.encode(document.toXmlString()),
    );

    return parts.rebuild(docx, replaced);
  }
}

/// Pinta [marks] en el cuerpo [body] de [document] y escribe sus notas como
/// comentarios. Devuelve si pintó algo.
bool _paintMarks({
  required _Parts parts,
  required XmlDocument document,
  required XmlElement body,
  required String text,
  required List<DocumentMark> marks,
  required Map<String, Uint8List> replaced,
}) {
  // 1. Los textos del cuerpo, en orden.
  final texts = <_Text>[];
  final haystack = StringBuffer();
  _collectTexts(body, texts, haystack);
  if (texts.isEmpty) return false;
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
  if (!found) return false;

  // 3. Partir los runs y pintarlos.
  final marked = _markRuns(texts, paint, marks);
  if (marked == null) return false;

  // 4. Las notas, como comentarios.
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
  return true;
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
  final commentsPart = _relatedPart(
    parts: parts,
    replaced: replaced,
    type: _commentsType,
    contentType: _commentsContentType,
    fileName: 'comments.xml',
  );

  // El archivo de comentarios: el que había, o uno nuevo.
  final existing = _current(parts, replaced, commentsPart);
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

  for (final m in commentMarks) {
    final runs = runsByMark[m]!;
    final id = '${nextId++}';

    // El comentario, un párrafo por renglón de la nota.
    final comment = _w3(commentPrefix, 'comment', {
      'id': id,
      'author': _commentAuthor,
      'initials': 'S',
    });
    for (final line in _lines(marks[m].note!)) {
      comment.children.add(
        _w3(commentPrefix, 'p')
          ..children.add(
            _w3(commentPrefix, 'r')..children.add(_textOf(commentPrefix, line)),
          ),
      );
    }
    commentsRoot.children.add(comment);

    // En el cuerpo: el rango y la marca del comentario después del último
    // run.
    final last = runs.last;
    final lastParent = last.parent! as XmlElement;
    var at = lastParent.children.indexOf(last) + 1;
    lastParent.children.insertAll(at, [
      _w3(prefix, 'commentRangeEnd', {'id': id}),
      _w3(prefix, 'r')
        ..children.add(_w3(prefix, 'commentReference', {'id': id})),
    ]);
    final first = runs.first;
    final firstParent = first.parent! as XmlElement;
    at = firstParent.children.indexOf(first);
    firstParent.children.insert(
      at,
      _w3(prefix, 'commentRangeStart', {'id': id}),
    );
  }

  replaced[parts.key(commentsPart)] = Uint8List.fromList(
    utf8.encode(comments.toXmlString()),
  );
}

// ---------------------------------------------------------------------
// Notas al pie (F45, mejora 19)
// ---------------------------------------------------------------------

const _footnotesType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'footnotes';
const _footnotesContentType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.'
    'footnotes+xml';

/// Las notas al pie de un Word que no tenía: con los dos separadores que Word
/// espera —la raya entre el texto y las notas, y la de cuando una nota sigue
/// en la página siguiente—, con los ids -1 y 0 de siempre.
final _emptyFootnotes = [
  '$_declaration<w:footnotes xmlns:w="$_w">',
  '<w:footnote w:type="separator" w:id="-1">',
  '<w:p><w:r><w:separator/></w:r></w:p></w:footnote>',
  '<w:footnote w:type="continuationSeparator" w:id="0">',
  '<w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>',
  '</w:footnotes>',
].join();

/// Pone [notes] como notas al pie del cuerpo [body]: la llamada después de
/// su pedazo y lo que dicen en las notas al pie. Devuelve si puso alguna.
///
/// Se ubican después de pintar los tramos, sobre los textos de ahora —pintar
/// parte los runs pero no cambia una letra—, y se ponen de atrás para
/// adelante: partir el run de una deja en su lugar los textos de las de antes.
bool _addFootnotes({
  required _Parts parts,
  required XmlElement body,
  required String text,
  required List<DocumentNote> notes,
  required Map<String, Uint8List> replaced,
}) {
  final texts = <_Text>[];
  final haystack = StringBuffer();
  _collectTexts(body, texts, haystack);
  if (texts.isEmpty) return false;
  final spans = locateMarks(
    haystack: haystack.toString(),
    extracted: text,
    marks: [for (final note in notes) _asMark(note)],
  );
  // Las encontradas, por dónde termina su pedazo en el cuerpo.
  final found = [
    for (var i = 0; i < notes.length; i++)
      if (spans[i] case final span?) (note: notes[i], end: span.end),
  ]..sort((a, b) => a.end.compareTo(b.end));
  if (found.isEmpty) return false;
  final prefix = body.name.prefix;
  if (prefix == null) return false;

  final footnotesPart = _relatedPart(
    parts: parts,
    replaced: replaced,
    type: _footnotesType,
    contentType: _footnotesContentType,
    fileName: 'footnotes.xml',
  );
  final existing = _current(parts, replaced, footnotesPart);
  final footnotes = XmlDocument.parse(
    existing == null
        ? _emptyFootnotes
        : utf8.decode(existing, allowMalformed: true),
  );
  final footnotesRoot = footnotes.rootElement;
  final notePrefix = footnotesRoot.name.prefix ?? prefix;

  // Los ids que ya existen no se repiten; los de la persona, desde 1.
  var nextId = 1;
  for (final e in footnotesRoot.descendantElements) {
    if (e.name.namespaceUri != _w || e.name.local != 'footnote') continue;
    final id = int.tryParse(e.getAttribute('id', namespace: _w) ?? '');
    if (id != null && id >= nextId) nextId = id + 1;
  }
  final ids = [for (var i = 0; i < found.length; i++) nextId + i];

  // La nota, un párrafo por renglón; el primero, con su número.
  for (var i = 0; i < found.length; i++) {
    final footnote = _w3(notePrefix, 'footnote', {'id': '${ids[i]}'});
    final lines = _lines(found[i].note.note);
    for (var l = 0; l < lines.length; l++) {
      final paragraph = _w3(notePrefix, 'p');
      if (l == 0) {
        paragraph.children.add(
          _w3(notePrefix, 'r')
            ..children.addAll([
              _superscript(notePrefix),
              _w3(notePrefix, 'footnoteRef'),
            ]),
        );
      }
      paragraph.children.add(
        _w3(notePrefix, 'r')
          ..children.add(
            _textOf(notePrefix, l == 0 ? ' ${lines[l]}' : lines[l]),
          ),
      );
      footnote.children.add(paragraph);
    }
    footnotesRoot.children.add(footnote);
  }

  // La llamada, de atrás para adelante.
  for (var i = found.length - 1; i >= 0; i--) {
    _insertReference(texts, found[i].end, prefix, ids[i]);
  }

  replaced[parts.key(footnotesPart)] = Uint8List.fromList(
    utf8.encode(footnotes.toXmlString()),
  );
  return true;
}

/// El pedazo de [note] como un tramo, para ubicarlo como se ubican todos.
DocumentMark _asMark(DocumentNote note) => DocumentMark(
  start: note.start,
  end: note.end,
  excerpt: note.excerpt,
  color: note.color,
  style: HighlightStyle.underline,
);

/// Pone la llamada a la nota [id] justo después de la letra [end] - 1 del
/// cuerpo: si cae en medio de un texto, su run se parte en dos —los dos con
/// las propiedades del original— y la llamada va en uno propio entre ellos.
///
/// El texto de la izquierda se queda en su elemento de siempre: las llamadas
/// que todavía faltan poner, que están antes, siguen encontrando el suyo.
void _insertReference(List<_Text> texts, int end, String prefix, int id) {
  // El texto que tiene la letra [end] - 1.
  var low = 0;
  var high = texts.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (texts[mid].start <= end - 1) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final text = texts[low];
  final run = text.element.parent;
  if (run is! XmlElement || !_isWord(run, 'r')) return;
  final parent = run.parent;
  if (parent is! XmlElement) return;
  final cut = end - text.start;

  final properties = run.children
      .whereType<XmlElement>()
      .where((c) => _isWord(c, 'rPr'))
      .firstOrNull;
  // Lo que en el run sigue a la letra: el resto del texto y lo que venga
  // después de él.
  final rest = <XmlNode>[];
  final at = run.children.indexOf(text.element);
  if (cut < text.text.length) {
    rest.add(_textLike(text.element, text.text.substring(cut)));
    text.element.children
      ..clear()
      ..add(XmlText(text.text.substring(0, cut)));
    _preserveSpace(text.element);
  }
  final following = run.children.sublist(at + 1);
  for (final node in following) {
    node.remove();
  }
  rest.addAll(following);

  final reference = _w3(prefix, 'r')
    ..children.addAll([
      _superscript(prefix),
      _w3(prefix, 'footnoteReference', {'id': '$id'}),
    ]);
  final after = [
    reference,
    if (rest.any((n) => n is XmlElement))
      XmlElement(run.name.copy(), run.attributes.map((a) => a.copy()), [
        if (properties != null) properties.copy(),
        ...rest,
      ]),
  ];
  parent.children.insertAll(parent.children.indexOf(run) + 1, after);
}

/// Las propiedades de un número volado.
XmlElement _superscript(String prefix) =>
    _w3(prefix, 'rPr')
      ..children.add(_w3(prefix, 'vertAlign', {'val': 'superscript'}));

// ---------------------------------------------------------------------
// Las partes relacionadas con el cuerpo
// ---------------------------------------------------------------------

/// La parte de [type] relacionada con el cuerpo —los comentarios, las notas
/// al pie—: la que ya nombra una relación, o [fileName] al lado del cuerpo
/// con su relación nueva y su tipo de contenido declarados en [replaced].
///
/// Lee las relaciones y los tipos de contenido como ya quedaron en
/// [replaced]: los comentarios y las notas al pie se agregan en la misma
/// escritura, y lo segundo no puede pisar lo primero.
String _relatedPart({
  required _Parts parts,
  required Map<String, Uint8List> replaced,
  required String type,
  required String contentType,
  required String fileName,
}) {
  final documentPart = parts.documentPart;
  final folder = _folderOf(documentPart);
  final relsName = '$folder/_rels/${documentPart.split('/').last}.rels'
      .replaceFirst(RegExp('^/'), '');

  final relsBytes = _current(parts, replaced, relsName);
  final rels = relsBytes == null
      ? XmlDocument.parse('$_declaration<Relationships xmlns="$_rels"/>')
      : XmlDocument.parse(utf8.decode(relsBytes, allowMalformed: true));
  final relsRoot = rels.rootElement;

  for (final rel in relsRoot.childElements) {
    if ((rel.getAttribute('Type') ?? '') == type) {
      final part = _resolve(folder, rel.getAttribute('Target') ?? '');
      _declareContentType(parts, replaced, part, contentType);
      return part;
    }
  }

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
      XmlAttribute(XmlName('Type'), type),
      XmlAttribute(XmlName('Target'), fileName),
    ]),
  );
  replaced[parts.key(relsName)] = Uint8List.fromList(
    utf8.encode(rels.toXmlString()),
  );
  final part = _join(folder, fileName);
  _declareContentType(parts, replaced, part, contentType);
  return part;
}

/// Declara el tipo de contenido de [part], si no está dicho.
void _declareContentType(
  _Parts parts,
  Map<String, Uint8List> replaced,
  String part,
  String contentType,
) {
  const typesName = '[Content_Types].xml';
  final typesBytes = _current(parts, replaced, typesName);
  if (typesBytes == null) return;
  final types = XmlDocument.parse(
    utf8.decode(typesBytes, allowMalformed: true),
  );
  final partName = '/${part.replaceFirst(RegExp('^/'), '')}';
  final declared = types.rootElement.childElements.any(
    (e) =>
        e.name.local == 'Override' &&
        (e.getAttribute('PartName') ?? '').toLowerCase() ==
            partName.toLowerCase(),
  );
  if (declared) return;
  // Sin prefijo: hereda el espacio de nombres del documento.
  types.rootElement.children.add(
    XmlElement(XmlName('Override'), [
      XmlAttribute(XmlName('PartName'), partName),
      XmlAttribute(XmlName('ContentType'), contentType),
    ]),
  );
  replaced[parts.key(typesName)] = Uint8List.fromList(
    utf8.encode(types.toXmlString()),
  );
}

/// La parte [name] como quedó: la reemplazada en esta escritura, o la del
/// archivo.
Uint8List? _current(
  _Parts parts,
  Map<String, Uint8List> replaced,
  String name,
) => replaced[parts.key(name)] ?? parts.read(name);

/// Un elemento de Word con [prefix] y sus atributos con el mismo prefijo.
XmlElement _w3(String prefix, String local, [Map<String, String>? attrs]) =>
    XmlElement(XmlName.fromString('$prefix:$local'), [
      for (final MapEntry(:key, :value) in (attrs ?? const {}).entries)
        XmlAttribute(XmlName.fromString('$prefix:$key'), value),
    ]);

/// Un `w:t` con [text], con sus espacios de las puntas.
XmlElement _textOf(String prefix, String text) => _w3(prefix, 't')
  ..attributes.add(XmlAttribute(XmlName.fromString('xml:space'), 'preserve'))
  ..children.add(XmlText(text));

/// Los renglones de una nota, sin los blancos de las puntas.
List<String> _lines(String note) => note.trim().split(RegExp(r'\r\n|\r|\n'));

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
