/// Pide una carpeta al sistema, para guardar ahí un paquete de exportación.
///
/// Igual que el selector de archivos de la captura: existe como interfaz
/// porque abrir el selector del sistema es lo único de este camino que no
/// se puede probar sin una ventana de verdad.
// ignore: one_member_abstracts
abstract interface class DirectoryChooser {
  /// La carpeta elegida, o `null` si se canceló.
  ///
  /// Cancelar no es un error: es la respuesta más común de un selector de
  /// carpetas, porque abrirlo por accidente pasa todo el tiempo.
  Future<String?> pickDirectory();
}
