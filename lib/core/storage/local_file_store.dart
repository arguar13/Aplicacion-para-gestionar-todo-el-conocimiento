import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_store.dart';

/// El almacén de archivos sobre el disco del dispositivo.
class LocalFileStore implements FileStore {
  /// [rootDirectory] se resuelve cada vez, no una sola vez al construir.
  ///
  /// Parece un detalle y no lo es: en iOS la carpeta de la app **cambia de
  /// ruta** entre ejecuciones y en cada actualización. Una ruta absoluta
  /// guardada hoy apunta mañana a un directorio que ya no existe, y los
  /// archivos "desaparecen" sin que nada se haya borrado. Es un error clásico
  /// y silencioso: no falla en desarrollo, falla en el teléfono del usuario
  /// después de actualizar.
  ///
  /// Por eso en la base se guarda una ruta **relativa** y la absoluta se
  /// arma en el momento de usarla.
  const LocalFileStore({required Future<Directory> Function() rootDirectory})
    : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  /// Subcarpeta del almacén.
  ///
  /// Tenerlos juntos y aparte del resto permite dos cosas: borrar todos los
  /// originales sin tocar nada más, y que alguien que abra la carpeta de la
  /// app entienda qué está viendo.
  static const _folder = 'originales';

  @override
  Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String id,
  }) async {
    // Cada archivo en su propia carpeta, nombrada por el identificador de la
    // fuente. Es lo que evita que dos "documento.pdf" de dos sitios distintos
    // se pisen, **sin** tener que pegar el identificador delante del nombre:
    // así el nombre guardado sigue siendo exactamente el que el usuario
    // reconoce, y para recuperarlo no hay que adivinar dónde terminaba el
    // identificador — que además lleva guiones, igual que muchos nombres de
    // archivo.
    final relativePath = p.join(_folder, id, sanitizeFileName(suggestedName));
    final file = File(await resolve(relativePath));

    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    // Se devuelve siempre con barras hacia adelante: la ruta se guarda en la
    // base y la base puede viajar entre plataformas en una copia de
    // seguridad. Windows entiende las barras hacia adelante; al revés no.
    return p.posix.joinAll(p.split(relativePath));
  }

  @override
  Future<String> saveStream({
    required Stream<List<int>> bytes,
    required String suggestedName,
    required String id,
  }) async {
    // La misma carpeta por fuente que `save`: ver ahí el porqué.
    final relativePath = p.join(_folder, id, sanitizeFileName(suggestedName));
    final file = File(await resolve(relativePath));
    await file.parent.create(recursive: true);

    final sink = file.openWrite();
    try {
      // `addStream` y no juntar en memoria: cada parte se escribe apenas
      // llega, y lo que ocupa en memoria es una parte, no el archivo.
      await sink.addStream(bytes);
      await sink.flush();
      await sink.close();
      // Cualquier fallo —el origen que se corta, el disco lleno— deja un
      // archivo a medias que nadie va a poder abrir: se borra y se avisa.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await sink.close().catchError((_) {});
      if (file.existsSync()) await file.delete();
      rethrow;
    }

    return p.posix.joinAll(p.split(relativePath));
  }

  @override
  Future<Uint8List?> read(String relativePath) async {
    final file = File(await resolve(relativePath));
    if (!file.existsSync()) return null;

    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> readHead(
    String relativePath, {
    int maxBytes = 4096,
  }) async {
    final file = File(await resolve(relativePath));
    if (!file.existsSync()) return null;

    // `RandomAccessFile.read()` y no `File.openRead()`: el stream con rango
    // de bytes deja el handle abierto hasta que algo lo cierre
    // explícitamente —acá no hay un `Stream.listen` que lo haga por su
    // cuenta—, y en algunas combinaciones de sistema de archivos eso
    // alcanza para que la lectura nunca se dé por terminada.
    final handle = await file.open();
    try {
      return await handle.read(maxBytes);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<Uint8List?> readRange(
    String relativePath, {
    required int start,
    required int length,
  }) async {
    final file = File(await resolve(relativePath));
    if (!file.existsSync()) return null;

    // Con `RandomAccessFile`, por lo mismo que en `readHead`.
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<int?> sizeOf(String relativePath) async {
    final file = File(await resolve(relativePath));
    return file.existsSync() ? file.length() : null;
  }

  @override
  Future<String?> localPathOf(String relativePath) async {
    final path = await resolve(relativePath);
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<bool> exists(String relativePath) async {
    return File(await resolve(relativePath)).existsSync();
  }

  @override
  Future<String> resolve(String relativePath) async {
    final root = await _rootDirectory();
    return p.join(root.path, p.joinAll(p.posix.split(relativePath)));
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(await resolve(relativePath));
    if (file.existsSync()) await file.delete();
  }
}
