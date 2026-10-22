/// Qué marca una marca de estudio (F36): una oración del resumen, una de la
/// síntesis o una palabra clave.
///
/// Una oración que está en el resumen y en la síntesis tiene dos marcas, una
/// de cada una: se ve una u otra según lo que esté prendido, nunca las dos
/// encima.
enum StudyMarkKind {
  /// Una oración con una idea principal.
  summary,

  /// Una oración de lo esencial, el hilo del documento.
  synthesis,

  /// Una palabra que sostiene su oración: hasta cuatro por oración.
  keyword,
}
