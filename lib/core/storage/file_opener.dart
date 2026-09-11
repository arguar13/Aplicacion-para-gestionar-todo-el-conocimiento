import 'package:sinapsis/core/storage/file_store.dart';

/// Abre un archivo con la aplicación que el sistema operativo tenga asociada
/// a su tipo: el lector de PDF, el procesador de textos, el que sea.
///
/// Existe como interfaz y no se llama al complemento nativo directamente, por
/// la misma razón que [FileStore]: para poder probar la pantalla de detalle
/// sin depender de que la máquina que corre las pruebas tenga una aplicación
/// de verdad instalada para cada tipo de archivo.
// ignore: one_member_abstracts
abstract interface class FileOpener {
  Future<FileOpenResult> open(String absolutePath);
}

/// Qué pasó al intentar abrir un archivo.
enum FileOpenResult {
  /// Se abrió: el sistema operativo ya se está encargando.
  done,

  /// El archivo ya no está donde debería — alguien vació el almacenamiento
  /// de la app desde los ajustes del sistema, por ejemplo.
  fileNotFound,

  /// El sistema no tiene ninguna aplicación asociada a este tipo de archivo.
  noAppAvailable,

  /// Cualquier otro fallo: permisos denegados, una plataforma no soportada,
  /// etc. El motivo puntual no cambia lo que puede hacer la interfaz al
  /// respecto, así que no hace falta distinguirlo más.
  failed,
}
