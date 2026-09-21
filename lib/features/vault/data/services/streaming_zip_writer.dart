import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Arma un `.zip` escribiendo cada entrada por tandas: nunca hay un archivo
/// entero en memoria, ni sin comprimir ni comprimido.
///
/// Existe porque `ZipFileEncoder.addFile` de `archive` no lo hace: lee el
/// archivo por tandas, pero junta TODO lo comprimido en memoria antes de
/// escribirlo. Con la base de una bóveda de cientos de MB, eso es cientos de MB
/// de memoria —en un teléfono, el sistema mata la app—. Acá cada entrada se
/// comprime con zlib nativo a un archivo temporal, por tandas, y el codificador
/// de `archive` solo copia esos bytes ya comprimidos al `.zip`.
///
/// Lo que sale es un `.zip` común: lo lee `ZipDecoder`, `unzip` y cualquier
/// otro.
class StreamingZipWriter {
  /// Empieza un `.zip` en [zip]. Los temporales de cada entrada comprimida van
  /// a [workDirectory], que ya tiene que existir.
  StreamingZipWriter(File zip, {required Directory workDirectory})
    : _encoder = ZipFileEncoder()..create(zip.path),
      _work = workDirectory;

  final ZipFileEncoder _encoder;
  final Directory _work;
  var _entries = 0;

  /// Las extensiones de lo que ya viene comprimido: intentar comprimirlo otra
  /// vez gasta tiempo y no achica nada.
  static const _alreadyCompressed = {
    '.zip', '.gz', '.7z', '.rar', //
    '.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.avif', //
    '.mp3', '.m4a', '.aac', '.ogg', '.opus', '.flac', //
    '.mp4', '.m4v', '.mov', '.mkv', '.webm', //
    '.pdf', '.docx', '.xlsx', '.pptx', '.epub',
  };

  /// Agrega [file] con el nombre [name] —con `/`, relativo a la raíz del
  /// `.zip`—. Lo ya comprimido se guarda tal cual; el resto, comprimido.
  Future<void> addFile(File file, String name) async {
    if (_alreadyCompressed.contains(p.extension(name).toLowerCase())) {
      _store(file, name);
    } else {
      await _deflate(file, name);
    }
  }

  /// Sin comprimir: el `.zip` copia el archivo por tandas de 1 MiB.
  void _store(File file, String name) {
    final entry = ArchiveFile.stream(name, InputFileStream(file.path))
      ..compression = CompressionType.none
      ..lastModTime = file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
    _encoder.addArchiveFile(entry);
  }

  /// Comprimido con zlib nativo a un temporal, por tandas.
  Future<void> _deflate(File file, String name) async {
    final temp = File(p.join(_work.path, 'entrada-${_entries++}.deflate'));
    var crc = 0;
    var size = 0;
    final sink = temp.openWrite();
    try {
      await sink.addStream(
        file
            .openRead()
            .map((chunk) {
              crc = getCrc32(chunk, crc);
              size += chunk.length;
              return chunk;
            })
            // `raw`: un `.zip` guarda el deflate sin la cabecera de zlib.
            .transform(ZLibCodec(raw: true).encoder),
      );
      await sink.close();
    } on Object {
      try {
        await sink.close();
      } on Object {
        // Ya se está fallando.
      }
      await _deleteQuietly(temp);
      rethrow;
    }

    final entry =
        ArchiveFile.file(name, size, _Precompressed(InputFileStream(temp.path)))
          ..crc32 = crc
          ..compression = CompressionType.deflate
          ..lastModTime =
              file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
    // Al agregarla, el codificador cierra el temporal: recién ahí se puede
    // borrar (en Windows, un archivo abierto no se borra).
    _encoder.addArchiveFile(entry);
    await _deleteQuietly(temp);
  }

  /// Termina el `.zip`: escribe el índice y cierra el archivo.
  Future<void> close() => _encoder.close();

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Un temporal que no se borra queda en la carpeta de trabajo, que se
      // borra entera al terminar.
    }
  }
}

/// El contenido de una entrada que YA está comprimida —con deflate crudo— en
/// un archivo: el codificador de `archive` lo copia al `.zip` tal cual, por
/// tandas, sin descomprimirlo ni comprimirlo de nuevo.
class _Precompressed extends FileContent {
  _Precompressed(this._compressed);

  final InputStream _compressed;

  @override
  int get length => _compressed.length;

  @override
  bool get isCompressed => true;

  @override
  InputStream getStream({bool decompress = true}) {
    if (decompress) {
      throw UnsupportedError(
        'Solo se lee comprimido: es para copiarlo al .zip.',
      );
    }
    return _compressed;
  }

  @override
  void write(OutputStream output) => output.writeStream(_compressed);

  @override
  Future<void> close() async => _compressed.close();

  @override
  void closeSync() => _compressed.closeSync();
}
