/// En qué punto del pipeline técnico está una fuente: si ya se extrajo su
/// texto íntegro.
///
/// No es [ItemState]: acá el eje es si el trabajo automático terminó, sin
/// ninguna decisión humana de por medio.
enum SourceProcessingStatus {
  /// Guardada, esperando su turno.
  pending,

  /// Con una extracción en curso.
  running,

  /// El texto íntegro ya está.
  done,

  /// La extracción falló. La fuente conserva lo que sí se pudo obtener.
  failed,
}
