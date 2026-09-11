/// En qué punto del procesamiento está un elemento.
///
/// Existe porque las conversiones caras —transcribir una hora de audio,
/// reconocer texto en cien páginas— no pueden bloquear el guardado. El
/// elemento se guarda enseguida con lo que haya (un enlace, un título) y la
/// transcripción aparece cuando termina.
///
/// [failed] no es un callejón sin salida: el elemento sigue existiendo con lo
/// que se pudo obtener, y la conversión se puede reintentar. Rechazar algo
/// porque una etapa opcional falló sería peor que aceptarlo incompleto.
enum ProcessingState {
  /// Guardado, esperando su turno en la cola.
  pending,

  /// Con una conversión en curso.
  processing,

  /// Listo: todo lo que se podía extraer, está.
  ready,

  /// Una conversión falló. El elemento conserva lo que sí se obtuvo.
  failed,
}
