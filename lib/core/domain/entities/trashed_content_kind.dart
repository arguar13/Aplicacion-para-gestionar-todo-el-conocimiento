/// Qué se soltó de un elemento y espera en la papelera del contenido (F30,
/// decisión 68): el archivo original o el texto que se le sacó.
enum TrashedContentKind {
  /// El archivo original —el libro, el audio—: se soltó y quedó el texto.
  file,

  /// El texto extraído: se soltó y quedó el archivo.
  text,
}
