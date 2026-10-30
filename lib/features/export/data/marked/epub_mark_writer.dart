import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/features/export/data/marked/html_mark_writer.dart';
import 'package:sinapsis/features/export/data/marked/mark_painter.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';
import 'package:xml/xml.dart';

/// Escribe resaltados en un libro EPUB (F38): el mismo libro, con cada tramo
/// envuelto en un `<mark>` con su color en los XHTML de los capítulos.
///
/// **Qué capítulo.** El texto extraído de un EPUB es sus capítulos, en el
/// orden del spine, unidos con una línea de `---`: se recorren los capítulos
/// como lo hace `EpubParser` —`EpubParser.chapterFiles` y `xhtmlToMarkdown`,
/// no una copia del recorrido—, se ubica el Markdown de cada uno dentro del
/// texto extraído y así cada tramo cae en su capítulo por sus posiciones. Si
/// no coinciden —el texto guardado no es el que sale hoy del libro—, o el
/// tramo cruza dos capítulos, se lo busca por su texto copiado (`excerpt`) en
/// los capítulos, en el primero que lo tenga. Dentro del capítulo, el tramo se
/// ubica con `locateMarks`, como en la página web: comparando solo letras y
/// números. Lo que no se encuentra se saltea.
///
/// **Lo que se toca.** Solo los capítulos con algún tramo: se leen como XML,
/// se les parten los textos en `<mark style="…">` —uno por cada texto que el
/// tramo cruza, así que una negrita o un enlace en el medio no molesta— y se
/// vuelven a escribir en la codificación en que estaban (UTF-8, UTF-16 o
/// ISO-8859-1; un capítulo en otra se deja como está). Todas las demás
/// entradas del ZIP quedan como estaban, y `mimetype` sigue primera y sin
/// comprimir, como pide el estándar para reconocer un EPUB sin abrirlo.
///
/// Un capítulo que no es XML válido —el extractor lo lee como HTML— tampoco
/// se toca: reescribirlo como XML lo cambiaría más de lo que se pidió.
///
/// **Las notas en el texto** (F45, mejora 19) son notas al pie de EPUB 3: la
/// llamada —un número volado con `epub:type="noteref"`— va justo después del
/// pedazo citado, y la nota, en un `<aside epub:type="footnote">` al final de
/// su capítulo, que los lectores muestran en una ventanita al tocar la
/// llamada. Se reparten por capítulo como los tramos y se numeran en el orden
/// del libro.
///
/// Es una función sin E/S: un libro grande conviene correrlo fuera del hilo
/// de la interfaz, como el parser.
class EpubMarkWriter {
  const EpubMarkWriter();

  /// El libro [epub] con [marks] resaltados y [notes] como notas al pie.
  /// [content] es el texto extraído del libro, en cuyas posiciones están los
  /// dos.
  Uint8List write(
    Uint8List epub,
    String content,
    List<DocumentMark> marks, [
    List<DocumentNote> notes = const [],
  ]) {
    if (marks.isEmpty && notes.isEmpty) return epub;
    final archive = ZipDecoder().decodeBytes(epub);
    final chapters = _chapters(archive, content);
    _paintMarks(chapters, marks);
    _placeNotes(chapters, notes);

    // El número de cada nota, en el orden del libro.
    final numbers = <int, int>{};
    for (final chapter in chapters) {
      for (final id in chapter.state?.painter.noteOrder ?? const <int>[]) {
        numbers[id] = numbers.length + 1;
      }
    }

    final rewritten = <String, List<int>>{};
    for (final chapter in chapters) {
      final state = chapter.state;
      if (state == null || state.painter.isEmpty) continue;
      rewritten[chapter.file.path] = state.write(numbers, notes);
    }
    if (rewritten.isEmpty) return epub;
    return _zip(archive, rewritten);
  }

