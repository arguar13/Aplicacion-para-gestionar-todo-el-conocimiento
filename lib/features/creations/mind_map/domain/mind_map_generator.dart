import 'dart:math' as math;

import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_prompt.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Quien genera un mapa mental (F43, paso 9): un solo pedido de JSON
/// (`StructuredWriter.writeStructured`) con el esquema de
/// `mindMapSchemaPrompt`, leído con `MindMapJson.read`.
///
/// **Lo largo, por partes**: cada parte da su rama —un mapa chico con su idea
/// central— y el paso de unir las junta en un solo árbol, sin repetir. Un
/// borrador puede ser una sola rama sin hijos; el mapa final, no.
///
/// **Lo que escribe, según la ventana**: un mapa de unas cincuenta ideas, con
/// su nota y su pasaje, son unos 3.000 tokens. Con un modelo de ventana chica
/// —Gemma en el teléfono— se reserva menos y se piden menos ideas, para que
/// entre material que leer.
class MindMapGenerator extends CreationGenerator {
  const MindMapGenerator();

  /// Lo más que escribe el mapa final.
  static const int replyTokens = 3200;

  /// Lo más que escribe el borrador de una parte.
  static const int partReplyTokens = 1400;

  /// Lo menos que se le deja: menos no alcanza para un mapa con sentido.
  static const int minReplyTokens = 600;

  /// Lo que ocupa una idea en la respuesta, con su nota, su fuente y su
  /// pasaje: con esto se piden tantas ideas como entran.
  static const int tokensPerNode = 60;

  @override
  StudyCreationKind get kind => StudyCreationKind.mindMap;

  @override
  int maxOutputTokens(CreationJob job) => replyTokens;

  /// Lo que se le reserva a la respuesta con una ventana de [contextTokens]:
  /// como mucho [replyTokens], y nunca más del 40 % de la ventana.
  static int replyTokensFor(int contextTokens) => math.max(
    minReplyTokens,
    math.min(replyTokens, (contextTokens * 0.4).floor()),
  );

  /// Cuántas ideas se piden para [tokens] de respuesta: entre 12 y 60.
  static int nodesFor(int tokens) => (tokens ~/ tokensPerNode).clamp(12, 60);

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
    final topic = job.options[CreationOptionKeys.topic];
    final about = topic is String ? topic : null;
    final titles = material.titles;
    final map = await writer.writeStructured(
      StructuredRequest<MindMap>(
        task: mindMapTask(nodesFor(reply), topic: about),
        partTask: mindMapPartTask(nodesFor(partReply), topic: about),
        mergeTask: mindMapMergeTask(nodesFor(reply), topic: about),
        schema: mindMapSchemaPrompt,
        material: material,
        budget: budgetFor(job, writer.contextTokens),
        maxOutputTokens: reply,
        partMaxOutputTokens: partReply,
        parse: (json) => MindMapJson.read(json, sources: titles),
        parsePartial: (json) =>
            MindMapJson.read(json, sources: titles, partial: true),
        languageCode: job.languageCode,
        cancellation: job.cancellation,
        onProgress: progress,
      ),
    );
    progress(1, CreationStep.finishing);
    return CreationOutput(
      title: map.title,
      content: MindMapJson.encodeString(map),
    );
  }
}
