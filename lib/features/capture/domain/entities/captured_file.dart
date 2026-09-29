import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_format.dart';

/// Un archivo que alguien trajo a la app.
///
/// Puede vivir **en memoria** —lo que ya llega como bytes: una foto recién
/// sacada, lo que entrega el navegador— o **en disco** —lo que el selector
/// del sistema, el botón de compartir de otra app o un arrastre entregan
/// como ruta—. En disco no se lee entero nunca: se sabe su tamaño, se leen
/// sus primeros [headBytes] para reconocer qué es, y se copia al almacén
/// por partes ([openRead]). Es lo que permite guardar un video de varios GB
/// grabado con el teléfono sin que la app se quede sin memoria (F21); antes
/// cada archivo se cargaba entero y se rechazaba lo que pasara de 500 MB.
///
/// La ruta del origen puede ser temporal —el sistema la borra en cuanto la
/// app que la compartió termina—: por eso se copia al almacén en el momento
/// de guardar, no se guarda la ruta.
class CapturedFile {
  /// Un archivo que ya está en memoria.
  CapturedFile({required this.name, required Uint8List bytes})
    : sizeInBytes = bytes.length,
      head = bytes.length <= headBytes
          ? bytes
          : Uint8List.sublistView(bytes, 0, headBytes),
      _bytes = bytes,
      _open = null;

  /// Un archivo en disco, de [sizeInBytes], cuyos primeros bytes son [head]
  /// y que se lee por partes con [openRead].
  CapturedFile.onDisk({
    required this.name,
    required this.sizeInBytes,
    required this.head,
    required Stream<List<int>> Function() openRead,
  }) : _bytes = null,
       _open = openRead;

  /// Cuántos bytes del comienzo alcanzan para reconocer el formato sin leer
  /// el archivo entero: las firmas están en los primeros bytes, y en un
  /// DOCX o un EPUB las entradas que los delatan están entre las primeras
  /// del ZIP.
  static const headBytes = 64 * 1024;

  /// El nombre que traía. Es entrada no confiable —lo puede haber puesto
  /// cualquier app— y se sanea antes de escribirlo en el disco (ver
  /// `sanitizeFileName`).
  final String name;

  final int sizeInBytes;

  /// Los primeros bytes, como mucho [headBytes].
  final Uint8List head;

  final Uint8List? _bytes;
  final Stream<List<int>> Function()? _open;

  /// Qué es esto en realidad, mirando los bytes y no el nombre.
  FileFormat get format => detectFileFormat(head, name: name);

  /// El contenido, por partes. Lo que usa quien lo copia al almacén.
  Stream<List<int>> openRead() {
    final bytes = _bytes;
    if (bytes != null) return Stream<List<int>>.value(bytes);
    return _open!();
  }

  /// El contenido entero, en memoria. Solo para quien de verdad lo necesita
  /// entero —un adjunto del chat, una bibliografía—, y después de comprobar
  /// [isTooLarge]: para guardar, [openRead].
  Future<Uint8List> readAll() async {
    final bytes = _bytes;
    if (bytes != null) return bytes;
    final builder = BytesBuilder(copy: false);
    await _open!().forEach(builder.add);
    return builder.takeBytes();
  }

  /// Lo más grande que se carga **entero en memoria**: 500 MB.
  ///
  /// No es un tope para guardar —eso se copia por partes, y el límite es el
  /// espacio libre del dispositivo—, sino para lo que de verdad necesita el
  /// archivo entero: un adjunto del chat, una bibliografía.
  static const maxBytes = 500 * 1024 * 1024;

  bool get isTooLarge => sizeInBytes > maxBytes;
}
