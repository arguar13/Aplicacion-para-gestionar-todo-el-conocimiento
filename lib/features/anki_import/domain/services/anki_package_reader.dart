import 'dart:typed_data';

import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';

/// Lee un `.apkg` de Anki y lo convierte en tarjetas de Sinapsis (F31).
///
/// Solo lee: el paquete no se modifica y no se guarda nada. Lo que la
/// persona decida traer lo escribe quien llama.
///
/// Los dos métodos lanzan **solo** `AnkiImportException` (con un mensaje en
/// español listo para mostrar) ante un archivo vacío, que no es un `.apkg`,
/// dañado o de un formato que no se sabe leer; nunca una excepción cruda del
/// zip o de SQLite.
abstract interface class AnkiPackageReader {
  /// Lee el archivo en [path]. No lo carga entero en memoria: saca del zip
  /// solo la colección y la lista de medios.
  Future<AnkiImportedPackage> readFile(String path);

  /// Lo mismo, con el paquete ya en memoria (un archivo elegido en la web, o
  /// una prueba).
  Future<AnkiImportedPackage> readBytes(Uint8List bytes);
}
