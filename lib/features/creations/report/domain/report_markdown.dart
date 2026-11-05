import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';
import 'package:sinapsis/features/creations/report/domain/report_export_notes.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';

/// Los textos fijos de un informe exportado, ya traducidos por quien
/// exporta: el Markdown y el PDF dicen lo mismo.
@immutable
class ReportExportLabels {
  const ReportExportLabels({
    this.kicker = '',
    this.untitledSection = _untitled,
    this.questions = 'Para probarte',
    this.answerKey = 'Respuestas',
    this.sources = '',
    this.page = _page,
  });

  /// Lo que va arriba del título: «Guía de estudio · Interactivo».
  final String kicker;

  /// El título de una sección que no lo trae: «Sección 3».
  final String Function(int number) untitledSection;

  /// El título de las preguntas de una sección.
  final String questions;

  /// El título de las respuestas, al final.
  final String answerKey;

  /// La línea de las fuentes: «Fuentes: Éxodo, Levítico». Vacía, no va.
  final String sources;

  /// «Página 3 de 12».
  final String Function(int number, int total) page;

  static String _untitled(int number) => 'Sección $number';
  static String _page(int number, int total) => 'Página $number de $total';

  /// El título de la sección [index] (desde 0) de [report].
  String sectionTitle(Report report, int index) {
    final title = report.sections[index].title.trim();
    return title.isEmpty ? untitledSection(index + 1) : title;
  }
}

/// El informe en Markdown (F43, punto 5: «exportar a PDF o Markdown»), para
/// llevarlo a Obsidian, a un repositorio o a cualquier editor:
///
/// - `#` el título, la bajada en itálica, `##` cada sección;
/// - las viñetas, las listas, los subtítulos y las citas como en el visor;
/// - **las palabras clave en negrita** (el rosa no existe en Markdown);
/// - el glosario como viñetas «**Término**: definición»;
/// - en el interactivo, las preguntas de cada sección con sus opciones
///   (A, B, C…) y, al final, las respuestas con su explicación: así se puede
///   probar uno sin ver la respuesta al lado.
///
/// Las opciones van en el mismo orden que en el visor ([reportOptionOrder]).
///
/// **Las notas de la persona** (F45, paso 8c), con [notes]: las del informe
/// entero, al comienzo —después del título— en una cita, con su título en
/// negrita; las de un pedazo, como notas al pie —`[^nota-1]` justo después
/// del pedazo y lo que dice al final del archivo—, numeradas en el orden en
/// que aparecen.
String reportToMarkdown(
  Report report, {
  ReportKeywords keywords = ReportKeywords.empty,
  bool interactive = true,
  ReportExportLabels labels = const ReportExportLabels(),
  ReportExportNotes notes = ReportExportNotes.none,
}) {
  final calls = ReportNoteCalls(notes);
  String plain(ReportTextPlace place, String text) =>
      _inlines([ReportInline(text)], calls.callsAt(place));

  final out = StringBuffer();
  if (labels.kicker.isNotEmpty) out.writeln('*${_escape(labels.kicker)}*\n');
  out.writeln('# ${plain(const ReportTextPlace.title(), report.title)}');
  if (report.subtitle.isNotEmpty) {
    out
      ..writeln()
      ..writeln(
        '*${plain(const ReportTextPlace.subtitle(), report.subtitle)}*',
      );
  }
  if (labels.sources.isNotEmpty) {
    out
      ..writeln()
      ..writeln(_escape(labels.sources));
  }
  if (notes.whole.isNotEmpty) {
    out
      ..writeln()
      ..writeln(_opening(notes));
  }

  for (final (index, section) in report.sections.indexed) {
    final title = labels.sectionTitle(report, index);
    out
      ..writeln()
      ..writeln('## ${plain(ReportTextPlace.sectionTitle(index), title)}');
    final blocks = reportBlocksWithKeywords(section.body, keywords);
    if (blocks.isNotEmpty) out.writeln();
    ReportBlock? previous;
    for (final (b, block) in blocks.indexed) {
      // Los ítems de una lista van seguidos; lo demás, con una línea en
      // blanco antes.
      final list = block is ReportBullet && previous is ReportBullet;
      if (previous != null && !list) out.writeln();
      out.writeln(
        _block(block, calls.callsAt(ReportTextPlace.block(index, b))),
      );
      previous = block;
    }
    if (section.entries.isNotEmpty) {
      out.writeln();
      for (final (e, entry) in section.entries.indexed) {
        final term = plain(ReportTextPlace.term(index, e), entry.term);
        final definition = _inlines(
          withReportKeywords(parseReportInlines(entry.definition), keywords),
          calls.callsAt(ReportTextPlace.definition(index, e)),
        );
        out.writeln(
          definition.isEmpty ? '- **$term**' : '- **$term**: $definition',
        );
      }
    }
    if (interactive && section.questions.isNotEmpty) {
      out
        ..writeln()
        ..writeln('### ${_escape(labels.questions)}')
        ..writeln();
      for (final (q, question) in section.questions.indexed) {
        if (q > 0) out.writeln();
        final asked = _inlines(
          parseReportInlines(question.question),
          calls.callsAt(ReportTextPlace.question(index, q)),
        );
        out.writeln('${q + 1}. $asked');
        for (final (i, option) in reportOptionOrder(question).indexed) {
          final text = plain(
            ReportTextPlace.option(index, q, question.options.indexOf(option)),
            option.text,
          );
          out.writeln('   - ${reportOptionLetter(i)}. $text');
        }
      }
    }
  }

  if (interactive && report.questionCount > 0) {
    out
      ..writeln()
      ..writeln('## ${_escape(labels.answerKey)}');
    for (final (index, section) in report.sections.indexed) {
      if (section.questions.isEmpty) continue;
      out
        ..writeln()
        ..writeln('### ${_escape(labels.sectionTitle(report, index))}')
        ..writeln();
      for (final (q, question) in section.questions.indexed) {
        final order = reportOptionOrder(question);
        final letter = reportOptionLetter(order.indexOf(question.correct));
        final explanation = question.explanation.isEmpty
            ? ''
            : ' — ${_escape(question.explanation)}';
        final correct = _escape(question.correct.text);
        out.writeln('${q + 1}. **$letter. $correct**$explanation');
      }
    }
  }
  if (calls.written.isNotEmpty) {
    out.writeln();
    for (final (i, note) in calls.written.indexed) {
      final lines = note.trim().split(RegExp(r'\r\n|\r|\n'));
      out.writeln('[^nota-${i + 1}]: ${lines.first}');
      // Los renglones que siguen, con sangría: siguen siendo de la nota.
      for (final line in lines.skip(1)) {
        out.writeln(line.isEmpty ? '' : '    $line');
      }
    }
  }
  return out.toString();
}

