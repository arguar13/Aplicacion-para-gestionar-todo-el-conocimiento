import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:web/web.dart' as web;

/// `FileStore` sobre el Origin Private File System (OPFS) del navegador.
///
/// Ver la decisión 9 en docs/arquitectura.md: en vez de sumar un paquete de
/// por medio, se habla directo con `package:web` y `dart:js_interop` —el
/// mismo estilo de interop que ya usan `audio_decoder` y `sherpa_onnx` en
/// sus versiones web—, porque la API que hace falta es chica: conseguir un
/// directorio, un archivo adentro de otro, y un stream para escribirlo.
///
/// Misma organización de carpetas que `LocalFileStore` —`originales/`, una
/// subcarpeta por identificador, el nombre adentro— para que una ruta
/// relativa guardada en la base signifique lo mismo en cualquier
/// plataforma.
///
/// Sin pruebas propias: OPFS no existe fuera de un navegador de verdad, así
/// que no hay con qué correrlo bajo `flutter test`. Verificado a mano en un
/// Chromium real (ver la fase 8 en docs/arquitectura.md).
class OpfsFileStore implements FileStore {
  const OpfsFileStore();

  static const _folder = 'originales';

  Future<web.FileSystemDirectoryHandle> _root() =>
      web.window.navigator.storage.getDirectory().toDart;

  /// Recorre los directorios de [segments] uno por uno, sin crear ninguno
  /// en el camino. `null` si algún tramo no existe.
  Future<web.FileSystemDirectoryHandle?> _findDirectory(
    List<String> segments,
  ) async {
    var current = await _root();
    for (final segment in segments) {
      try {
        current = await current.getDirectoryHandle(segment).toDart;
        // Cualquier falla acá significa que ese tramo no existe: OPFS no
        // ofrece una forma de comprobarlo sin intentar abrirlo primero.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        return null;
      }
    }
    return current;
  }

  @override
  Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String id,
  }) async {
    final name = sanitizeFileName(suggestedName);

    final root = await _root();
    final originales = await root
        .getDirectoryHandle(
          _folder,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    final idDirectory = await originales
        .getDirectoryHandle(id, web.FileSystemGetDirectoryOptions(create: true))
        .toDart;
    final fileHandle = await idDirectory
        .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
        .toDart;

    final writable = await fileHandle.createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;

    return '$_folder/$id/$name';
  }

  @override
  Future<String> saveStream({
    required Stream<List<int>> bytes,
    required String suggestedName,
    required String id,
  }) async {
    final name = sanitizeFileName(suggestedName);

    final root = await _root();
    final originales = await root
        .getDirectoryHandle(
          _folder,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
    final idDirectory = await originales
        .getDirectoryHandle(id, web.FileSystemGetDirectoryOptions(create: true))
        .toDart;
    final fileHandle = await idDirectory
        .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
        .toDart;

    // Parte por parte, igual que en disco: ver `FileStore.saveStream`.
    final writable = await fileHandle.createWritable().toDart;
    try {
      await for (final chunk in bytes) {
        final part = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await writable.write(part.toJS).toDart;
      }
      await writable.close().toDart;
      // Un origen que se corta a mitad de camino no deja un archivo a medias.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await writable.abort().toDart;
      try {
        await idDirectory.removeEntry(name).toDart;
        // Si ni siquiera se puede borrar lo escrito, el error que importa es
        // el original, que se relanza igual.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
      rethrow;
    }

    return '$_folder/$id/$name';
  }

  @override
  Future<Uint8List?> read(String relativePath) async {
    final segments = relativePath.split('/');
    final fileName = segments.removeLast();

    final directory = await _findDirectory(segments);
    if (directory == null) return null;

    try {
      final fileHandle = await directory.getFileHandle(fileName).toDart;
      final file = await fileHandle.getFile().toDart;
      final buffer = await file.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
      // El archivo no existe, o dejó de existir entre que se resolvió el
      // directorio y se pidió abrirlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> readHead(String relativePath, {int maxBytes = 4096}) =>
      readRange(relativePath, start: 0, length: maxBytes);

  @override
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int length,
  }) async {
    final file = await _file(relativePath);
    if (file == null) return null;

    // `Blob.slice` recorta antes de leer: no hace falta traer el archivo
    // entero a memoria de JavaScript solo para mirarle una parte.
    final buffer = await file.slice(start, start + length).arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<int?> sizeOf(String relativePath) async =>
      (await _file(relativePath))?.size;

  /// En OPFS no hay ruta que otra librería pueda abrir: ver [resolve].
  @override
  Future<String?> localPathOf(String relativePath) async => null;

  /// El archivo de [relativePath], o `null` si no existe o dejó de existir
  /// entre que se resolvió el directorio y se pidió abrirlo.
  Future<web.File?> _file(String relativePath) async {
    final segments = relativePath.split('/');
    final fileName = segments.removeLast();

    final directory = await _findDirectory(segments);
    if (directory == null) return null;

    try {
      final fileHandle = await directory.getFileHandle(fileName).toDart;
      return await fileHandle.getFile().toDart;
      // OPFS no distingue sus fallos con tipos propios: la única forma de
      // saber que el archivo no está es intentar abrirlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(String relativePath) async {
    final segments = relativePath.split('/');
    final fileName = segments.removeLast();

    final directory = await _findDirectory(segments);
    if (directory == null) return false;

    try {
      await directory.getFileHandle(fileName).toDart;
      return true;
      // El archivo no existe: la única forma que da OPFS de saberlo es
      // intentar abrirlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> resolve(String relativePath) {
    // OPFS no tiene una ruta de sistema de archivos real —ni un archivo
    // temporal ni un identificador que otra API pueda abrir por su
    // cuenta—. Quien necesite el contenido tiene que pedirlo con `read()`;
    // ver la decisión 9 en docs/arquitectura.md.
    throw UnsupportedError(
      'OpfsFileStore no tiene una ruta absoluta: usar read() para conseguir '
      'los bytes en su lugar.',
    );
  }

  @override
  Future<void> delete(String relativePath) async {
    final segments = relativePath.split('/');
    final fileName = segments.removeLast();

    final directory = await _findDirectory(segments);
    if (directory == null) return;

    try {
      await directory.removeEntry(fileName).toDart;
      // No falla si no estaba: mismo contrato que `LocalFileStore.delete`.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Ya no estaba.
    }
  }
}
