/// Qué tan trabajada está una nota, para saber de un vistazo qué falta
/// sin tener que abrirla.
enum NoteMaturity {
  /// Recién creada. Puede ser solo el fragmento que le dio origen.
  seed,

  /// Ya tiene estructura propia, más allá de lo que la originó.
  developing,

  /// Trabajada a fondo: conecta con lo que tiene que conectar y dice lo
  /// que tiene que decir.
  mature,
}