  /// Pinta [marks] en [chapters]: ver la documentación de la clase.
  void _paintMarks(List<_Chapter> chapters, List<DocumentMark> marks) {
    if (marks.isEmpty) return;

    // A cada tramo, su capítulo por sus posiciones; con las posiciones del
    // capítulo, que es lo que el ubicador entiende.
    final byChapter = <int, List<int>>{};
    final lost = <int>[];
    for (var index = 0; index < marks.length; index++) {
      final mark = marks[index];
      final at = chapters.indexWhere(
        (c) =>
            c.start != null &&
            mark.start >= c.start! &&
            mark.end <= c.start! + c.markdown.length,
      );
      if (at < 0) {
        lost.add(index);
      } else {
        (byChapter[at] ??= []).add(index);
      }
    }
    for (final MapEntry(key: at, value: indexes) in byChapter.entries) {
      final chapter = chapters[at];
      final painter = chapter.state?.painter;
      // Un capítulo que no se puede reescribir se deja como está, y lo que
      // le tocaba no se busca en otro: sería pintar un pasaje parecido.
      if (painter == null) continue;
      final found = painter.paint([
        for (final i in indexes) _shifted(marks[i], -chapter.start!),
      ], priorities: indexes);
      for (var k = 0; k < indexes.length; k++) {
        if (!found[k]) lost.add(indexes[k]);
      }
    }

    // Lo que no cayó donde sus posiciones decían, por su texto: en el primer
    // capítulo que lo tenga. Sin un lugar de dónde partir, el ubicador toma la
    // primera repetición.
    lost.sort();
    var pending = lost;
    for (final chapter in chapters) {
      final painter = chapter.state?.painter;
      if (pending.isEmpty) break;
      if (painter == null) continue;
      final found = painter.paint([
        for (final i in pending) _shifted(marks[i], -marks[i].start),
      ], priorities: pending);
      pending = [
        for (var k = 0; k < pending.length; k++)
          if (!found[k]) pending[k],
      ];
    }
  }

  /// Ubica el pedazo de cada una de [notes] en [chapters], como los tramos:
  /// por sus posiciones y, si no, por su texto en el primer capítulo que lo
  /// tenga.
  void _placeNotes(List<_Chapter> chapters, List<DocumentNote> notes) {
    if (notes.isEmpty) return;
    final byChapter = <int, List<int>>{};
    final lost = <int>[];
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      final at = chapters.indexWhere(
        (c) =>
            c.start != null &&
            note.start >= c.start! &&
            note.end <= c.start! + c.markdown.length,
      );
      if (at < 0) {
        lost.add(index);
      } else {
        (byChapter[at] ??= []).add(index);
      }
    }
    for (final MapEntry(key: at, value: indexes) in byChapter.entries) {
      final chapter = chapters[at];
      final painter = chapter.state?.painter;
      if (painter == null) continue;
      final found = painter.placeNotes([
        for (final i in indexes) _shiftedNote(notes[i], -chapter.start!),
      ], ids: indexes);
      for (var k = 0; k < indexes.length; k++) {
        if (!found[k]) lost.add(indexes[k]);
      }
    }
    lost.sort();
    var pending = lost;
    for (final chapter in chapters) {
      final painter = chapter.state?.painter;
      if (pending.isEmpty) break;
      if (painter == null) continue;
      final found = painter.placeNotes([
        for (final i in pending) _shiftedNote(notes[i], -notes[i].start),
      ], ids: pending);
      pending = [
        for (var k = 0; k < pending.length; k++)
          if (!found[k]) pending[k],
      ];
    }
  }
}

/// [note] con sus posiciones corridas [by] letras.
DocumentNote _shiftedNote(DocumentNote note, int by) => DocumentNote(
  start: note.start + by,
  end: note.end + by,
  excerpt: note.excerpt,
  note: note.note,
  color: note.color,
);

/// [mark] con sus posiciones corridas [by] letras.
DocumentMark _shifted(DocumentMark mark, int by) => DocumentMark(
  start: mark.start + by,
  end: mark.end + by,
  excerpt: mark.excerpt,
  color: mark.color,
  style: mark.style,
  note: mark.note,
);

/// Un capítulo que da texto, y dónde empieza su Markdown en el texto
/// extraído (`null` si no se encontró).
class _Chapter {
  _Chapter(this.file, this.text, this.markdown, this.start);

  final EpubSpineFile file;
  final String text;
  final String markdown;
  final int? start;

  /// Para pintar en él; `null` si no se puede reescribir. Se arma cuando se
  /// pide por primera vez.
  late final _ChapterState? state = _ChapterState.of(this);
}

/// Los capítulos del libro que el extractor une, en su orden, cada uno con
/// su lugar en [content].
List<_Chapter> _chapters(Archive archive, String content) {
  final chapters = <_Chapter>[];
  var cursor = 0;
  for (final file in EpubParser.chapterFiles(archive)) {
    final text = EpubParser.decodeChapter(file.bytes);
    final markdown = xhtmlToMarkdown(text);
    if (markdown.trim().isEmpty) continue;
    final at = content.indexOf(markdown, cursor);
    if (at >= 0) cursor = at + markdown.length;
    chapters.add(_Chapter(file, text, markdown, at >= 0 ? at : null));
  }
  return chapters;
}

