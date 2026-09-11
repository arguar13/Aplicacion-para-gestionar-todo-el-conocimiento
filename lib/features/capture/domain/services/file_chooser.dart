import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

/// Pide un archivo al sistema.
///
/// Existe como contrato de dominio y no como una llamada directa al selector
/// porque abrir el selector del sistema es lo único de todo este camino que
/// no se puede probar: necesita un sistema operativo con una ventana. Detrás
/// de esta interfaz, la pantalla y el caso de uso se prueban enteros con un
/// doble que devuelve el archivo que el test quiera.
///
/// Es una interfaz de un solo método y podría ser una función suelta. Se deja
/// como interfaz porque va a crecer —elegir varios archivos a la vez, aceptar
/// los que se suelten sobre la ventana— y porque un tipo con nombre se lee
/// mejor en el constructor de quien lo recibe que una firma de función.
// ignore: one_member_abstracts
abstract interface class FileChooser {
  /// Abre el selector y devuelve lo elegido, o `null` si se canceló.
  ///
  /// Cancelar no es un error: es la respuesta más común de un selector de
  /// archivos, porque abrirlo por accidente pasa todo el tiempo.
  Future<CapturedFile?> pickOne();
}

/// El usuario no dio permiso para leer sus archivos.
///
/// Se distingue de cancelar porque pide una acción distinta: cancelar es
/// "ahora no", y esto es "hay que ir a los ajustes del sistema".
class FileAccessDeniedException implements Exception {
  const FileAccessDeniedException();

  @override
  String toString() => 'Sin permiso para leer los archivos del dispositivo';
}
