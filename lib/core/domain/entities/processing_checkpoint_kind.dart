/// Qué trabajo largo guardó su avance (ver `ProcessingCheckpoints`).
enum ProcessingCheckpointKind {
  /// Una página escaneada de un documento, ya reconocida.
  ocrPage,

  /// Un tramo de audio de 29 s fijos, ya transcrito: como se partía el
  /// audio antes de F22. Ya no se escribe ni se lee —los tramos de ahora son
  /// otros, y mezclarlos daría texto repetido o con huecos—; un elemento que
  /// quedó a medias con estos se transcribe de nuevo, y sus filas se borran
  /// con el resto del avance cuando termina. Se conserva para poder leer
  /// esas filas.
  transcriptSegment,

  /// Un tramo de audio cortado en una pausa (F22, ver `planWindows`), ya
  /// transcrito.
  transcriptWindow,

  /// El usuario pidió volver a extraer el texto del elemento (F22): una sola
  /// fila, en la posición 0. Mientras exista, el procesamiento corre el
  /// transformador aunque el elemento ya tenga texto, y el texto nuevo toma
  /// el lugar del viejo. Se va con el resto del avance cuando termina bien;
  /// si falla, queda, y reintentar sigue siendo volver a extraer.
  reextract,
}
