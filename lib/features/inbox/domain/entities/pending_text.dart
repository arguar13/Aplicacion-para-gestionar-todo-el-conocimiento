import 'package:sinapsis/core/domain/entities/processing_state.dart';

/// En qué está el texto de lo que espera en la Bandeja (F41).
///
/// Lo nuevo de la Biblioteca entra a la Bandeja apenas se guarda, tenga texto
/// o no. Casi todo lo que se hace con una fuente ahí —triarla, sacarle
/// una nota, vincularla a una nota viva, revisar lo que sugirió la IA—
/// necesita su texto; descartarla, no. Esto es lo que la tarjeta y la cola
/// dicen mientras tanto, y lo que apaga o prende cada acción, en vivo.
///
/// Sale de dos datos que ya existen, sin columnas nuevas: si el elemento tiene
/// algún texto (`hasTextSql`) y en qué está su procesamiento.
enum PendingText {
  /// Ya tiene texto: se puede hacer todo.
  ready,

  /// Todavía no: se está transcribiendo, leyendo o extrayendo, o espera su
  /// turno en la cola. Llega solo.
  arriving,

  /// Sacarle el texto falló. No llega solo: se puede reintentar.
  failed,

  /// Se terminó de procesar y no tenía texto: una foto sin letras, un audio
  /// en silencio, una página sin cuerpo, o un libro del que se dejó «solo el
  /// libro» (F30). Tampoco llega solo: se puede volver a extraer.
  missing;

  /// En qué está el texto de un elemento que [hasText] o no, con su
  /// procesamiento en [processing].
  ///
  /// Con texto, siempre [ready]: mientras se vuelve a extraer, el texto de
  /// antes sigue guardado hasta que el nuevo está listo, y si falla, queda.
  static PendingText of({
    required bool hasText,
    required ProcessingState processing,
  }) {
    if (hasText) return ready;
    return switch (processing) {
      ProcessingState.pending || ProcessingState.processing => arriving,
      ProcessingState.failed => failed,
      ProcessingState.ready => missing,
    };
  }

  bool get isReady => this == ready;
}
