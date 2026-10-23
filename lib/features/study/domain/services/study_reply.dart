import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/study/domain/services/study_extracts.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Cuántas oraciones se le dan al modelo, como mucho, en una parte (F36): con
/// un modelo en la nube la ventana no es el límite, pero lo que contesta sí
/// —las palabras clave de cada oración—, y un pedido más chico se lee con
/// más cuidado.
const kMaxStudyPartSentences = 120;

/// Lo que ocupa una oración además de su texto, en caracteres: en el pedido,
/// su número entre corchetes y el salto de línea; en la respuesta, su línea
/// `CLAVE` —ver [studyReplyTokens]—, a dos caracteres y medio por token. Cada
/// oración trae su respuesta (F39): una parte que entra con sus palabras
/// clave no se corta a mitad de la respuesta.
const _perSentenceOverhead = 7 + _keywordLineTokens * 5 ~/ 2;

/// Lo que escribe el modelo por oración: `CLAVE 12: palabra, palabra,
/// palabra, palabra`, y su parte de las líneas de números.
const _keywordLineTokens = 22;

/// Hasta dónde llega la parte que empieza en la oración [from]: el índice de
/// la primera oración que ya no entra.
///
/// Entran las que quepan en [charBudget] caracteres —al menos una, aunque sea
/// más larga: si no, una oración enorme no se analizaría nunca— y hasta
/// [kMaxStudyPartSentences].
int studyPartEnd(
  List<StudySentence> sentences,
  int from, {
  required int charBudget,
}) {
  var used = 0;
  var end = from;
  while (end < sentences.length && end - from < kMaxStudyPartSentences) {
    final cost = sentences[end].length + _perSentenceOverhead;
    if (end > from && used + cost > charBudget) break;
    used += cost;
    end++;
  }
  return end;
}

/// Cuántos caracteres de oraciones conviene darle por parte a un modelo con
/// una ventana de [contextTokens] tokens (F36): lo que queda después de la
/// instrucción y un margen, a unos dos caracteres y medio por token. Lo que
/// contesta por cada oración lo cuenta `studyPartEnd`, oración por oración.
/// Con Gemma en el teléfono, unas treinta oraciones; con un modelo en la nube
/// el límite es [kMaxStudyPartSentences], no la ventana.
int studyPartCharBudget(int contextTokens) =>
    ((contextTokens - 600) * 5 ~/ 2).clamp(800, 15000);

/// Cuántos tokens puede escribir el modelo para una parte de [count]
/// oraciones: las dos líneas de números y, por **cada** oración, su línea
/// `CLAVE` con hasta cuatro palabras (F39).
int studyReplyTokens(int count) =>
    (count * _keywordLineTokens + 96).clamp(192, 3072);

/// El pedido de una parte: sus oraciones, numeradas desde 1, cada una en un
/// renglón y sin las marcas de Markdown —el modelo lee lo que se lee—.
String buildStudyPrompt(String content, List<StudySentence> part) {
  final buffer = StringBuffer('Oraciones del documento:\n');
  for (final (index, sentence) in part.indexed) {
    final text = studyPlainText(
      content.substring(sentence.start, sentence.end),
    );
    buffer.writeln('[${index + 1}] $text');
  }
  return buffer.toString().trimRight();
}

/// Lo que la IA marcó en una parte (F36), ya en el texto guardado: las
/// oraciones del resumen, las de la síntesis y las palabras clave de todas
/// sus oraciones (F39).
@immutable
class StudyPartMarks {
  const StudyPartMarks({
    required this.summary,
    required this.synthesis,
    required this.keywords,
  });

  final List<StudySentence> summary;
  final List<StudySentence> synthesis;
  final List<StudyWord> keywords;
}

