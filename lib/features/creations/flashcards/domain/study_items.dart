import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';

/// Una tarjeta de un mazo o una pregunta de un cuestionario (F43, paso 8):
/// lo que comparten para pedirse por partes, juntarse sin repetir y saber de
/// qué documento procesado salen.
abstract interface class StudyItem<T extends StudyItem<T>> {
  /// Lo que dice que dos son la misma: la pregunta, normalizada.
  String get fingerprint;

  /// El título del documento que la IA dijo que es la fuente, si lo dijo.
  String get sourceHint;

  /// El documento procesado del que sale, una vez resuelto.
  String? get documentId;

  /// La misma, con su documento ya resuelto.
  T withDocument(String documentId);
}

/// Lo que leyó una respuesta: el título que propuso la IA y los ítems.
@immutable
class StudyItemBatch<T extends StudyItem<T>> {
  const StudyItemBatch({required this.title, required this.items});

  final String title;
  final List<T> items;
}

/// Cómo se le piden los ítems de un tipo al modelo.
@immutable
class StudyItemsRequest<T extends StudyItem<T>> {
  const StudyItemsRequest({
    required this.count,
    required this.tokensPerItem,
    required this.task,
    required this.schema,
    required this.parse,
    this.guidance,
  });

  /// Cuántos se quieren en total.
  final int count;

  /// Cuánto escribe la IA por ítem, más o menos: con esto se reserva la
  /// respuesta y se sabe cuántos entran en una ventana chica.
  final int tokensPerItem;

  /// La tarea para `count` ítems; `part` si es una parte del material.
  final String Function(int count, {required bool part}) task;

  /// El esquema del JSON.
  final String schema;

  /// Lee la respuesta; lanza [FormatException] si no trae ningún ítem.
  final StudyItemBatch<T> Function(Object? json) parse;

  /// Lo que escribió la persona («Tema»), tal cual.
  final String? guidance;

  /// Lo que se le reserva a una respuesta con [items] ítems.
  int replyTokensFor(int items) => items * tokensPerItem + 200;
}

/// Cuántos ítems entran en una respuesta con la ventana de [contextTokens]:
/// como mucho el 40 % de la ventana para lo que escribe —con Gemma en el
/// teléfono (2.048 tokens), unas ocho tarjetas—, y nunca menos de tres.
int studyItemsThatFit(int contextTokens, int tokensPerItem) =>
    math.max(3, (contextTokens * 0.4 / tokensPerItem).floor());

/// Lo que se reserva para la respuesta de [request] en la ventana de
/// [contextTokens]: lo de los ítems que entran.
int studyItemsReplyTokens(
  StudyItemsRequest<Object?> request,
  int contextTokens,
) => request.replyTokensFor(
  math.min(
    request.count,
    studyItemsThatFit(contextTokens, request.tokensPerItem),
  ),
);

