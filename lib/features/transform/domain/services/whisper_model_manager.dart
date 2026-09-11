/// Dónde quedaron, en el disco, los tres archivos que necesita el
/// reconocedor de Whisper.
class WhisperModelPaths {
  const WhisperModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String tokens;
}

/// Trae y guarda el modelo de transcripción, sin que nadie más sepa de dónde
/// sale ni dónde queda.
///
/// Separado del `Transformer` que transcribe a propósito: el modelo pesa
/// cientos de megas y no viene con la app —ver la decisión 8 en
/// docs/arquitectura.md—, así que hace falta bajarlo aparte, una sola vez,
/// con el permiso explícito de quien usa la app. El principio 1 de la
/// arquitectura es tajante con esto: las únicas conexiones salientes son las
/// que el usuario pide.
abstract interface class WhisperModelManager {
  /// Si el modelo ya está en el disco, listo para usarse.
  Future<bool> isReady();

  /// Las rutas de los archivos ya descargados.
  ///
  /// Solo tiene sentido llamarlo después de que [isReady] haya dicho que
  /// sí: no vuelve a comprobar nada por su cuenta.
  Future<WhisperModelPaths> paths();

  /// Cuánto pesa la descarga completa, en bytes, si se puede saber de
  /// antemano. `null` si no se pudo consultar —sin conexión, por ejemplo—,
  /// que es distinto de "no hace falta descargar nada".
  ///
  /// No es un número fijo en el código: el modelo puede cambiar de tamaño
  /// el día que se actualice, y mostrar un número viejo sería peor que no
  /// mostrar ninguno.
  Future<int?> downloadSizeInBytes();

  /// Descarga el modelo y lo deja listo para [isReady].
  ///
  /// El stream emite el progreso de 0.0 a 1.0 a medida que avanza, y se
  /// cierra solo al terminar. Un error en el medio —sin conexión, el
  /// archivo ya no está donde se lo buscaba— llega como un error del
  /// stream, sin dejar archivos a medio bajar que hagan creer que el
  /// modelo está listo cuando no lo está.
  Stream<double> download();
}

/// Se pidió transcribir sin haber descargado el modelo todavía.
///
/// El elemento queda como cualquier otro fallo de transformación —conserva
/// lo que tenía, se puede reintentar— pero el motivo puntual conviene que
/// quede claro en los registros: no es un audio corrupto ni un problema de
/// red, es que falta un paso previo, de una sola vez, en la pantalla de
/// transcripción.
class WhisperModelNotReadyException implements Exception {
  const WhisperModelNotReadyException();

  @override
  String toString() => 'El modelo de transcripción todavía no está descargado.';
}
