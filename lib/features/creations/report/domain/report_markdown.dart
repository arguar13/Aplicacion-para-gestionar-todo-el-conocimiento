import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
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
String reportToMarkdown(
  Report report, {
  ReportKeywords keywords = ReportKeywords.empty,
  bool interactive = true,
  ReportExportLabels labels = const ReportExportLabels(),
}) {
  final out = StringBuffer();
  if (labels.kicker.isNotEmpty) out.writeln('*${_escape(labels.kicker)}*\n');
  out.writeln('# ${_escape(report.title)}');
  if (report.subtitle.isNotEmpty) {
    out
      ..writeln()
      ..writeln('*${_escape(report.subtitle)}*');
  }
  if (labels.sources.isNotEmpty) {
    out
      ..writeln()
      ..writeln(_escape(labels.sources));
  }

  for (final (index, section) in report.sections.indexed) {
    out
      ..writeln()
      ..writeln('## ${_escape(labels.sectionTitle(report, index))}');
    final blocks = reportBlocksWithKeywords(section.body, keywords);
    if (blocks.isNotEmpty) out.writeln();
    ReportBlock? previous;
    for (final block in blocks) {
      // Los ítems de una lista van seguidos; lo demás, con una línea en
      // blanco antes.
      final list = block is ReportBullet && previous is ReportBullet;
      if (previous != null && !list) out.writeln();
      out.writeln(_block(block));
      previous = block;
    }
    if (section.entries.isNotEmpty) {
      out.writeln();
      for (final entry in section.entries) {
        final definition = _inlines(
          withReportKeywords(parseReportInlines(entry.definition), keywords),
        );
        out.writeln(
          definition.isEmpty
              ? '- **${_escape(entry.term)}**'
              : '- **${_escape(entry.term)}**: $definition',
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
        out.writeln('${q + 1}. ${_escape(question.question)}');
        for (final (i, option) in reportOptionOrder(question).indexed) {
          out.writeln('   - ${reportOptionLetter(i)}. ${_escape(option.text)}');
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
  return out.toString();
}

String _block(ReportBlock block) => switch (block) {
  ReportParagraph() => _inlines(block.inlines),
  ReportBullet(:final level, :final number) =>
    '${'  ' * level}${number == null ? '-' : '$number.'} '
        '${_inlines(block.inlines)}',
  ReportSubheading() => '### ${_inlines(block.inlines)}',
  ReportQuote() => '> ${_inlines(block.inlines)}',
};

/// Los pedazos en Markdown: la negrita y las palabras clave con `**`, la
/// itálica con `*`.
String _inlines(List<ReportInline> inlines) {
  final out = StringBuffer();
  for (final inline in inlines) {
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
