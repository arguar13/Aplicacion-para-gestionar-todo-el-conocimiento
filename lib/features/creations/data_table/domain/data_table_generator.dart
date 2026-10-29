import 'dart:math' as math;

import 'package:sinapsis/features/creations/data_table/domain/data_table_prompt.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table_json.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Quien genera una tabla de datos (F43, paso 9): un solo pedido de JSON
/// (`StructuredWriter.writeStructured`) con el esquema de
/// `dataTableSchemaPrompt`, leído con `StudyTableJson.read`.
///
/// **La «Descripción»** de la hoja dice qué columnas quiere la persona: va
/// tal cual con la tarea (es lo que pidió), y la tarea le dice a la IA que
/// use esas columnas, con esos nombres y en ese orden. Sin descripción, la
/// IA elige las que mejor resumen el material.
///
/// **Lo largo, por partes**: cada parte da sus filas —con las columnas
/// pedidas, o unas que sirvan para todo el material— y el paso de unir las
/// junta en una sola tabla, sin filas repetidas.
///
/// **Lo que escribe, según la ventana**: unas cuarenta filas de cinco
/// columnas son unos 2.600 tokens; con un modelo de ventana chica se reserva
/// menos y se piden menos filas.
class DataTableGenerator extends CreationGenerator {
  const DataTableGenerator();

  static const int replyTokens = 2600;
  static const int partReplyTokens = 1200;
  static const int minReplyTokens = 500;

  /// Lo que ocupa una fila en la respuesta: unas cinco celdas cortas.
  static const int tokensPerRow = 64;

  @override
  StudyCreationKind get kind => StudyCreationKind.dataTable;

  @override
  int maxOutputTokens(CreationJob job) => replyTokens;

  /// Lo que se le reserva a la respuesta con una ventana de [contextTokens]:
  /// como mucho [replyTokens], y nunca más del 40 % de la ventana.
  static int replyTokensFor(int contextTokens) => math.max(
    minReplyTokens,
    math.min(replyTokens, (contextTokens * 0.4).floor()),
  );

  /// Cuántas filas se piden para [tokens] de respuesta: entre 6 y 40.
  static int rowsFor(int tokens) => (tokens ~/ tokensPerRow).clamp(6, 40);

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: replyTokensFor(contextTokens),
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final reply = replyTokensFor(writer.contextTokens);
    final partReply = math.min(reply, partReplyTokens);
    final raw = job.options[CreationOptionKeys.description];
    final description = raw is String && raw.trim().isNotEmpty
        ? raw.trim()
        : null;
    final wants = description != null;
    final table = await writer.writeStructured(
      StructuredRequest<StudyTable>(
        task: dataTableTask(rowsFor(reply), wantsColumns: wants),
        partTask: dataTablePartTask(rowsFor(partReply), wantsColumns: wants),
        mergeTask: dataTableMergeTask(rowsFor(reply), wantsColumns: wants),
        schema: dataTableSchemaPrompt,
        material: material,
        budget: budgetFor(job, writer.contextTokens),
        maxOutputTokens: reply,
        partMaxOutputTokens: partReply,
        parse: StudyTableJson.read,
        guidance: description,
        languageCode: job.languageCode,
        cancellation: job.cancellation,
        onProgress: progress,
      ),
    );
    progress(1, CreationStep.finishing);
    return CreationOutput(
      title: table.title,
      content: StudyTableJson.encodeString(table),
    );
  }
}
