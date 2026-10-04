import 'package:flutter_gemma/core/extensions.dart' show ModelThinkingFilter;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

/// La respuesta de [chat] al pedido que ya tiene cargado, a medida que el
/// modelo la escribe: cada pedazo de texto nuevo (F30). Al terminar, deja en
/// [meter] cuánto tardó.
///
/// Sobre `generateChatResponseAsync` y no sobre `generateChatResponse`, que
/// espera la respuesta entera sin mostrar nada: además de poder mostrarla
/// mientras se escribe, es lo único que mide la espera hasta la primera
/// palabra y la que lleva la cuenta de lo que ocupa la sesión.
///
/// Quien la consume la tiene que leer HASTA EL FINAL: si deja de escucharla
/// a mitad, `flutter_gemma` no anota la respuesta en su historial y la sesión
/// queda desfasada. Para cortarla se usa `InferenceChat.stopGeneration`, que
/// la termina limpia con lo escrito hasta ahí.
Stream<String> measuredReply(
  InferenceChat chat, {
  required LanguageModelMeter meter,
  required LanguageModelReplyKind kind,
}) async* {
  final watch = Stopwatch()..start();
  final tokensBefore = chat.currentTokens;
  Duration? firstToken;
  final text = StringBuffer();

  await for (final response in chat.generateChatResponseAsync()) {
    // Sin herramientas ni modo de pensamiento configurados, solo llega texto.
    if (response is! TextResponse || response.token.isEmpty) continue;
    firstToken ??= watch.elapsed;
    text.write(response.token);
    yield response.token;
  }

  watch.stop();
  // `flutter_gemma` suma a su cuenta lo que ocupa la respuesta al terminar
  // —con el tokenizador del modelo—: la diferencia son los tokens generados.
  final tokens = chat.currentTokens - tokensBefore;
  meter.recordReply(
    LanguageModelReply(
      kind: kind,
      firstToken: firstToken,
      total: watch.elapsed,
      tokens: tokens > 0 ? tokens : null,
      words: countWords(text.toString()),
    ),
  );
}

/// El texto final de una respuesta de [chat]: sin lo que el modelo haya
/// «pensado» en voz alta y sin espacios en las puntas. Es lo mismo que hacía
/// `generateChatResponse` con la respuesta entera, y que el camino de a
/// pedazos no hace solo.
String cleanReply(InferenceChat chat, String text) =>
    ModelThinkingFilter.cleanResponse(
      text,
      isThinking: false,
      modelType: chat.modelType,
      fileType: chat.fileType,
    );

/// [measuredReply] entera y limpia ([cleanReply]), para quien solo usa el
/// texto completo: las tareas que después lo leen línea por línea.
Future<String> collectReply(
  InferenceChat chat, {
  required LanguageModelMeter meter,
  LanguageModelReplyKind kind = LanguageModelReplyKind.task,
}) async {
  final text = StringBuffer();
  await for (final piece in measuredReply(chat, meter: meter, kind: kind)) {
    text.write(piece);
  }
  return cleanReply(chat, text.toString());
}
