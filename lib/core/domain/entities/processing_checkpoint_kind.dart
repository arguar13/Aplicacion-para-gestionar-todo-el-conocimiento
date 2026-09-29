/// Qué trabajo largo guardó su avance (ver `ProcessingCheckpoints`).
enum ProcessingCheckpointKind {
  /// Una página escaneada de un documento, ya reconocida.
  ocrPage,

  /// Un tramo de audio, ya transcrito.
  transcriptSegment,
}
