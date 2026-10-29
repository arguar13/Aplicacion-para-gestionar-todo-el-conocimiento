import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// [report] como lo dibuja la app: sin secciones vacías y, en el glosario,
/// en orden alfabético de verdad.
///
/// El orden del glosario no se le confía a la IA: por partes, cada parte da
/// sus términos y unirlos los desordena —y un modelo chico no ordena bien—.
/// Acá se juntan todos los términos, se sacan los repetidos, se ordenan sin
/// tildes ni mayúsculas y se agrupan por su letra; cada pregunta del
/// interactivo va a la letra del término del que habla.
Report normalizeReport(Report report, ReportTemplate template) {
  final sections = [
    for (final section in report.sections)
      if (section.hasContent || section.questions.isNotEmpty) section,
  ];
  final normalized = report.copyWith(sections: sections);
  if (template != ReportTemplate.glossary) return normalized;
  return _alphabetical(normalized);
}

Report _alphabetical(Report report) {
  final entries = <ReportEntry>[];
  final seen = <String>{};
  final questions = <(ReportQuestion, String)>[];
  final prose = <ReportSection>[];
  for (final section in report.sections) {
    final own = section.entries.isNotEmpty
        ? section.entries
        : _entriesFromBullets(section.body);
    for (final entry in own) {
      if (seen.add(_sortKey(entry.term))) entries.add(entry);
    }
    for (final question in section.questions) {
      questions.add((question, section.title));
    }
    // Lo que no es un término —una introducción— queda arriba, como está.
    if (own.isEmpty && section.body.trim().isNotEmpty) {
      prose.add(section.copyWith(questions: const []));
    }
  }
  if (entries.isEmpty) return report;
  entries.sort((a, b) => _sortKey(a.term).compareTo(_sortKey(b.term)));

  final byLetter = <String, List<ReportEntry>>{};
  for (final entry in entries) {
    byLetter.putIfAbsent(_letterOf(entry.term), () => []).add(entry);
  }
  final letters = byLetter.keys.toList();
  final attached = {for (final letter in letters) letter: <ReportQuestion>[]};
  for (final (question, title) in questions) {
    final letter = _letterFor(question, title, entries, letters);
    if (attached[letter]!.length < ReportLimits.questions) {
      attached[letter]!.add(question);
    }
  }
  return report.copyWith(
    sections: [
      ...prose,
      for (final letter in letters)
        ReportSection(
          title: letter,
          entries: byLetter[letter]!,
          questions: attached[letter]!,
        ),
    ],
  );
}

/// La letra del término del que habla [question]: el primero que nombra su
/// enunciado o su respuesta; si no nombra ninguno, la de la sección donde la
/// puso la IA; y si tampoco, la última.
String _letterFor(
  ReportQuestion question,
  String sectionTitle,
  List<ReportEntry> entries,
  List<String> letters,
) {
  final said =
      ' ${foldStudyWord('${question.question} ${question.correct.text}')} ';
  for (final entry in entries) {
    final term = foldStudyWord(entry.term);
    if (term.isNotEmpty && said.contains(' $term ')) {
      return _letterOf(entry.term);
    }
  }
  final fromTitle = _letterOf(sectionTitle);
  return letters.contains(fromTitle) ? fromTitle : letters.last;
}

/// Cómo se ordena un término: sin tildes ni mayúsculas.
String _sortKey(String term) => foldStudyWord(term);

/// La letra de un término, en mayúscula y sin tilde; «#» si empieza con un
/// número o un signo.
String _letterOf(String term) {
  final key = _sortKey(term);
  if (key.isEmpty) return '#';
  final first = key[0];
  return RegExp(r'\p{L}', unicode: true).hasMatch(first)
      ? first.toUpperCase()
      : '#';
}

final _termBullet = RegExp(
  r'^\s*(?:[-*•·–]\s+)?\*\*(.+?)\*\*\s*[:—–-]?\s*(.*)$',
);

/// Los términos de un glosario escrito como viñetas («- **Término**:
/// definición»), si la IA no usó el campo de los términos. Vacío si alguna
/// línea con texto no tiene esa forma: entonces no es una lista de términos.
List<ReportEntry> _entriesFromBullets(String body) {
  final entries = <ReportEntry>[];
  for (final line in body.split('\n')) {
    if (line.trim().isEmpty) continue;
    final match = _termBullet.firstMatch(line);
    if (match == null) return const [];
    entries.add(
      ReportEntry(
        term: match.group(1)!.trim(),
        definition: match.group(2)!.trim(),
      ),
    );
  }
  return entries;
}
