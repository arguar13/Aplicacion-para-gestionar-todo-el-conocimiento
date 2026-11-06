import 'package:meta/meta.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';

// «Descargar el índice» (F46, paso 4): lo que se está mirando, en renglones
// listos para escribir en un PDF o en Markdown. Puro: lo que dice cada
// renglón —el nombre de un tema, la página de un capítulo— lo pone quien
// llama, en su idioma ([IndexPrintLabels]).

/// Qué es un renglón del índice descargado.
enum IndexPrintKind {
  /// Un tema, en versalitas.
  topic,

  /// Un documento, con su título en serif.
  document,

  /// Un capítulo, con su sangría, su número, los puntos y su página.
  chapter,

  /// «Texto completo», sin puntos ni página.
  wholeText,

  /// Una imagen, con su lugar en la galería.
  image,
}

/// Un renglón del índice descargado.
@immutable
class IndexPrintLine {
  const IndexPrintLine({
    required this.kind,
    required this.title,
    this.level = 0,
    this.number,
    this.page,
    this.note,
    this.context = false,
  });

  final IndexPrintKind kind;
  final String title;

  /// El nivel de un capítulo, desde 1; 0 en un tema o un documento.
  final int level;

  /// «1.2.3», si se numera.
  final String? number;

  /// Lo que va a la derecha de los puntos: «p. 47», «pág. 3», «img. 3».
  final String? page;

  /// Lo que va debajo de un documento, en chico: «también en Roma».
  final String? note;

  /// En una búsqueda, un capítulo que se ve porque contiene a lo encontrado.
  final bool context;

  @override
  bool operator ==(Object other) =>
      other is IndexPrintLine &&
      other.kind == kind &&
      other.title == title &&
      other.level == level &&
      other.number == number &&
      other.page == page &&
      other.note == note &&
      other.context == context;

  @override
  int get hashCode =>
      Object.hash(kind, title, level, number, page, note, context);

  @override
  String toString() =>
      'IndexPrintLine(${kind.name} $level ${number ?? ''} «$title»'
      '${page == null ? '' : ' $page'}${note == null ? '' : ' ($note)'})';
}

