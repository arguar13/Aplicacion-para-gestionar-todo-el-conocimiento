import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Si el modelo que escribe puede «pensar más» antes de contestar (F42): el
/// interruptor «Pensar más» de la hoja «Agregar al chat».
///
/// Todos los modelos en la nube que razonan ya se piden pensando lo menos
/// posible, que es lo más rápido (F32): `thinkingLevel: low` en Gemini 3 y 4,
/// `thinkingBudget: 0` en Gemini 2.5 Flash, `reasoning_effort: low` en los de
/// OpenAI que razonan y `effort: low` en Claude 5. «Pensar más» es la misma
/// perilla en el otro extremo; cada formato la traduce en su `bodyOf`, y esto
/// es la única fuente de quién la tiene —la pantalla, para mostrar el
/// interruptor prendible o apagado con su motivo, y los formatos, para no
/// mandarle a un modelo un parámetro que rechaza con un 400—.
enum ThinkMoreSupport {
  /// El modelo tiene la perilla: «Pensar más» se puede prender.
  supported,

  /// Gemma en el teléfono: el motor no ofrece un modo para pensar más. El
  /// gancho queda en `ModelConversation.send(thinkMore:)`, que Gemma hoy
  /// ignora; si una versión de `flutter_gemma` lo trae, se prende acá.
  onDevice,

  /// Un modelo en la nube que no razona (GPT-4o, Gemini 2.0, Claude 4): no
  /// hay nada que subir.
  notThisModel,
}

/// Si [model] —el id del proveedor, como lo pide la app— de [provider] puede
/// pensar más. Ver [ThinkMoreSupport].
ThinkMoreSupport thinkMoreSupport(AiProvider provider, String model) {
  final id = model.trim();
  final supported = switch (provider) {
    AiProvider.gemma => null,
    AiProvider.gemini => geminiThinks(id),
    AiProvider.openAi => openAiReasons(id),
    AiProvider.anthropic => anthropicFifthGeneration(id),
  };
  return switch (supported) {
    null => ThinkMoreSupport.onDevice,
    true => ThinkMoreSupport.supported,
    false => ThinkMoreSupport.notThisModel,
  };
}

/// Si [model] es un Gemini que regula lo que piensa: del 2.5 en adelante
/// (`thinkingBudget` en el 2.5, `thinkingLevel` del 3 en adelante).
bool geminiThinks(String model) {
  final generation = geminiGeneration(model);
  if (generation == null) return false;
  final (major, minor) = generation;
  return major >= 3 || (major == 2 && minor >= 5);
}

/// La versión de un Gemini, (mayor, menor): `gemini-2.5-flash` es (2, 5) y
/// `gemini-3-pro`, (3, 0). `null` si [model] no es un Gemini.
(int, int)? geminiGeneration(String model) {
  final match = RegExp(r'^gemini-(\d+)(?:\.(\d+))?').firstMatch(model);
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.tryParse(match.group(2) ?? '') ?? 0);
}

/// Si [model] de OpenAI razona antes de escribir: la serie «o» y GPT-5 en
/// adelante, salvo los `-chat`, que contestan directo.
bool openAiReasons(String model) {
  if (RegExp(r'^o\d').hasMatch(model)) return true;
  final gpt = RegExp(r'^gpt-(\d+)').firstMatch(model);
  if (gpt == null) return false;
  return int.parse(gpt.group(1)!) >= 5 && !model.contains('-chat');
}

/// Si [model] de Claude es de la familia 5 (Opus, Sonnet, Haiku, Fable,
/// Mythos): siempre piensa, y lo que piensa se regula con `effort`.
bool anthropicFifthGeneration(String model) => RegExp(
  r'^claude-(opus|sonnet|haiku|fable|mythos)-5(?:$|-)',
).hasMatch(model);
