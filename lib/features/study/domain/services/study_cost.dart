import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Lo que ocupa la instrucción de cada pedido de estudiar, en tokens: lo mismo
/// que reserva `studyPartCharBudget` antes de repartir la ventana.
const kStudyInstructionTokens = 600;

/// Lo que va a pedirle a la IA analizar un texto para estudiarlo (F43, paso
/// 15): en cuántos pedidos —uno por parte, como los arma `AnalyzeForStudy`—
/// y cuántos tokens lee y escribe. Es lo que dice el aviso «Con tu IA actual»
/// antes de marcar el resumen, la síntesis o las palabras clave con la IA.
@immutable
class StudyAnalysisPlan {
  const StudyAnalysisPlan({
    required this.parts,
    required this.inputTokens,
    required this.outputTokens,
  });

  static const nothing = StudyAnalysisPlan(
    parts: 0,
    inputTokens: 0,
    outputTokens: 0,
  );

  /// Los pedidos: uno por parte.
  final int parts;

  /// Lo que lee, con la instrucción de cada pedido.
  final int inputTokens;

  /// Lo que escribe como mucho: las líneas de números y la línea `CLAVE` de
  /// cada oración (`studyReplyTokens`).
  final int outputTokens;

  bool get isEmpty => parts == 0;

  @override
  bool operator ==(Object other) =>
      other is StudyAnalysisPlan &&
      other.parts == parts &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(parts, inputTokens, outputTokens);

  @override
  String toString() =>
      'StudyAnalysisPlan($parts partes, $inputTokens → $outputTokens)';
}

/// Lo que falta analizar de [sentences] desde la oración [from], partido
/// como lo parte el análisis ([studyPartEnd] con [charBudget]). Pura.
///
/// Cuenta por parte la instrucción ([kStudyInstructionTokens]) más sus
/// oraciones —con su número entre corchetes— a dos caracteres y medio por
/// token, la misma cuenta con que se reparte la ventana; y lo que contesta,
/// [studyReplyTokens] de sus oraciones.
StudyAnalysisPlan planStudyAnalysis(
  List<StudySentence> sentences, {
  required int from,
  required int charBudget,
}) {
  var parts = 0;
  var input = 0;
  var output = 0;
  var next = from.clamp(0, sentences.length);
  while (next < sentences.length) {
    final end = studyPartEnd(sentences, next, charBudget: charBudget);
    var chars = 0;
    for (var i = next; i < end; i++) {
      chars += sentences[i].length + _numberChars;
    }
    input += kStudyInstructionTokens + (chars * 2 / 5).ceil();
    output += studyReplyTokens(end - next);
    parts++;
    next = end;
  }
  return StudyAnalysisPlan(
    parts: parts,
    inputTokens: input,
    outputTokens: output,
  );
}

/// `[12] ` y el salto de línea de cada oración en el pedido.
const _numberChars = 7;

/// Qué le falta analizar al texto de [job] —lo que está después de hasta
/// dónde se analizó—, en pedidos y tokens: ver [planStudyAnalysis]. Parte el
/// texto en oraciones como el análisis, así que con un libro entero conviene
/// correrlo en otro hilo (`compute`): por eso recibe y devuelve solo datos.
StudyAnalysisPlan planStudyAnalysisOf(StudyPlanJob job) {
  final sentences = splitStudySentences(job.content, markdown: job.markdown);
  final from = sentences.indexWhere((s) => s.start >= job.analyzedUntil);
  return planStudyAnalysis(
    sentences,
    from: from < 0 ? sentences.length : from,
    charBudget: job.charBudget,
  );
}

/// Lo que necesita [planStudyAnalysisOf]: el texto, si es Markdown, hasta
/// dónde se analizó y cuánto entra por parte.
typedef StudyPlanJob = ({
  String content,
  bool markdown,
  int analyzedUntil,
  int charBudget,
});