/// Las notas del informe entero, en una cita: el título en negrita y cada
/// nota en una viñeta, con sus renglones.
String _opening(ReportExportNotes notes) => [
  if (notes.title.isNotEmpty) ...['> **${_escape(notes.title)}**', '>'],
  for (final note in notes.whole) ..._quotedItem(note),
].join('\n');

List<String> _quotedItem(String note) {
  final lines = note.trim().split(RegExp(r'\r\n|\r|\n'));
  return [
    '> - ${lines.first}',
    for (final line in lines.skip(1))
      if (line.isEmpty) '>' else '>   $line',
  ];
}

String _block(ReportBlock block, List<ReportNoteCall> calls) => switch (block) {
  ReportParagraph() => _inlines(block.inlines, calls),
  ReportBullet(:final level, :final number) =>
    '${'  ' * level}${number == null ? '-' : '$number.'} '
        '${_inlines(block.inlines, calls)}',
  ReportSubheading() => '### ${_inlines(block.inlines, calls)}',
  ReportQuote() => '> ${_inlines(block.inlines, calls)}',
};

/// Los pedazos en Markdown: la negrita y las palabras clave con `**`, la
/// itálica con `*`, y después de su pedazo la llamada de cada una de [calls],
/// `[^nota-1]` (F45, paso 8c).
String _inlines(
  List<ReportInline> inlines, [
  List<ReportNoteCall> calls = const [],
]) {
  final out = StringBuffer();
  for (final piece in reportInlinesWithCalls(inlines, calls)) {
    if (piece is int) {
      out.write('[^nota-$piece]');
      continue;
    }
    final inline = piece as ReportInline;
    final text = _escape(inline.text);
    final bold = inline.bold || inline.keyword;
    // Los espacios de los bordes quedan afuera de las marcas: «** palabra**»
    // no es negrita en Markdown.
    final lead = RegExp(r'^\s*').stringMatch(text)!;
    final trail = RegExp(r'\s*$').stringMatch(text.substring(lead.length))!;
    final core = text.substring(lead.length, text.length - trail.length);
    if (core.isEmpty || (!bold && !inline.italic)) {
      out.write(text);
      continue;
    }
    final mark = bold && inline.italic
        ? '***'
        : bold
        ? '**'
        : '*';
    out
      ..write(lead)
      ..write(mark)
      ..write(core)
      ..write(mark)
      ..write(trail);
  }
  return out.toString();
}

/// Lo que en Markdown tiene otro sentido, escapado: un asterisco suelto, un
/// guion bajo, un acento grave.
String _escape(String text) =>
    text.replaceAllMapped(RegExp(r'[\\*_`]'), (m) => '\\${m[0]}');
