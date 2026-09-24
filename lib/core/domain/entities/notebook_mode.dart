/// Cómo un cuaderno decide qué elementos tiene (F16, D1).
enum NotebookMode {
  /// El usuario agrega y saca elementos uno por uno —`notebook_item`—.
  manual,

  /// El cuaderno guarda una `LibraryQuery` con nombre, resuelta en el
  /// momento: los mismos elementos que esa consulta traería en la
  /// Biblioteca, sin una lista fija que mantener al día.
  query,
}
