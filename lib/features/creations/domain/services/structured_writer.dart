import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_json.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Quien escribe un JSON con un esquema dado (F43, decisión G): el modelo de
/// lenguaje elegido —Gemma en el teléfono o el de la nube—, por el mismo lugar
/// que las tarjetas y el quiz. Lo implementa `LanguageModelTasks`: la
/// instancia de la persona («Generar ahora», con su turno y su cuota) o la de
/// la cola de fondo («Generar más tarde», `LanguageModelTasks.background`, con
/// su tope del día).
///
/// Lo que cada tipo pide —su instrucción, su esquema, cómo se lee— vive en el
/// tipo (`lib/features/creations/<tipo>/`), nunca acá ni en
/// `LanguageModelTasks`: esto es solo el pedido genérico.
abstract interface class StructuredWriter {
  /// La ventana del modelo, en tokens: con ella se arma el material
  /// ([CreationBudget]).
  int get contextTokens;

  /// Le pide al modelo lo de [request] y devuelve lo que lee
  /// [StructuredRequest.parse]:
  ///
  /// - **De una vez** si el material es de una vez: una instrucción con la
  ///   tarea, el idioma y el esquema, y el material.
  /// - **Por partes** si el material va por partes: cada parte da su borrador
  ///   en el mismo esquema (el «map»), y un último paso los une en uno
  ///   (el «reduce»); si los borradores juntos no entran en la ventana, se
  ///   unen de a grupos que entran, y después los grupos, hasta que queda uno.
  /// - **Con tolerancia** ([extractJsonValue]): un bloque de código, una frase
  ///   antes o una coma de más no rompen nada.
  /// - **Con una corrección**: si lo que contesta no se puede leer —no es JSON,
  ///   o [StructuredRequest.parse] lanza [FormatException]—, se le devuelve su
  ///   respuesta con el motivo y se le pide UNA vez que la corrija. Si
  ///   tampoco, lanza [UnreadableStructuredReply].
  /// - **Cancelable**: con [StructuredRequest.cancellation] cancelada, corta lo
  ///   que se esté escribiendo y lanza [CreationCancelledException].
  /// - **Con el turno que le toca** a esta instancia (F27): la de la persona lo
  ///   pide primero; la de fondo espera y cede el paso, y repite lo cortado.
  ///   Cada llamada pide su propio turno: entre una parte y la siguiente, la
  ///   persona puede usar el modelo.
  /// - **Contado**: con un modelo en la nube, cada pedido suma en lo gastado de
  ///   la cuenta (`AiUsageLedger`), como cualquier otro.
  Future<T> writeStructured<T>(StructuredRequest<T> request);
}

/// Lo que un tipo de creación le pide al modelo (F43): ver
/// [StructuredWriter.writeStructured].
@immutable
class StructuredRequest<T> {
  const StructuredRequest({
    required this.task,
    required this.schema,
    required this.material,
    required this.budget,
    required this.maxOutputTokens,
    required this.parse,
    this.languageCode = 'es',
    this.guidance,
    this.partTask,
    this.mergeTask,
    this.partMaxOutputTokens,
    this.parsePartial,
    this.cancellation,
    this.onProgress,
  });

  /// Qué armar, en infinitivo y en español: «armar un mapa mental con las
  /// ideas del material, de lo general a lo particular».
  final String task;

  /// La forma del JSON, dicha para el modelo: un ejemplo con comentarios
  /// cortos, o una descripción campo por campo. Breve: con Gemma, la
  /// instrucción y el esquema entran en [CreationBudget.instructionTokens].
  final String schema;

  /// Lo que se lee (`CreationMaterialBuilder`).
  final CreationMaterial material;

  /// Con qué se armó [material]: dice cuánto entra al unir los borradores.
  final CreationBudget budget;

  /// El tope de la respuesta final.
  final int maxOutputTokens;

  /// Lee el JSON ya decodificado; lanza [FormatException] con un motivo corto
  /// si no tiene la forma del esquema —ese motivo es lo que se le dice al
  /// modelo al pedirle que lo corrija—.
  final T Function(Object? json) parse;

  /// En qué idioma escribir el contenido (`es`, `en`…).
  final String languageCode;

  /// Lo que la persona escribió en «Describí lo que querés crear», y los temas
  /// sugeridos que tocó: va con la tarea, tal cual.
  final String? guidance;

  /// Qué armar con UNA parte, por partes; si falta, un borrador de [task] solo
  /// con esa parte.
  final String? partTask;

  /// Qué hacer con los borradores, por partes; si falta, unirlos en uno solo
  /// sin repetir y sin perder lo importante.
  final String? mergeTask;

  /// El tope de la respuesta de cada parte; si falta, [maxOutputTokens].
  final int? partMaxOutputTokens;

  /// Lee el borrador de una parte; si falta, [parse]. Un borrador puede ser
  /// más laxo que el final —un mapa con una sola rama—.
  final Object? Function(Object? json)? parsePartial;

  /// Para cortarlo a mitad.
  final CancellationSignal? cancellation;

