import 'dart:typed_data';

/// Escribe archivos en una carpeta elegida por el usuario, fuera del
/// almacenamiento propio de la app.
///
/// Aparte del almacén de archivos interno a propósito: aquel guarda en la
/// carpeta privada de la app, con nombres que ella misma controla y que
/// nunca chocan entre sí. Este escribe donde el usuario haya elegido, así
/// que puede fallar por motivos que el almacén interno no tiene que
/// considerar nunca —permisos de una carpeta ajena, un disco externo que
/// se desconectó a mitad de camino— y dos elementos sin relación pueden
/// pedir, sin saberlo, el mismo nombre de archivo.
// ignore: one_member_abstracts
abstract interface class DirectoryWriter {
  Future<void> writeFile({
    required String directoryPath,
    required String fileName,
    required Uint8List bytes,
  });
}