/// Lee lo que contestó el modelo para [part] —ver `buildStudyPrompt`—, en el
/// formato que le pide `LanguageModelTasks`:
///
/// ```text
/// RESUMEN: 1, 3, 5-7
/// SINTESIS: 3
/// CLAVE 1: revolución, industrial
/// CLAVE 3: vapor | fábricas
/// ```
///
/// Con tolerancia a lo que un modelo chico cambia —acentos, mayúsculas,
/// viñetas, negritas, rangos, «ninguna»—, pero sin creerle nada que no esté:
/// un número fuera de la parte se descarta, y una palabra clave solo cuenta si
/// está en su oración (`pickKeywords`). Las palabras clave van en **todas**
/// las oraciones, estén o no en el resumen o en la síntesis (F39): se
/// estudian de punta a punta del documento.
///
/// `null` si no hay ni una línea de resumen ni una de síntesis: el modelo no
/// contestó en el formato y la parte no está analizada —otra cosa es que
/// conteste en el formato sin marcar ninguna—.
StudyPartMarks? parseStudyReply(
  String reply, {
  required String content,
  required List<StudySentence> part,
}) {
  List<int>? summary;
  List<int>? synthesis;
  final proposed = <int, List<String>>{};

  for (final rawLine in reply.split('\n')) {
    final line = _plainLine(rawLine);
    if (line.isEmpty) continue;

    final numbers = _numbersLine.firstMatch(line);
    if (numbers != null) {
      final indexes = _numbersIn(numbers[2]!, part.length);
      if (numbers[1]!.startsWith('res')) {
        summary = [...?summary, ...indexes];
      } else {
        synthesis = [...?synthesis, ...indexes];
      }
      continue;
    }

    final keywords = _keywordsLine.firstMatch(line);
    if (keywords != null) {
      final index = int.parse(keywords[1]!) - 1;
      if (index < 0 || index >= part.length) continue;
      proposed[index] = [
        ...?proposed[index],
        ...keywords[2]!
            .split(RegExp('[,;|/]'))
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty),
      ];
    }
  }

  if (summary == null && synthesis == null) return null;

  final summaryIndexes = {...?summary}.toList()..sort();
  final synthesisIndexes = {...?synthesis}.toList()..sort();

  return StudyPartMarks(
    summary: [for (final i in summaryIndexes) part[i]],
    synthesis: [for (final i in synthesisIndexes) part[i]],
    keywords: [
      for (final i in proposed.keys.toList()..sort())
        ...pickKeywords(content, part[i], proposed[i]!),
    ],
  );
}

/// [line] en minúsculas, sin acentos en las etiquetas y sin lo que un modelo
/// le pone alrededor —viñetas, negritas, comillas—.
String _plainLine(String line) => line
    .replaceAll(RegExp('[*_`"«»]'), '')
    .replaceFirst(RegExp(r'^\s*[-•>]+\s*'), '')
    .trim()
    .toLowerCase()
    .replaceAll('í', 'i')
    .replaceAll('é', 'e');

/// `RESUMEN: …` o `SINTESIS: …`, y lo que sigue.
final _numbersLine = RegExp(r'^(resumen|sintesis)\s*[:=-]\s*(.*)$');

/// `CLAVE <n>: …`, `CLAVES <n>: …` o `CLAVE [n]: …`.
final _keywordsLine = RegExp(r'^claves?\s*\[?(\d+)\]?\s*[:=-]\s*(.*)$');

/// Los índices —desde 0— que nombra [text]: números y rangos `a-b`, dentro de
/// la parte. «ninguna», «-» o nada: ninguno.
List<int> _numbersIn(String text, int count) {
  final indexes = <int>[];
  for (final match in RegExp(r'(\d+)\s*(?:[-–]\s*(\d+))?').allMatches(text)) {
    final from = int.parse(match[1]!);
    final to = match[2] == null ? from : int.parse(match[2]!);
    // Un rango desmedido es un error del modelo, no un pedido; uno al revés
    // no recorre nada.
    if (to - from > count) continue;
    for (var n = from; n <= to; n++) {
      if (n >= 1 && n <= count) indexes.add(n - 1);
    }
  }
  return indexes;
}