  /// Cuánto va (de 0 a 1) y en qué paso.
  final void Function(double progress, CreationStep step)? onProgress;
}

/// La IA no devolvió el JSON pedido, ni después de pedirle que lo corrija.
class UnreadableStructuredReply implements Exception {
  const UnreadableStructuredReply(this.reason);

  /// El último motivo: lo que no se pudo leer.
  final String reason;

  @override
  String toString() => 'UnreadableStructuredReply: $reason';
}

/// Se canceló una creación mientras se escribía.
class CreationCancelledException implements Exception {
  const CreationCancelledException();

  @override
  String toString() => 'Se canceló la creación.';
}

/// Un pedido de una sola vuelta, como lo arma [runStructuredRequest] para
/// quien habla con el modelo: la instrucción de sistema, lo fijo del pedido
/// ([lead]) y lo que se lee ([material]), que es lo único que se puede achicar
/// si con el tokenizador del modelo no entra.
@immutable
class StructuredCall {
  const StructuredCall({
    required this.instruction,
    required this.lead,
    required this.material,
    required this.maxOutputTokens,
  });

  final String instruction;
  final String lead;
  final String material;
  final int maxOutputTokens;

  /// El pedido entero.
  String get prompt => '$lead$material';
}

/// Lo que habla con el modelo: manda [call] y da la respuesta entera.
typedef StructuredCaller = Future<String> Function(StructuredCall call);

/// Lo que hace [StructuredWriter.writeStructured], sin saber de qué modelo ni
/// de qué turno: [call] es quien habla con él (`LanguageModelTasks` le pone su
/// turno, su motor y el corte). Se separa para que la orquestación —de una
/// vez o por partes, la corrección, el avance, la cancelación— se pruebe sola
/// y viva fuera de `language_model_tasks.dart`.
Future<T> runStructuredRequest<T>(
  StructuredRequest<T> request,
  StructuredCaller call,
) async {
  final material = request.material;
  final progress = request.onProgress;
  _throwIfCancelled(request);

  if (material.mode.isSingle) {
    progress?.call(0, CreationStep.writing);
    final json = await _ask(
      request,
      call,
      instruction: structuredInstruction(
        task: _withGuidance(request.task, request.guidance),
        schema: request.schema,
        languageCode: request.languageCode,
      ),
      lead: 'Material:\n\n',
      material: material.text ?? '',
      maxOutputTokens: request.maxOutputTokens,
      validate: request.parse,
    );
    final result = request.parse(json);
    progress?.call(1, CreationStep.writing);
    return result;
  }

  // Por partes: un borrador por parte.
  final parts = material.parts;
  if (parts.isEmpty) {
    throw const UnreadableStructuredReply('No hay partes que leer.');
  }
  final partTask =
      request.partTask ??
      'armar un borrador parcial de lo siguiente, solo con esta parte del '
          'material: ${request.task}';
  final drafts = <String>[];
  // Una parte más para el paso final: ningún avance llega a 1 antes de unir.
  final steps = parts.length + 1;
  for (final (index, part) in parts.indexed) {
    _throwIfCancelled(request);
    progress?.call(index / steps, CreationStep.readingParts);
    final json = await _ask(
      request,
      call,
      instruction: structuredInstruction(
        task: _withGuidance(partTask, request.guidance),
        schema: request.schema,
        languageCode: request.languageCode,
      ),
      lead:
          'Parte ${index + 1} de ${parts.length} del material (las demás se '
          'leen aparte):\n\n',
      material: part.text,
      maxOutputTokens: request.partMaxOutputTokens ?? request.maxOutputTokens,
      validate: request.parsePartial ?? request.parse,
    );
    drafts.add(jsonEncode(json));
  }

  // Unir: de a grupos que entran, hasta que queda uno. Con una sola parte, su
  // borrador ya es el final si se lee como tal.
  if (drafts.length == 1) {
    final only = jsonDecode(drafts.single);
    try {
      final result = request.parse(only);
      progress?.call(1, CreationStep.joining);
      return result;
    } on FormatException {
      // Un borrador laxo: se lo pasa igual por el paso de unir.
    }
  }
  final mergeTask =
      request.mergeTask ??
      'unir en uno solo los borradores parciales que se te dan —cada uno se '
          'armó con una parte del material—, sin repetir nada y sin perder '
          'nada importante, para lograr esto: ${request.task}';
  final instruction = structuredInstruction(
    task: _withGuidance(mergeTask, request.guidance),
    schema: request.schema,
    languageCode: request.languageCode,
  );
  var round = drafts;
  while (true) {
    _throwIfCancelled(request);
    progress?.call(parts.length / steps, CreationStep.joining);
    final groups = groupDrafts(round, request.budget.inputChars);
    final merged = <Object?>[];
    for (final group in groups) {
      _throwIfCancelled(request);
      final last = groups.length == 1;
      merged.add(
        await _ask(
          request,
          call,
          instruction: instruction,
          lead: 'Borradores parciales, en el orden del material:\n\n',
          material: [
            for (final (i, draft) in group.indexed)
              'Borrador ${i + 1}:\n$draft',
          ].join('\n\n'),
          maxOutputTokens: last
              ? request.maxOutputTokens
              : request.partMaxOutputTokens ?? request.maxOutputTokens,
          validate: last
              ? request.parse
              : (request.parsePartial ?? request.parse),
        ),
      );
    }
    if (merged.length == 1) {
      final result = request.parse(merged.single);
      progress?.call(1, CreationStep.joining);
      return result;
    }
    round = [for (final json in merged) jsonEncode(json)];
  }
}

