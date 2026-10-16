import 'dart:typed_data';

import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';

/// El motor que de verdad escribe (F32): Gemma en el teléfono o un modelo en
/// la nube (Gemini, OpenAI, Claude).
///
/// Lo que se le pide en cada tarea —la instrucción, el pedido, cómo se lee lo
/// que contesta— vive una sola vez arriba, en `LanguageModelTasks`: un motor
/// solo sabe abrir un intercambio, escribir la respuesta, cortarla y cerrarse.
/// Así las tarjetas, los resúmenes, los vínculos, el quiz, los cuadernos y la
/// IA de fondo hacen lo mismo con cualquier motor.
abstract interface class ModelBackend {
  /// Cuántos tokens lee de una vez —su ventana—: la instrucción, el pedido y
  /// la respuesta.
  int get contextTokens;

  /// El mismo motor para la IA de fondo (F32): con un modelo en la nube, lo que
  /// pide cuenta aparte —y tiene su tope por día— para que siempre quede cuota
  /// para la persona. Gemma no distingue: devuelve el mismo.
  ModelBackend get forBackground;

  /// Si ya está listo para escribir sin esperar: Gemma, con sus pesos ya en
  /// la memoria; un modelo en la nube, siempre.
  bool get isWarm;

  /// Lo deja listo (Gemma: carga los pesos). Corre dentro de un turno de la
  /// persona (`LanguageModelGate`): no lo pide.
  Future<void> warmUp();

  /// Abre un intercambio de una sola vuelta, con [instruction] y un tope de
  /// [maxOutputTokens] para la respuesta. Corre dentro del turno de quien lo
  /// pide (`LanguageModelGate`): no lo pide.
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  });

  /// Abre una charla que recuerda lo conversado entre mensajes. A diferencia
  /// de [openExchange], pide sus propios turnos: dura mientras dure la charla.
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  });
}

/// Un pedido de una sola vuelta, abierto con su instrucción.
abstract interface class ModelExchange {
  /// Cuántos tokens ocupa [text] en la ventana del motor.
  Future<int> countTokens(String text);

  /// Manda [text] y da la respuesta entera, ya limpia. Se puede cortar con
  /// [stop]: termina con lo escrito hasta ahí.
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  });

  /// Corta lo que se esté escribiendo.
  Future<void> stop();

  /// Libera el intercambio. Después de esto no se vuelve a usar.
  Future<void> close();
}

/// Una charla en curso que recuerda lo conversado.
abstract interface class ModelConversation {
  /// Manda [prompt] —lo que [said] la persona, con lo que lo acompañe, como el
  /// contexto de la bóveda— y da la respuesta mientras se escribe
  /// ([ChatReplyStream]). En lo conversado queda [said], no [prompt]: el
  /// contexto se vuelve a buscar en cada mensaje.
  ChatReplyStream send({
    required String prompt,
    required String said,
    List<Uint8List> images = const [],
  });

  /// Termina la charla y libera lo que tenga abierto.
  Future<void> close();
}
