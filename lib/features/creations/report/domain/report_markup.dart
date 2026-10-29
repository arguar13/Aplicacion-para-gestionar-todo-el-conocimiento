import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';

/// Un pedazo de texto de un informe con su estilo: lo que dibujan el visor,
/// el PDF y el Markdown.
@immutable
class ReportInline {
  const ReportInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.keyword = false,
  });

  final String text;
  final bool bold;
  final bool italic;

  /// Si es una palabra clave de las fuentes: va en rosa (decisión 85) y, en
  /// el Markdown, en negrita.
  final bool keyword;

  ReportInline copyWith({String? text, bool? keyword}) => ReportInline(
    text ?? this.text,
    bold: bold,
    italic: italic,
    keyword: keyword ?? this.keyword,
  );

  @override
  bool operator ==(Object other) =>
      other is ReportInline &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.keyword == keyword;

  @override
  int get hashCode => Object.hash(text, bold, italic, keyword);

  @override
  String toString() =>
      'ReportInline(${bold ? 'b ' : ''}${italic ? 'i ' : ''}'
      '${keyword ? 'k ' : ''}"$text")';
}

/// Un bloque del texto de una sección.
@immutable
sealed class ReportBlock {
  const ReportBlock(this.inlines);

  final List<ReportInline> inlines;

  /// El texto llano, sin estilos.
  String get plainText => inlines.map((i) => i.text).join();

  /// El mismo bloque con otros pedazos (las palabras clave ya marcadas).
  ReportBlock withInlines(List<ReportInline> inlines);
}

/// Un párrafo.
final class ReportParagraph extends ReportBlock {
  const ReportParagraph(super.inlines);

  @override
  ReportParagraph withInlines(List<ReportInline> inlines) =>
      ReportParagraph(inlines);

  @override
  bool operator ==(Object other) =>
      other is ReportParagraph && listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);

  @override
  String toString() => 'ReportParagraph($inlines)';
}

/// Una viñeta —o un ítem de una lista numerada, si tiene [number]—, con su
/// sangría: 0 o 1.
final class ReportBullet extends ReportBlock {
  const ReportBullet(super.inlines, {this.level = 0, this.number});

  final int level;

  /// El número del ítem en una lista numerada; `null` en una viñeta.
  final int? number;

  bool get ordered => number != null;

  @override
  ReportBullet withInlines(List<ReportInline> inlines) =>
      ReportBullet(inlines, level: level, number: number);

  @override
  bool operator ==(Object other) =>
      other is ReportBullet &&
      other.level == level &&
      other.number == number &&
      listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(level, number, Object.hashAll(inlines));

  @override
  String toString() => 'ReportBullet($level, $number, $inlines)';
}

/// Un subtítulo dentro de una sección (`### …`).
final class ReportSubheading extends ReportBlock {
  const ReportSubheading(super.inlines);

  @override
  ReportSubheading withInlines(List<ReportInline> inlines) =>
      ReportSubheading(inlines);

  @override
  bool operator ==(Object other) =>
      other is ReportSubheading && listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);

  @override
  String toString() => 'ReportSubheading($inlines)';
}

/// Una cita (`> …`): una frase textual del material.
final class ReportQuote extends ReportBlock {
  const ReportQuote(super.inlines);

  @override
  ReportQuote withInlines(List<ReportInline> inlines) => ReportQuote(inlines);

  @override
  bool operator ==(Object other) =>
      other is ReportQuote && listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);

  @override
  String toString() => 'ReportQuote($inlines)';
}

final _bullet = RegExp(r'^(\s*)[-*•·–]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _quote = RegExp(r'^\s*>\s?(.*)$');

/// Los bloques del texto de una sección —lo poco de Markdown que escribe la
/// IA—, con tolerancia:
///
/// - un párrafo hasta la línea en blanco; los renglones seguidos se unen con
///   un espacio (un modelo que corta las líneas a mano no parte el párrafo);
/// - viñetas con «- », «* », «• » o «– », y una segunda sangría desde dos
///   espacios; un renglón con sangría y sin marca sigue a su viñeta;
/// - listas numeradas «1. » o «1) »;
/// - `### subtítulos` (cualquier cantidad de #) y `> citas`;
/// - `**negrita**` y `*itálica*` dentro de cualquiera ([parseReportInlines]).
List<ReportBlock> parseReportBody(String body) {
  final blocks = <ReportBlock>[];
  final paragraph = <String>[];
  ReportBullet? openBullet;
  final openBulletText = StringBuffer();

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join(' ').trim();
    paragraph.clear();
    if (text.isNotEmpty) blocks.add(ReportParagraph(parseReportInlines(text)));
  }

  void flushBullet() {
    final bullet = openBullet;
    if (bullet == null) return;
    final text = openBulletText.toString().trim();
    openBullet = null;
    openBulletText.clear();
    if (text.isNotEmpty) {
      blocks.add(bullet.withInlines(parseReportInlines(text)));
    }
  }

  for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flushParagraph();
      flushBullet();
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      flushBullet();
      final text = _withoutWrappingBold(heading.group(1)!.trim());
      if (text.isNotEmpty) {
        blocks.add(ReportSubheading(parseReportInlines(text)));
      }
      continue;
    }
    final quote = _quote.firstMatch(line);
    if (quote != null) {
      flushParagraph();
      flushBullet();
      final text = quote.group(1)!.trim();
      if (text.isNotEmpty) blocks.add(ReportQuote(parseReportInlines(text)));
      continue;
    }
    // «**Negrita**» al principio de una línea no es una viñeta: el «*» de una
    // viñeta va seguido de un espacio.
    final bullet = _bullet.firstMatch(line);
    final numbered = bullet == null ? _numbered.firstMatch(line) : null;
    if (bullet != null || numbered != null) {
      flushParagraph();
      flushBullet();
      final indent = (bullet ?? numbered)!.group(1)!.length;
      openBullet = ReportBullet(
        const [],
        level: indent >= 2 ? 1 : 0,
        number: numbered == null ? null : int.parse(numbered.group(2)!),
      );
      openBulletText.write(
        bullet != null ? bullet.group(2) : numbered!.group(3),
      );
      continue;
    }
    if (openBullet != null && raw.startsWith(RegExp(r'\s'))) {
      // Sigue la viñeta de arriba.
      openBulletText
        ..write(' ')
        ..write(line.trim());
      continue;
    }
    flushBullet();
    paragraph.add(line.trim());
  }
  flushParagraph();
  flushBullet();
  return blocks;
}