/// El índice descargado: su título, la línea que dice qué se descargó y sus
/// renglones.
@immutable
class IndexPrint {
  const IndexPrint({
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final String title;
  final String subtitle;
  final List<IndexPrintLine> lines;

  bool get isEmpty => lines.isEmpty;
}

/// Cómo se nombra cada cosa en el idioma de la app.
@immutable
class IndexPrintLabels {
  const IndexPrintLabels({
    required this.topicName,
    required this.entryTitle,
    required this.entryPage,
    required this.topicsNote,
  });

  /// El nombre de un tema, con «Sin tema».
  final String Function(IndexTopic topic) topicName;

  /// El título que se lee de una entrada: el suyo, «Texto completo»,
  /// «Imagen 3».
  final String Function(IndexEntry entry) entryTitle;

  /// Lo que va a la derecha de los puntos.
  final String? Function(IndexEntry entry) entryPage;

  /// Lo que va debajo de un documento: los temas de `spaceIds` —sus otros
  /// temas bajo uno (`listed` falso), o todos en una lista sin temas—;
  /// `null` si no hay que decir nada.
  final String? Function(List<String> spaceIds, {required bool listed})
  topicsNote;
}

/// Un grupo del árbol: un tema con sus documentos, o —`topic` `null`, «Por
/// documento»— todos sin temas.
typedef IndexPrintGroup = ({IndexTopic? topic, List<IndexDocument> documents});

/// Los renglones del árbol que se está mirando: cada tema, sus documentos y,
/// de cada uno, sus entradas hasta [depth] —«Niveles: 1 · 2 · 3 · Todo», como
/// en Word—, con lo que se abrió o se cerró a mano ([folds], por documento) y
/// la numeración si [numbered]. Las mismas filas que el Índice dibuja al
/// desplegar un documento (`indexOutline`): lo descargado y lo que se ve
/// dicen lo mismo.
///
/// Un documento que está bajo dos temas va bajo los dos (decisión D).
List<IndexPrintLine> indexPrintTree({
  required List<IndexPrintGroup> groups,
  required Map<String, List<IndexEntry>> entries,
  required int? depth,
  required IndexPrintLabels labels,
  Map<String, Map<int, bool>> folds = const {},
  bool numbered = false,
}) {
  final lines = <IndexPrintLine>[];
  for (final group in groups) {
    final topic = group.topic;
    if (topic != null) {
      lines.add(
        IndexPrintLine(
          kind: IndexPrintKind.topic,
          title: labels.topicName(topic),
        ),
      );
    }
    for (final document in group.documents) {
      lines.add(
        IndexPrintLine(
          kind: IndexPrintKind.document,
          title: document.title,
          note: labels.topicsNote(
            topic == null ? document.spaceIds : document.alsoIn(topic.spaceId),
            listed: topic == null,
          ),
        ),
      );
      final rows = indexOutline(
        entries[document.id] ?? const [],
        depth: depth,
        folds: folds[document.id] ?? const {},
        numbered: numbered,
      );
      for (final row in rows) {
        lines.add(_entryLine(row.entry, labels, number: row.number));
      }
    }
  }
  return lines;
}

/// Los renglones de una búsqueda: primero los documentos cuyo título
/// coincide ([documents]), y después lo encontrado de cada documento con los
/// capítulos que lo contienen ([groups], `groupIndexSearch`), como se ve.
List<IndexPrintLine> indexPrintSearch({
  required List<IndexDocument> documents,
  required List<IndexSearchGroup> groups,
  required IndexPrintLabels labels,
}) => [
  for (final document in documents)
    IndexPrintLine(
      kind: IndexPrintKind.document,
      title: document.title,
      note: labels.topicsNote(document.spaceIds, listed: true),
    ),
  for (final group in groups) ...[
    IndexPrintLine(
      kind: IndexPrintKind.document,
      title: group.first.documentTitle,
      note: labels.topicsNote(group.first.spaceIds, listed: true),
    ),
    for (final row in group.rows)
      _entryLine(row.entry, labels, context: !row.matched),
  ],
];

IndexPrintLine _entryLine(
  IndexEntry entry,
  IndexPrintLabels labels, {
  String? number,
  bool context = false,
}) => IndexPrintLine(
  kind: switch (entry) {
    IndexEntry(isImage: true) => IndexPrintKind.image,
    IndexEntry(isWholeText: true) => IndexPrintKind.wholeText,
    _ => IndexPrintKind.chapter,
  },
  title: labels.entryTitle(entry),
  level: entry.level,
  number: number,
  page: labels.entryPage(entry),
  context: context,
);

/// [print] en Markdown: el título, la línea de lo que se descargó, cada tema
/// como `##`, cada documento como título —`###` bajo un tema, `##` sin
/// temas— con lo que dice debajo en cursiva, y sus entradas como una lista
/// con sangría por nivel, su número y su página después de una raya.
String indexMarkdown(IndexPrint print) {
  final out = StringBuffer()
    ..writeln('# ${_escape(print.title)}')
    ..writeln()
    ..writeln('*${_escape(print.subtitle)}*');
  final topics = print.lines.any((l) => l.kind == IndexPrintKind.topic);
  var inList = false;
  for (final line in print.lines) {
    switch (line.kind) {
      case IndexPrintKind.topic:
        out
          ..writeln()
          ..writeln('## ${_escape(line.title)}');
        inList = false;
      case IndexPrintKind.document:
        out
          ..writeln()
          ..writeln('${topics ? '###' : '##'} ${_escape(line.title)}');
        if (line.note case final note?) {
          out
            ..writeln()
            ..writeln('*${_escape(note)}*');
        }
        inList = false;
      case IndexPrintKind.chapter ||
          IndexPrintKind.wholeText ||
          IndexPrintKind.image:
        if (!inList) out.writeln();
        inList = true;
        final indent = '  ' * (line.level - 1).clamp(0, 20);
        final number = line.number == null ? '' : '${line.number} ';
        final title = line.kind == IndexPrintKind.wholeText
            ? '*${_escape(line.title)}*'
            : _escape(line.title);
        final page = line.page == null ? '' : ' — ${_escape(line.page!)}';
        out.writeln('$indent- $number$title$page');
    }
  }
  return out.toString();
}

/// [text] sin lo que Markdown leería como marca: un título con `*`, `_` o
/// `#` se ve tal cual.
String _escape(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_\[\]<>#|]'),
  (match) => '\\${match[0]}',
);
