// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese. Es
// deliberado: el disco puede fallar de las dos formas.
// ignore_for_file: only_throw_errors

import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_store.dart';

/// Un almacén de archivos que vive en memoria.
///
/// Para las pruebas que necesitan un almacén pero no están probando el
/// almacén: escribir en el disco de verdad las haría más lentas y dejaría
/// basura si alguna se cae a la mitad. El almacén real tiene sus propias
/// pruebas, contra un directorio temporal de verdad.
class InMemoryFileStore implements FileStore {
  final _contents = <String, Uint8List>{};

  /// Las rutas que se borraron, en orden. Permite comprobar que algo limpió
  /// lo que tenía que limpiar.
  final deleted = <String>[];

  /// Si está, se lanza al borrar. Para probar qué pasa cuando el disco se
  /// resiste.
  Object? deleteError;

  /// Qué hay guardado ahora mismo.
  Iterable<String> get paths => _contents.keys;

  @override
  Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String id,
  }) async {
    final path = 'originales/$id/${sanitizeFileName(suggestedName)}';
    _contents[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List?> read(String relativePath) async => _contents[relativePath];

  @override
  Future<String> resolve(String relativePath) async => '/memoria/$relativePath';

  @override
  Future<void> delete(String relativePath) async {
    if (deleteError != null) throw deleteError!;

    deleted.add(relativePath);
    _contents.remove(relativePath);
  }
}