/// Pide los ítems de [request] sobre [material] (F43, paso 8).
///
/// - **De una vez** si el material es de una vez: un solo
///   [StructuredWriter.writeStructured], con tantos ítems como entran en la
///   ventana.
/// - **Por partes** si no: cada parte da los suyos con su propio pedido —en
///   la ventana, con su turno— y se juntan **en la app**, sin un paso más de
///   la IA. Un mazo y un cuestionario son listas de cosas sueltas: unirlos no
///   necesita que nadie los reescriba, y así un libro entero no gasta un
///   pedido de más ni pierde nada al resumir los borradores. Se reparten
///   parejo entre las partes, sin repetir la misma pregunta.
///
/// Una parte que no se pudo leer ni corregida no tira las demás: falla solo
/// si ninguna dio nada. Cada ítem sale con el documento del que viene —el de
/// su parte, el que dijo la IA o, si hay uno solo, ese—.
///
/// [progress] va de 0 a [share]: lo que sigue (las ilustraciones) es de quien
/// llama.
Future<StudyItemBatch<T>> writeStudyItems<T extends StudyItem<T>>({
  required StudyItemsRequest<T> request,
  required CreationJob job,
  required CreationMaterial material,
  required StructuredWriter writer,
  required CreationProgressReport progress,
  double share = 1,
}) async {
  final window = writer.contextTokens;
  final fits = studyItemsThatFit(window, request.tokensPerItem);

  StructuredRequest<StudyItemBatch<T>> ask(
    CreationMaterial on,
    int count, {
    required bool part,
    void Function(double, CreationStep)? onProgress,
  }) {
    final reply = request.replyTokensFor(count);
    return StructuredRequest(
      task: request.task(count, part: part),
      schema: request.schema,
      material: on,
      budget: CreationBudget(
        contextTokens: window,
        reservedOutputTokens: reply,
      ),
      maxOutputTokens: reply,
      parse: request.parse,
      languageCode: job.languageCode,
      guidance: request.guidance,
      cancellation: job.cancellation,
      onProgress: onProgress,
    );
  }

  if (material.mode.isSingle) {
    final count = math.min(request.count, fits);
    final batch = await writer.writeStructured(
      ask(
        material,
        count,
        part: false,
        onProgress: (value, step) => progress(value * share, step),
      ),
    );
    return StudyItemBatch(
      title: batch.title,
      items: _unique([
        for (final item in batch.items) _withSource(item, material),
      ]).take(request.count).toList(),
    );
  }

  final parts = material.parts;
  if (parts.isEmpty) {
    throw const UnreadableStructuredReply('No hay partes que leer.');
  }
  final perPart = math.min(
    fits,
    math.max(2, (request.count / parts.length).ceil()),
  );
  final found = <List<T>>[];
  final titles = <String>[];
  UnreadableStructuredReply? lastError;
  for (final (index, part) in parts.indexed) {
    if (job.cancellation.isCancelled) throw const CreationCancelledException();
    progress(index / parts.length * share, CreationStep.readingParts);
    final source = [
      for (final s in material.sources)
        if (s.documentId == part.documentId) s,
    ];
    final StudyItemBatch<T> batch;
    try {
      batch = await writer.writeStructured(
        ask(
          CreationMaterial(
            mode: CreationMaterialMode.fullText,
            text: part.text,
            sources: source,
          ),
          perPart,
          part: true,
        ),
      );
    } on UnreadableStructuredReply catch (error) {
      lastError = error;
      continue;
    }
    titles.add(batch.title);
    found.add([
      for (final item in batch.items) item.withDocument(part.documentId),
    ]);
  }
  if (found.every((items) => items.isEmpty)) {
    throw lastError ??
        const UnreadableStructuredReply('Ninguna parte dio nada que leer.');
  }
  progress(share, CreationStep.joining);
  return StudyItemBatch(
    title: material.sources.length == 1
        ? material.sources.single.title
        : titles.firstWhere((t) => t.trim().isNotEmpty, orElse: () => ''),
    items: spreadStudyItems(found, request.count),
  );
}

/// [lists] —los ítems de cada parte, en orden— juntadas en una de [count]
/// como mucho, sin repetir y repartidas parejo: de a una de cada parte, en
/// vueltas, y al final en el orden del material.
List<T> spreadStudyItems<T extends StudyItem<T>>(
  List<List<T>> lists,
  int count,
) {
  final seen = <String>{};
  final queues = [
    for (final list in lists)
      [
        for (final item in list)
          if (seen.add(item.fingerprint)) item,
      ],
  ];
  // Cuántos toma cada parte: de a uno por vuelta, mientras queden.
  final taken = List.filled(queues.length, 0);
  var total = 0;
  var progressed = true;
  while (total < count && progressed) {
    progressed = false;
    for (var i = 0; i < queues.length && total < count; i++) {
      if (taken[i] < queues[i].length) {
        taken[i]++;
        total++;
        progressed = true;
      }
    }
  }
  return [for (var i = 0; i < queues.length; i++) ...queues[i].take(taken[i])];
}

/// [items] sin la misma pregunta dos veces, en orden.
List<T> _unique<T extends StudyItem<T>>(List<T> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(item.fingerprint)) item,
  ];
}

/// [item] con su documento: el que nombró la IA si se reconoce entre las
/// fuentes del material; si no, el primero.
T _withSource<T extends StudyItem<T>>(T item, CreationMaterial material) {
  final sources = material.sources;
  if (sources.isEmpty) return item;
  final hint = normalizeVocabularyLabel(item.sourceHint);
  if (hint.isNotEmpty && sources.length > 1) {
    for (final source in sources) {
      final title = normalizeVocabularyLabel(source.title);
      if (title.isNotEmpty && (title == hint || title.contains(hint))) {
        return item.withDocument(source.documentId);
      }
    }
    for (final source in sources) {
      final title = normalizeVocabularyLabel(source.title);
      if (title.isNotEmpty && hint.contains(title)) {
        return item.withDocument(source.documentId);
      }
    }
  }
  return item.withDocument(sources.first.documentId);
}