/// Un capítulo leído como XML, con sus textos a la vista para pintarlos.
class _ChapterState {
  _ChapterState._(
    this._document,
    this._body,
    this._texts,
    this._encoding,
    this.painter,
  );

  static _ChapterState? of(_Chapter chapter) {
    final encoding = _Encoding.of(chapter.file.bytes);
    final document = parseXhtml(chapter.text);
    if (encoding == null || document == null) return null;
    final root = document.rootElement;
    final body = root.localName == 'body'
        ? root
        : root.descendantElements
              .where((element) => element.localName == 'body')
              .firstOrNull;
    if (body == null) return null;
    final texts = <XmlText>[];
    _collect(body, texts);
    return _ChapterState._(
      document,
      body,
      texts,
      encoding,
      MarkPainter([for (final text in texts) text.value], chapter.markdown),
    );
  }

  final XmlDocument _document;
  final XmlElement _body;
  final List<XmlText> _texts;
  final _Encoding _encoding;
  final MarkPainter painter;

  /// El capítulo con los textos pintados y las llamadas de las notas —con
  /// los números de [numbers], por id, y lo que dicen en [notes]—, en los
  /// bytes de su codificación.
  List<int> write(Map<int, int> numbers, List<DocumentNote> notes) {
    final prefix = _body.name.prefix;
    for (final node in painter.touched.toList()..sort()) {
      final pieces = painter.piecesOf(node);
      if (pieces == null) continue;
      final text = _texts[node];
      final parent = text.parent;
      if (parent == null) continue;
      final neighbor = parent is XmlElement ? parent.name.prefix : null;
      final replacement = [
        for (final p in pieces) ...[
          _nodeOf(p, neighbor),
          for (final id in p.notes) _callOf(numbers[id]!, neighbor),
        ],
      ];
      final index = parent.children.indexOf(text);
      parent.children.replaceRange(index, index + 1, replacement);
    }
    final order = painter.noteOrder;
    if (order.isNotEmpty) {
      _declareOps(_document.rootElement);
      for (final id in order) {
        _body.children.add(_asideOf(numbers[id]!, notes[id].note, prefix));
      }
    }
    return _encoding.encode(_document.toXmlString());
  }
}

/// El espacio de nombres de `epub:type`.
const _ops = 'http://www.idpf.org/2007/ops';

/// Que [root] declare el prefijo `epub`, para poder decir `epub:type`.
void _declareOps(XmlElement root) {
  final declared = root.attributes.any(
    (a) => a.name.prefix == 'xmlns' && a.name.local == 'epub',
  );
  if (declared) return;
  root.attributes.add(XmlAttribute(XmlName('epub', 'xmlns'), _ops));
}

XmlName _named(String local, String? prefix) =>
    prefix == null ? XmlName(local) : XmlName(local, prefix);

/// La llamada a la nota [number]: su número volado, que lleva a la nota.
XmlElement _callOf(int number, String? prefix) =>
    XmlElement(_named('sup', prefix), const [], [
      XmlElement(
        _named('a', prefix),
        [
          XmlAttribute(XmlName('type', 'epub'), 'noteref'),
          XmlAttribute(XmlName('href'), '#$kNoteIdPrefix$number'),
          XmlAttribute(XmlName('id'), '$kNoteCallIdPrefix$number'),
        ],
        [XmlText('$number')],
      ),
    ]);

/// La nota al pie [number]: lo que dice, un renglón por renglón, con su
/// número y su vuelta a la llamada.
XmlElement _asideOf(int number, String note, String? prefix) {
  final lines = note.trim().split(RegExp(r'\r\n|\r|\n'));
  final paragraph = XmlElement(_named('p', prefix), const [], [
    XmlElement(
      _named('a', prefix),
      [XmlAttribute(XmlName('href'), '#$kNoteCallIdPrefix$number')],
      [XmlText('$number.')],
    ),
    XmlText(' '),
    for (var l = 0; l < lines.length; l++) ...[
      if (l > 0) XmlElement(_named('br', prefix)),
      XmlText(lines[l]),
    ],
  ]);
  return XmlElement(
    _named('aside', prefix),
    [
      XmlAttribute(XmlName('type', 'epub'), 'footnote'),
      XmlAttribute(XmlName('id'), '$kNoteIdPrefix$number'),
    ],
    [paragraph],
  );
}

void _collect(XmlElement element, List<XmlText> texts) {
  for (final child in element.children) {
    if (child is XmlText) {
      texts.add(child);
    } else if (child is XmlElement &&
        !markOpaqueElements.contains(child.localName.toLowerCase())) {
      _collect(child, texts);
    }
  }
}

