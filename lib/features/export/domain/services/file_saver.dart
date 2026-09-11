import 'dart:typed_data';

/// Deja elegir dónde guardar un archivo ya armado en memoria.
///
/// Igual que el resto de los selectores del sistema: existe como interfaz
/// porque abrir el diálogo de guardado no se puede probar sin una ventana
/// de verdad.
// ignore: one_member_abstracts
abstract interface class FileSaver {
  /// La ruta elegida, o `null`.
  ///
  /// `null` significa cosas distintas según la plataforma y ninguna es un
  /// error: en escritorio y en móvil es que se canceló el diálogo; en la
  /// web siempre es `null`, porque ahí no hay una ruta de la que hablar —el
  /// navegador se encarga solo de la descarga—. Por eso quien llama no
  /// debería leer nada en ese `null` más que "no hay una ruta que mostrar".
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  });
}