/// «**Introducción**» como subtítulo es «Introducción»: el subtítulo ya va
/// destacado.
String _withoutWrappingBold(String text) {
  final match = RegExp(r'^\*\*(.+)\*\*$').firstMatch(text);
  return match == null ? text : match.group(1)!.trim();
}

final _boldPattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
final _italicPattern = RegExp(
  r'(?<![\p{L}\p{N}*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\p{L}\p{N}*])|'
  r'(?<![\p{L}\p{N}_])_(?![\s_])(.+?)(?<![\s_])_(?![\p{L}\p{N}_])',
  unicode: true,
);

/// Los pedazos de [text] con su negrita (`**…**` o `__…__`) y su itálica
/// (`*…*` o `_…_`). Una marca sin su pareja queda como está: un asterisco
/// suelto es un asterisco.
List<ReportInline> parseReportInlines(String text) {
  final inlines = <ReportInline>[];
  var at = 0;
  for (final match in _boldPattern.allMatches(text)) {
    if (match.start > at) {
      inlines.addAll(_italics(text.substring(at, match.start)));
    }
    final inner = (match.group(1) ?? match.group(2))!;
    inlines.add(ReportInline(_plainItalics(inner), bold: true));
    at = match.end;
  }
  if (at < text.length) inlines.addAll(_italics(text.substring(at)));
  return _merged(inlines);
}

List<ReportInline> _italics(String text) {
  final inlines = <ReportInline>[];
  var at = 0;
  for (final match in _italicPattern.allMatches(text)) {
    if (match.start > at) {
      inlines.add(ReportInline(text.substring(at, match.start)));
    }
    inlines.add(
      ReportInline((match.group(1) ?? match.group(2))!, italic: true),
    );
    at = match.end;
  }
  if (at < text.length) inlines.add(ReportInline(text.substring(at)));
  return inlines;
}

/// Lo de adentro de una negrita, sin las marcas de una itálica anidada (la
/// negrita ya destaca).
String _plainItalics(String text) =>
    text.replaceAllMapped(_italicPattern, (m) => (m.group(1) ?? m.group(2))!);

/// Une los pedazos seguidos con el mismo estilo y saca los vacíos.
List<ReportInline> _merged(List<ReportInline> inlines) {
  final merged = <ReportInline>[];
  for (final inline in inlines) {
    if (inline.text.isEmpty) continue;
    final last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.bold == inline.bold &&
        last.italic == inline.italic &&
        last.keyword == inline.keyword) {
      merged[merged.length - 1] = last.copyWith(text: last.text + inline.text);
    } else {
      merged.add(inline);
    }
  }
  return merged;
}

/// [inlines] con las palabras clave de [keywords] marcadas: cada pedazo se
/// parte donde empieza y termina una. Sin palabras clave, los mismos.
List<ReportInline> withReportKeywords(
  List<ReportInline> inlines,
  ReportKeywords keywords,
) {
  if (keywords.isEmpty) return inlines;
  final out = <ReportInline>[];
  for (final inline in inlines) {
    final ranges = keywords.rangesIn(inline.text);
    if (ranges.isEmpty) {
      out.add(inline);
      continue;
    }
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) {
        out.add(inline.copyWith(text: inline.text.substring(at, start)));
      }
      out.add(
        inline.copyWith(text: inline.text.substring(start, end), keyword: true),
      );
      at = end;
    }
    if (at < inline.text.length) {
      out.add(inline.copyWith(text: inline.text.substring(at)));
    }
  }
  return out;
}

/// Los bloques de [body] con sus palabras clave marcadas.
List<ReportBlock> reportBlocksWithKeywords(
  String body,
  ReportKeywords keywords,
) => [
  for (final block in parseReportBody(body))
    block.withInlines(withReportKeywords(block.inlines, keywords)),
];