/// El pedazo [piece] como nodo: texto, o `<mark>` con el texto adentro. Con
/// el prefijo de espacio de nombres de su vecino, si el capítulo usa uno.
XmlNode _nodeOf(MarkedPiece piece, String? prefix) {
  if (piece.fill == null && piece.underline == null) {
    return XmlText(piece.text);
  }
  final note = markNoteOf(piece);
  return XmlElement(
    prefix == null ? XmlName('mark') : XmlName('mark', prefix),
    [
      XmlAttribute(XmlName('style'), markStyleOf(piece)),
      if (note != null) XmlAttribute(XmlName('title'), note),
    ],
    [XmlText(piece.text)],
  );
}

/// Cómo está guardado un capítulo, para escribirlo de vuelta igual.
class _Encoding {
  const _Encoding._(this._kind, {this.bom = false, this.bigEndian = false});

  /// La codificación de los bytes de un capítulo, o `null` si es una que no
  /// se sabe escribir de vuelta.
  static _Encoding? of(List<int> bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return const _Encoding._('utf16', bom: true, bigEndian: true);
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return const _Encoding._('utf16', bom: true);
      }
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return const _Encoding._('utf8', bom: true);
    }
    final declared = _xmlEncoding
        .firstMatch(
          latin1.decode(bytes.length > 200 ? bytes.sublist(0, 200) : bytes),
        )?[1]
        ?.toLowerCase();
    return switch (declared) {
      null || 'utf-8' || 'utf8' => const _Encoding._('utf8'),
      'iso-8859-1' ||
      'iso8859-1' ||
      'iso_8859-1' ||
      'latin1' ||
      'latin-1' => const _Encoding._('latin1'),
      _ => null,
    };
  }

  final String _kind;
  final bool bom;
  final bool bigEndian;

  List<int> encode(String xml) {
    switch (_kind) {
      case 'utf16':
        final units = xml.codeUnits;
        final out = <int>[
          if (bigEndian) ...[0xFE, 0xFF] else ...[0xFF, 0xFE],
          for (final unit in units)
            if (bigEndian) ...[
              unit >> 8,
              unit & 0xFF,
            ] else ...[
              unit & 0xFF,
              unit >> 8,
            ],
        ];
        return out;
      case 'latin1':
        // Lo que ISO-8859-1 no tiene —una nota con una letra de otro
        // alfabeto— va como referencia numérica, que XML entiende igual.
        final buffer = StringBuffer();
        for (final rune in xml.runes) {
          if (rune > 0xFF) {
            buffer.write('&#$rune;');
          } else {
            buffer.writeCharCode(rune);
          }
        }
        return latin1.encode(buffer.toString());
      default:
        return [
          if (bom) ...[0xEF, 0xBB, 0xBF],
          ...utf8.encode(xml),
        ];
    }
  }
}

/// El `encoding` de la declaración de XML, al principio del archivo.
final _xmlEncoding = RegExp(
  r'''^\s*<\?xml\s[^>]*?encoding\s*=\s*["']([^"']+)["']''',
);

/// El ZIP de [original] con [rewritten] —ruta y bytes nuevos— en el lugar de
/// las entradas del mismo nombre. `mimetype` primero y sin comprimir; las
/// demás entradas, con los mismos bytes y en el mismo orden.
///
/// Cada entrada se copia a una nueva en vez de volver a agregar la leída: en
/// `archive` una entrada que ya se leyó (`readBytes`) y se agrega a otro ZIP
/// sale con su contenido comprimido dos veces.
Uint8List _zip(Archive original, Map<String, List<int>> rewritten) {
  final out = Archive();
  final mimetype = original.files
      .where((f) => f.name == 'mimetype')
      .firstOrNull;
  if (mimetype != null) {
    out.add(
      ArchiveFile.bytes('mimetype', mimetype.readBytes() ?? const [])
        ..compression = CompressionType.none
        ..lastModTime = mimetype.lastModTime,
    );
  }
  for (final file in original.files) {
    if (identical(file, mimetype)) continue;
    if (file.isDirectory) {
      out.add(ArchiveFile.directory(file.name)..lastModTime = file.lastModTime);
      continue;
    }
    final bytes = rewritten[file.name] ?? file.readBytes() ?? const <int>[];
    out.add(
      ArchiveFile.bytes(file.name, bytes)
        ..lastModTime = file.lastModTime
        ..compression = file.compression == CompressionType.none
            ? CompressionType.none
            : null,
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}
