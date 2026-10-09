/// Pide al sistema el `.apkg` de Anki que se quiere traer (F31).
///
/// Devuelve la **ruta** del archivo y no su contenido: un paquete con medios
/// puede pesar cientos de MB, y el lector (`AnkiPackageReader.readFile`) saca
/// del zip solo la colección sin cargarlo entero. Existe como contrato, igual
/// que `FileChooser`, porque abrir el selector del sistema es lo único de este
/// camino que no se puede probar sin una ventana.
abstract interface class ApkgFileChooser {
  /// Abre el selector y devuelve la ruta elegida, o `null` si se canceló
  /// (que no es un error).
  Future<String?> pick();

  /// Suelta lo que el selector dejó en el almacenamiento temporal del sistema
  /// (en Android, una copia del archivo elegido). Se llama al terminar con el
  /// paquete, haya salido bien o mal.
  Future<void> release();
}
