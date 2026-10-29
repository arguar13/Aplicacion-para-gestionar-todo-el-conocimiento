import 'dart:math' as math;

import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_normalize.dart';
import 'package:sinapsis/features/creations/report/domain/report_prompt.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';

/// Lo que se le deja en la ventana a la instrucción de un informe: la tarea
/// con la guía de su plantilla y el esquema, que con las preguntas del
/// interactivo es más largo que el de otros tipos.
const kReportInstructionTokens = 900;

/// Cuánto de la ventana puede ocupar la respuesta, como mucho: con Gemma
/// (2048 tokens) quedan ~900 para escribir y lo demás para leer, por partes.
const _windowShareForReply = 0.45;

/// Lo menos que se le deja escribir a un informe: menos no da ni para dos
/// secciones.
const _minReplyTokens = 600;

/// Lo que escribe cada parte, por partes, como mucho: un borrador, no el
/// informe entero.
const _maxPartReplyTokens = 1400;

/// Quien genera los informes (F43, punto 4 del plan): un solo pedido de JSON
/// (`StructuredWriter.writeStructured`) con la estructura de la plantilla
/// elegida —o la propia, escrita con ✎—, en el idioma de la creación, con
/// las preguntas de cada sección si es interactivo. Lo largo va por partes:
/// cada parte da el borrador de sus secciones y el último paso las une en la
/// estructura de la plantilla. Lo que devuelve pasa por [normalizeReport]
/// antes de guardarse (el glosario, en orden alfabético de verdad).
class ReportGenerator extends CreationGenerator {
  const ReportGenerator();

  @override
  StudyCreationKind get kind => StudyCreationKind.report;

  /// Lo que pide la plantilla y el formato, sin mirar la ventana: lo que
  /// estima la hoja (`reportOutputTokens`).
  @override
  int maxOutputTokens(CreationJob job) => reportOutputTokens(job.options);

  /// La respuesta que entra en una ventana de [contextTokens]: lo de la
  /// plantilla, sin pasarse de casi la mitad de la ventana.
  int replyTokensFor(CreationJob job, int contextTokens) => math.max(
    _minReplyTokens,
    math.min(
      maxOutputTokens(job),
      (contextTokens * _windowShareForReply).floor(),
    ),
  );

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: replyTokensFor(job, contextTokens),
        instructionTokens: kReportInstructionTokens,
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final template = ReportTemplate.of(job.options);
    final format = ReportFormat.of(job.options);
    final custom = reportCustomTemplateOf(job.options);
    final reply = replyTokensFor(job, writer.contextTokens);
    progress(
      0,
      material.mode.isSingle ? CreationStep.writing : CreationStep.readingParts,
    );
    final report = await writer.writeStructured(
      StructuredRequest<Report>(
        task: reportTask(template: template, format: format, custom: custom),
        schema: reportJsonSchemaPrompt(template: template, format: format),
        material: material,
        budget: budgetFor(job, writer.contextTokens),
        maxOutputTokens: reply,
        parse: parseReportReply,
        languageCode: job.languageCode,
        partTask: reportPartTask(template: template, format: format),
        mergeTask: reportMergeTask(
          template: template,
          format: format,
          custom: custom,
        ),
        partMaxOutputTokens: math.min(reply, _maxPartReplyTokens),
        cancellation: job.cancellation,
        onProgress: progress,
      ),
    );
    if (job.cancellation.isCancelled) throw const CreationCancelledException();
    progress(1, CreationStep.finishing);
    final normalized = normalizeReport(report, template);
    final title = normalized.title.isNotEmpty
        ? normalized.title
        : material.sources.isEmpty
        ? ''
        : material.sources.first.title;
    return CreationOutput(
      title: title,
      // La versión 1 del esquema: la de fábrica de `CreationOutput`.
      content: ReportJson.encodeString(normalized.copyWith(title: title)),
    );
  }
}

/// Lee lo que contestó la IA; lanza [FormatException] —lo que se le dice al
/// modelo para que lo corrija— si no trae ninguna sección con algo para
/// leer.
Report parseReportReply(Object? json) {
  final report = ReportJson.tryDecode(json);
  if (report == null) {
    throw const FormatException(
      'El informe no trae ninguna sección con título y texto en "sections".',
    );
  }
  return report;
}