/// [drafts] en grupos de a varios cuyo texto junto entra en [maxChars], en
/// orden; uno que solo ya no entra va solo. Siempre al menos dos por grupo si
/// hay más de uno —si no, unir no avanzaría nunca—.
List<List<String>> groupDrafts(List<String> drafts, int maxChars) {
  final groups = <List<String>>[];
  var current = <String>[];
  var size = 0;
  for (final draft in drafts) {
    final length = draft.length + 16;
    if (current.length >= 2 && size + length > maxChars) {
      groups.add(current);
      current = [];
      size = 0;
    }
    current.add(draft);
    size += length;
  }
  if (current.isNotEmpty) {
    // Uno suelto al final se une al grupo anterior: un grupo de uno no une
    // nada.
    if (current.length == 1 && groups.isNotEmpty) {
      groups.last.add(current.single);
    } else {
      groups.add(current);
    }
  }
  return groups;
}

/// Un pedido con su corrección: lo que lee [validate] de la respuesta, o, si
/// no se puede, lo de la respuesta a «corregí esto» —una sola vez—.
Future<Object?> _ask<T>(
  StructuredRequest<T> request,
  StructuredCaller call, {
  required String instruction,
  required String lead,
  required String material,
  required int maxOutputTokens,
  required Object? Function(Object? json) validate,
}) async {
  final reply = await call(
    StructuredCall(
      instruction: instruction,
      lead: lead,
      material: material,
      maxOutputTokens: maxOutputTokens,
    ),
  );
  _throwIfCancelled(request);
  try {
    final json = extractJsonValue(reply);
    validate(json);
    return json;
  } on FormatException catch (first) {
    _throwIfCancelled(request);
    final repaired = await call(
      StructuredCall(
        instruction: instruction,
        lead: repairLead(first.message),
        material: _clip(reply, kMaxRepairReplyChars),
        maxOutputTokens: maxOutputTokens,
      ),
    );
    _throwIfCancelled(request);
    try {
      final json = extractJsonValue(repaired);
      validate(json);
      return json;
    } on FormatException catch (second) {
      throw UnreadableStructuredReply(second.message);
    }
  }
}

/// Cuánto de una respuesta rota se le devuelve al modelo para que la corrija.
const kMaxRepairReplyChars = 12000;

/// Lo fijo del pedido de corrección, con el [reason] de por qué no se pudo
/// leer: después va la respuesta rota.
String repairLead(String reason) =>
    'Tu respuesta anterior no se pudo leer como el JSON pedido ($reason). '
    'Devolvé SOLO el JSON corregido, completo y con la forma pedida, sin '
    'nada antes ni después. Esta fue tu respuesta:\n\n';

/// La instrucción de sistema de un pedido estructurado: la tarea, el idioma y
/// el esquema, y que la respuesta sea solo el JSON.
String structuredInstruction({
  required String task,
  required String schema,
  required String languageCode,
}) =>
    'Tu única tarea es $task, basándote ÚNICAMENTE en el material que se te '
    'da: nunca agregues datos, fechas, nombres ni afirmaciones que no estén '
    'ahí. Escribí todo el contenido en ${languageNameOf(languageCode)}. '
    'Respondé SOLO con un JSON válido, sin Markdown, sin bloques de código y '
    'sin texto antes ni después, con esta forma:\n$schema';

/// El nombre en español de un idioma para la instrucción: `es` → «español».
/// Uno que no está en la lista va con su código, que los modelos entienden.
String languageNameOf(String code) =>
    switch (code.split(RegExp('[-_]')).first) {
      'es' => 'español',
      'en' => 'inglés',
      'pt' => 'portugués',
      'fr' => 'francés',
      'it' => 'italiano',
      'de' => 'alemán',
      'ca' => 'catalán',
      'gl' => 'gallego',
      'eu' => 'euskera',
      'nl' => 'neerlandés',
      'la' => 'latín',
      'el' => 'griego',
      'he' => 'hebreo',
      'ru' => 'ruso',
      'zh' => 'chino',
      'ja' => 'japonés',
      'ko' => 'coreano',
      'ar' => 'árabe',
      _ => 'el idioma de código «$code»',
    };

String _withGuidance(String task, String? guidance) {
  final wish = guidance?.trim();
  if (wish == null || wish.isEmpty) return task;
  return '$task. Lo que pidió la persona: «$wish»';
}

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

void _throwIfCancelled(StructuredRequest<Object?> request) {
  if (request.cancellation?.isCancelled ?? false) {
    throw const CreationCancelledException();
  }
}
