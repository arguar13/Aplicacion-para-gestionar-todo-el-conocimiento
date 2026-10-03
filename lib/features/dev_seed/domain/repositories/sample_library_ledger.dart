/// Lo que ya se cargó de la biblioteca de ejemplo: lo que hace que tocar dos
/// veces «Cargar» no duplique nada.
///
/// Se recuerda por el identificador estable de cada recurso
/// (`SampleResource.id`), no buscando en la biblioteca por dirección o por
/// título: un archivo bajado no guarda de dónde vino, y el título de una
/// página cambia al procesarse. Y se recuerda uno por uno, apenas queda
/// guardado: si la app se cierra a mitad de la carga, la próxima pasada
/// sigue desde donde quedó.
abstract interface class SampleLibraryLedger {
  /// Los identificadores de lo que ya se cargó.
  Set<String> loadedIds();

  /// Anota que [id] ya se cargó.
  Future<void> markLoaded(String id);
}
