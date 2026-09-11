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
/// vez de que la app muera sin explicación. Cuando lleguen el audio y el
/// video largos —fase 7— van a necesitar una variante que copie por partes
/// sin pasar por memoria.
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

  /// Lo más grande que se acepta: 200 MB.
  ///
  /// Cubre de sobra cualquier documento —un PDF escaneado de mil páginas
  /// ronda los 100 MB— y deja afuera lo que no entra en la memoria de un
  /// teléfono modesto.
  static const maxBytes = 200 * 1024 * 1024;

  bool get isTooLarge => sizeInBytes > maxBytes;
}
