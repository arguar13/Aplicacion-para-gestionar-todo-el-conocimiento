import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';

/// Un archivo que alguien trajo a la app.
///
/// Lleva los bytes en memoria y no una ruta. La razón es que el archivo puede
/// venir de cualquier lado —el selector del sistema, el botón de compartir de
/// otra app, un arrastre— y en varios de esos casos la ruta es temporal: el
/// sistema la borra en cuanto la app que la compartió termina. Leerlo ahí
/// mismo y quedarse con los bytes es lo que garantiza que lo que el usuario
/// eligió llegue entero al almacén.
///
/// Tiene un costo: un archivo de mil megas ocuparía mil megas de memoria. Por
/// eso la captura rechaza lo que pase de [maxBytes] con un mensaje claro, en
/// vez de que la app muera sin explicación. Una variante que copie por
/// partes sin pasar por memoria —para audio y video de horas de verdad, sin
/// ningún tope— sigue siendo trabajo pendiente: subir [maxBytes] ayuda hasta
/// donde ayuda cargar todo de una vez, no lo reemplaza.
class CapturedFile {
  const CapturedFile({required this.name, required this.bytes});

  /// El nombre que traía. Es entrada no confiable —lo puede haber puesto
  /// cualquier app— y se sanea antes de escribirlo en el disco (ver
  /// `sanitizeFileName`).
  final String name;

  final Uint8List bytes;

  /// Qué es esto en realidad, mirando los bytes y no el nombre.
  FileFormat get format => detectFileFormat(bytes, name: name);

  int get sizeInBytes => bytes.length;

  /// Lo más grande que se acepta: 500 MB.
  ///
  /// Cubre un documento escaneado de miles de páginas —mil páginas rondan
  /// los 100 MB— y varias horas de audio a un bitrate normal; un video
  /// largo de verdad, comprimido, puede seguir sin entrar. Subirlo más allá
  /// de esto empieza a arriesgar la memoria de un teléfono modesto, porque
  /// el archivo entero se carga de una sola vez —ver el comentario de la
  /// clase—, no en partes.
  static const maxBytes = 500 * 1024 * 1024;

  bool get isTooLarge => sizeInBytes > maxBytes;
}

/// El archivo que se está por traer pesa más que [CapturedFile.maxBytes],
/// según el tamaño que ya informa el origen —el selector del sistema, el
/// archivo soltado sobre la ventana, lo que llegó por el botón de
/// compartir— sin necesidad de abrirlo.
///
/// Se lanza **antes** de leer esos bytes del disco, no después:
/// [CapturedFile.isTooLarge] ya existe para el caso en que el archivo se
/// leyó igual, pero confiar solo
/// en ese chequeo significaría cargar en memoria un archivo de varios
/// cientos de megas solo para terminar descartándolo por pesado — el mismo
/// desperdicio que puede hacer que la app se quede sin memoria y se cierre
/// en un teléfono modesto, en vez de mostrar el aviso de siempre.
class FileTooLargeException implements Exception {
  const FileTooLargeException();

  @override
  String toString() => 'El archivo pesa más de ${CapturedFile.maxBytes} bytes';
}
