import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';

/// Las tres de extraer de Repasar (F43, paso 7): **Extraer texto completo**,
/// **Extraer resumen** y **Extraer síntesis**. Son vistas vivas (decisión E):
/// no guardan nada propio; lo que muestran sale, cada vez, del texto del
/// documento procesado y de sus marcas de estudiar (F36, clave
/// `procesado:…`), las mismas que se marcan en el original (M5, M8).
///
/// Acá está lo puro: cómo se parte lo que se muestra, qué marca le hace falta
/// a cada una y cómo se escribe su archivo.

/// Qué marca de estudiar necesita [kind] para mostrarse completa: el texto
/// completo, sus palabras clave; el resumen y la síntesis, sus oraciones.
StudyMarkKind extractNeeds(StudyCreationKind kind) => switch (kind) {
  StudyCreationKind.fullText => StudyMarkKind.keyword,
  StudyCreationKind.summary => StudyMarkKind.summary,
  StudyCreationKind.synthesis => StudyMarkKind.synthesis,
  _ => throw ArgumentError.value(kind, 'kind', 'no es de extraer'),
};

/// Los tipos que se extraen.
const extractKinds = [
  StudyCreationKind.fullText,
  StudyCreationKind.summary,
  StudyCreationKind.synthesis,
];

/// Un tramo `[start, end)` del texto propio del documento, tal cual.
typedef ExtractPiece = ({int start, int end});

/// Lo que se dibuja de una vez en el visor: un párrafo —o unos pocos— del
/// texto entero, o las oraciones del resumen que en el documento están en el
/// mismo párrafo, una detrás de la otra con un espacio.
///
/// Sus tramos son posiciones del texto propio: lo marcado y lo que suena en
/// voz alta caen en su lugar sin traducir nada.
@immutable
class ExtractBlock {
  ExtractBlock(List<ExtractPiece> pieces)
    : assert(pieces.isNotEmpty, 'un bloque sin tramos'),
      pieces = List.unmodifiable(pieces);

  final List<ExtractPiece> pieces;

  int get start => pieces.first.start;
  int get end => pieces.last.end;

  @override
  bool operator ==(Object other) =>
      other is ExtractBlock && listEquals(other.pieces, pieces);

  @override
  int get hashCode => Object.hashAll(pieces);

  @override
  String toString() => 'ExtractBlock($pieces)';
}

/// Cuánto mide, más o menos, un bloque: unos cuatro o cinco párrafos de un
/// teléfono. Un libro entero son miles; la lista arma solo los que se ven.
const kExtractBlockChars = 1200;

/// El texto entero en bloques: los párrafos juntados hasta
/// [kExtractBlockChars], sin partir uno salvo que solo ya sea más largo, y
/// sin los separadores de página de un PDF (`readerPageRanges`, el corte del
/// lector de libros).
List<ExtractBlock> extractTextBlocks(String content) => [
  for (final range in readerPageRanges(
    content,
    targetPageLength: kExtractBlockChars,
  ))
    ExtractBlock([(start: range.start, end: range.end)]),
];

/// Lo mismo que [extractTextBlocks] sin trabar la pantalla: un libro se parte
/// en otro hilo (lo mismo que hace el lector de libros a partir de
/// `kReaderInlineChars`).
Future<List<ExtractBlock>> extractTextBlocksOff(String content) async {
  if (content.length <= kReaderInlineChars) return extractTextBlocks(content);
  final bounds = await compute(_blockBounds, content);
  return [
    for (var i = 0; i < bounds.length; i += 2)
      ExtractBlock([(start: bounds[i], end: bounds[i + 1])]),
  ];
}

List<int> _blockBounds(String content) => [
  for (final block in extractTextBlocks(content)) ...[block.start, block.end],
];

/// Un renglón en blanco: lo que separa un párrafo de otro.
final _paragraphBreak = RegExp(r'\n[ \t]*\n');

/// El comienzo de un bloque de Markdown que no se junta con lo de antes: un
/// título, una viñeta, una lista numerada, una cita.
final _blockStart = RegExp(r'^[ \t]*(?:#{1,6}\s|[-*+]\s|\d{1,9}[.)]\s|>)');

/// Las oraciones de [kind] de [study] en bloques, en el orden del texto: las
/// que en el documento están en el mismo párrafo van juntas —como un párrafo
/// del documento, con lo demás quitado—, y una que empieza otro párrafo, un
/// título o una viñeta, abre el suyo. Ninguno pasa mucho de
/// [kExtractBlockChars]. Las que quedan vacías, fuera
/// (`studySentenceParts`).
List<ExtractBlock> extractSentenceBlocks(
  String content,
  DocumentStudy study,
  StudyMarkKind kind, {
  bool markdown = false,
}) {
  final blocks = <ExtractBlock>[];
  var current = <ExtractPiece>[];
  var size = 0;
  void flush() {
    if (current.isEmpty) return;
    blocks.add(ExtractBlock(current));
    current = [];
    size = 0;
  }

  for (final part in studySentenceParts(content, study, kind)) {
    final piece = _trimmed(content, part.mark.start, part.mark.end);
    if (piece == null) continue;
    if (current.isNotEmpty) {
      final previous = current.last;
      final gap = previous.end <= piece.start
          ? content.substring(previous.end, piece.start)
          : '';
      final newLine = gap.contains('\n');
      final separate =
          _paragraphBreak.hasMatch(gap) ||
          (newLine &&
              markdown &&
              (_startsBlock(content, piece.start) ||
                  _startsBlock(content, previous.start))) ||
          size + piece.end - piece.start > kExtractBlockChars;
      if (separate) flush();
    }
    current.add(piece);
    size += piece.end - piece.start + 1;
  }
  flush();
  return blocks;
}

/// Si el renglón de [offset] en [content] empieza un bloque de Markdown y
/// [offset] está en su comienzo.
bool _startsBlock(String content, int offset) {
  final lineStart = content.lastIndexOf('\n', offset - 1) + 1;
  if (content.substring(lineStart, offset).trim().isNotEmpty) return false;
  final lineEnd = content.indexOf('\n', offset);
  return _blockStart.hasMatch(
    content.substring(lineStart, lineEnd < 0 ? content.length : lineEnd),
  );
}

ExtractPiece? _trimmed(String content, int start, int end) {
  var s = start.clamp(0, content.length);
  var e = end.clamp(s, content.length);
  while (s < e && content[s].trim().isEmpty) {
    s++;
  }
  while (e > s && content[e - 1].trim().isEmpty) {
    e--;
  }
  return s < e ? (start: s, end: e) : null;
}

/// Los bloques de [kind] de un documento, con su texto y lo estudiado: el
/// texto entero o las oraciones de lo que extrae.
List<ExtractBlock> extractBlocksOf(
  StudyCreationKind kind, {
  required String content,
  required DocumentStudy study,
  required bool markdown,
}) => kind == StudyCreationKind.fullText
    ? extractTextBlocks(content)
    : extractSentenceBlocks(
        content,
        study,
        extractNeeds(kind),
        markdown: markdown,
      );

/// Las de [keywords] —en orden— que tocan `[start, end)`, buscando la
/// primera sin recorrer las de antes: un libro tiene decenas de miles, y cada
/// bloque que se dibuja pregunta por las suyas.
List<StudyMark> keywordsWithin(List<StudyMark> keywords, int start, int end) {
  var low = 0;
  var high = keywords.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (keywords[middle].end <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return [
    for (var i = low; i < keywords.length && keywords[i].start < end; i++)
      keywords[i],
  ];
}
