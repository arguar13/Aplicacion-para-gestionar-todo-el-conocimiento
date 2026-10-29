import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

/// Un documento de una extracción, como se escribe en su archivo (F43, paso
/// 7): su título y, si tiene, su texto propio con lo estudiado; si no,
/// [note] dice por qué —«Fuente borrada», «Todavía no tiene resumen»—.
@immutable
class ExtractExportSection {
  const ExtractExportSection({
    required this.title,
    this.content,
    this.markdown = false,
    this.study = DocumentStudy.notStarted,
    this.keywordsShown = true,
    this.note,
  });

  final String title;

  /// El texto propio del documento, o `null` si no tiene.
  final String? content;

  /// Si [content] es Markdown.
  final bool markdown;
  final DocumentStudy study;

  /// Si las palabras clave van resaltadas —en negrita—: la misma preferencia
  /// del documento que se ve en el visor y en el original (M5, M8).
  final bool keywordsShown;

  /// Lo que se escribe en lugar de lo que falta.
  final String? note;
}

/// El Markdown de una extracción de [kind] titulada [title]: el título, y un
/// apartado por documento con su título y lo extraído —el texto entero, o las
/// oraciones del resumen o de la síntesis en párrafos, como se ven—, con las
/// palabras clave en **negrita** si se resaltan. Un apartado sin nada lleva
/// su nota en cursiva.
///
/// Es lo mismo que muestra el visor: los mismos bloques
/// (`extractBlocksOf`), así que lo que se descarga es lo que se lee.
String extractMarkdown({
  required String title,
  required StudyCreationKind kind,
  required List<ExtractExportSection> sections,
}) {
  final out = StringBuffer('# ${_oneLine(title)}\n');
  for (final section in sections) {
    out.write('\n## ${_oneLine(section.title)}\n\n');
    final content = section.content;
    final blocks = content == null
        ? const <ExtractBlock>[]
        : extractBlocksOf(
            kind,
            content: content,
            study: section.study,
            markdown: section.markdown,
          );
    if (content == null || blocks.isEmpty) {
      final note = section.note;
      if (note != null) out.write('_${_oneLine(note)}_\n');
      continue;
    }
    final keywords = section.keywordsShown
        ? section.study.of(StudyMarkKind.keyword)
        : const <StudyMark>[];
    final paragraphs = kind == StudyCreationKind.fullText
        ? [
            for (final block in blocks)
              _boldWithin(content, block.start, block.end, keywords),
          ]
        : [
            for (final block in blocks)
              [
                for (final piece in block.pieces)
                  _sentence(content, piece, keywords),
              ].where((s) => s.isNotEmpty).join(' '),
          ];
    out
      ..write(paragraphs.where((p) => p.isNotEmpty).join('\n\n'))
      ..write('\n');
  }
  return out.toString();
}

/// `[start, end)` de [raw] tal cual —con su formato—, con las palabras clave
/// que caen adentro en negrita.
String _boldWithin(String raw, int start, int end, List<StudyMark> keywords) {
  final out = StringBuffer();
  var cursor = start;
  for (final mark in keywords) {
    if (mark.end <= start || mark.start >= end) continue;
    if (mark.start < cursor) continue;
    final word = raw.substring(mark.start, mark.end);
    if (!_boldable(raw, mark.start, mark.end, word)) continue;
    out
      ..write(raw.substring(cursor, mark.start))
      ..write('**$word**');
    cursor = mark.end;
  }
  out.write(raw.substring(cursor, end));
  return out.toString().trim();
}

/// Una oración del resumen o de la síntesis en un renglón y sin su formato
/// —como se ve en el visor—, con sus palabras clave en negrita.
///
/// Las palabras clave se señalan antes de quitar el formato, con dos
/// caracteres de uso privado que ningún texto trae: así una palabra adentro
/// de un enlace o de una negrita sigue en su lugar cuando el enlace se
/// vuelve su texto, y recién al final se cambian por `**`.
String _sentence(String raw, ExtractPiece piece, List<StudyMark> keywords) {
  final marked = StringBuffer();
  var cursor = piece.start;
  for (final mark in keywords) {
    if (mark.end <= piece.start || mark.start >= piece.end) continue;
    if (mark.start < cursor) continue;
    final end = mark.end > piece.end ? piece.end : mark.end;
    marked
      ..write(raw.substring(cursor, mark.start))
      ..write(_open)
      ..write(raw.substring(mark.start, end))
      ..write(_close);
    cursor = end;
  }
  marked.write(raw.substring(cursor, piece.end));
  final plain = _plain(
    marked.toString().replaceFirst(_linePrefix, ''),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  return plain
      .replaceAllMapped(_markedWord, (m) => '**${m[1]}**')
      .replaceAll(RegExp('[$_open$_close]'), '');
}

/// Una palabra clave señalada, con lo que quedó de ella: si quedó vacía —era
/// solo formato— o con un `*` adentro, se saca la señal y no se pone negrita.
final _markedWord = RegExp(
  '$_open\\s*([^$_open$_close*\\s](?:[^$_open$_close*]*[^$_open$_close*\\s])?)'
  '\\s*$_close',
);

/// Dónde empieza y dónde termina una palabra clave, mientras se quita el
/// formato.
final _open = String.fromCharCode(0xE000);
final _close = String.fromCharCode(0xE001);

/// El `#` de un título, la viñeta, el número o el `>` al comienzo de una
/// oración que empieza un renglón.
final _linePrefix = RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+|\d{1,9}[.)]\s+)');

/// Sin enlaces, sin `**`, `__` ni acentos graves: como `studyPlainText`.
String _plain(String raw) => raw
    .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'\*\*|__|`'), '');

/// Si la palabra clave `[start, end)` de [raw] se puede poner en negrita sin
/// romper el Markdown: en un renglón, sin marcas adentro ni pegadas.
bool _boldable(String raw, int start, int end, String word) {
  if (word.trim().isEmpty || word != word.trim()) return false;
  if (RegExp(r'[\n*_`\[\]<>|]').hasMatch(word)) return false;
  bool marker(int at) => at >= 0 && at < raw.length && '*_`'.contains(raw[at]);
  return !marker(start - 1) && !marker(end);
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
