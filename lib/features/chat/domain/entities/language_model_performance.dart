/// En qué parte del teléfono corre el modelo de lenguaje (F30).
///
/// La GPU suele ser varias veces más rápida que la CPU para Gemma; la NPU no
/// se pide nunca —sus paquetes son de un fabricante y de un largo de contexto
/// fijos—, pero `flutter_gemma` la nombra y se muestra si alguna vez aparece.
enum LanguageModelBackend { gpu, cpu, npu }

/// Cómo se cargó el modelo la última vez (F30): cuánto tardó, en qué parte del
/// teléfono quedó corriendo y si quedó listo para mirar fotos.
class LanguageModelLoad {
  const LanguageModelLoad({
    required this.duration,
    required this.backend,
    required this.requestedBackend,
    required this.vision,
  });

  final Duration duration;

  /// Dónde quedó corriendo; `null` si `flutter_gemma` no lo dijo.
  final LanguageModelBackend? backend;

  /// Dónde se pidió que corriera; `null` es «lo que elija `flutter_gemma`»,
  /// que prueba la GPU y, si falla, cae a la CPU sin avisar.
  final LanguageModelBackend? requestedBackend;

  /// Si se cargó con la parte del modelo que mira imágenes.
  final bool vision;

  /// Se pidió la GPU —o nada, que es pedirla— y quedó en la CPU: la GPU no
  /// arrancó en este teléfono.
  bool get fellBackToCpu =>
      backend == LanguageModelBackend.cpu &&
      requestedBackend != LanguageModelBackend.cpu;
}

/// Para qué fue una respuesta del modelo: la charla de la persona o una tarea
/// —resumir, tarjetas, la IA que organiza sola—.
enum LanguageModelReplyKind { chat, task }

/// Cuánto tardó una respuesta del modelo (F30).
///
/// Lo que la persona siente es [firstToken] —cuánto espera hasta ver la
/// primera palabra: lee el pedido entero, el «prefill»— y la velocidad con la
/// que después se escribe el resto ([tokensPerSecond], [wordsPerSecond]).
class LanguageModelReply {
  const LanguageModelReply({
    required this.kind,
    required this.total,
    required this.words,
    this.firstToken,
    this.tokens,
  });

  final LanguageModelReplyKind kind;

  /// Desde que se pidió la respuesta hasta la primera palabra. `null` si no
  /// escribió nada.
  final Duration? firstToken;

  /// Desde que se pidió hasta la última palabra.
  final Duration total;

  /// Cuántos tokens generó, según el propio tokenizador del modelo. `null` si
  /// no se pudo contar.
  final int? tokens;

  /// Cuántas palabras escribió.
  final int words;

  /// Lo que tardó en escribir, sin la espera hasta la primera palabra.
  Duration? get _writing {
    final first = firstToken;
    if (first == null) return null;
    final writing = total - first;
    return writing > Duration.zero ? writing : null;
  }

  /// Tokens por segundo mientras escribe: sin contar el primero, que sale al
  /// terminar de leer el pedido.
  double? get tokensPerSecond {
    final writing = _writing;
    final count = tokens;
    if (writing == null || count == null || count < 2) return null;
    return (count - 1) *
        Duration.microsecondsPerSecond /
        writing.inMicroseconds;
  }

  /// Palabras por segundo mientras escribe.
  double? get wordsPerSecond {
    final writing = _writing;
    if (writing == null || words == 0) return null;
    return words * Duration.microsecondsPerSecond / writing.inMicroseconds;
  }
}

/// Lo medido del modelo de lenguaje en esta sesión de la app (F30): para ver
/// en el teléfono de verdad si corre en la GPU o en la CPU, y qué tan rápido.
class LanguageModelPerformance {
  const LanguageModelPerformance({this.load, this.chatReply, this.taskReply});

  /// La última carga; `null` si no se cargó en esta sesión.
  final LanguageModelLoad? load;

  /// La última respuesta del chat.
  final LanguageModelReply? chatReply;

  /// La última respuesta de una tarea.
  final LanguageModelReply? taskReply;

  LanguageModelPerformance withLoad(LanguageModelLoad load) =>
      LanguageModelPerformance(
        load: load,
        chatReply: chatReply,
        taskReply: taskReply,
      );

  LanguageModelPerformance withReply(LanguageModelReply reply) =>
      switch (reply.kind) {
        LanguageModelReplyKind.chat => LanguageModelPerformance(
          load: load,
          chatReply: reply,
          taskReply: taskReply,
        ),
        LanguageModelReplyKind.task => LanguageModelPerformance(
          load: load,
          chatReply: chatReply,
          taskReply: reply,
        ),
      };
}
