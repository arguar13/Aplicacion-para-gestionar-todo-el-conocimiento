import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';

/// [ArchiveExpander] para `.zip`, por streaming y desconfiado (F30).
///
/// Un `.zip` lo armó cualquiera, y su índice dice lo que quiso quien lo
/// armó. Por eso:
///
/// - **Rutas hostiles.** Una entrada con `..`, una ruta absoluta, `\`, `:`
///   o un byte nulo no se saca. Las demás tampoco se escriben con su ruta:
///   cada archivo va a la carpeta del «Contenido» con su nombre saneado, y
///   la ruta que traía adentro queda solo como título. No hay forma de que
///   una entrada escriba fuera de esa carpeta.
/// - **Enlaces simbólicos, carpetas y entradas cifradas**: no se sacan. Lo
///   cifrado es justamente lo que no es público.
/// - **Bombas.** Se cuentan las entradas ([maxEntries]), la profundidad de
///   carpetas ([maxDepth]), lo descomprimido en total —contra el tope del
///   elemento y [maxTotalBytes]— y la proporción entre lo descomprimido y lo
///   comprimido ([maxRatio], pasado [ratioFloorBytes]). Lo descomprimido se
///   cuenta **mientras sale**, no por lo que dice el índice: una entrada que
///   miente sobre su tamaño se corta en el byte en que se pasa.
/// - **Un `.zip` adentro de otro** se guarda como archivo, sin abrirlo: un
///   solo nivel.
/// - **Integridad**: el CRC-32 de cada entrada se comprueba al terminarla.
///
/// Si algo de eso salta, se borra lo que ya se había sacado y se lanza
/// [UnsafeArchiveException]: el `.zip` queda guardado tal cual, sin abrir.
///
/// Nunca tiene una entrada entera en memoria: la descompresión es la de zlib
/// nativo, por tandas, como en la bóveda (`IncomingVault`), porque `archive`
/// 4.0.9 junta en memoria todo lo descomprimido de una entrada.
class ZipArchiveExpander implements ArchiveExpander {
  const ZipArchiveExpander({
    required FileStore files,
    this.maxEntries = 2000,
    this.maxDepth = 16,
    this.maxTotalBytes = 4 * 1024 * 1024 * 1024,
    this.maxRatio = 200,
    this.ratioFloorBytes = 16 * 1024 * 1024,
  }) : _files = files;

  final FileStore _files;

  /// Cuántas entradas como mucho.
  final int maxEntries;

  /// Cuántas carpetas, una adentro de otra, como mucho.
  final int maxDepth;

  /// Lo más que se descomprime, aunque el tope del elemento dé para más.
  final int maxTotalBytes;

  /// Cuántas veces más grande que lo comprimido puede ser lo descomprimido.
  final int maxRatio;

  /// Por debajo de esto no se mira la proporción: un texto repetitivo de
  /// pocos megas se comprime mucho y no es ninguna bomba.
  final int ratioFloorBytes;

  @override
  Future<List<ExpandedFile>> expand(
    String zipPath, {
    required String storeId,
    required String folder,
    required int maxBytes,
  }) async {
    final local = await _files.localPathOf(zipPath);
    if (local == null) throw const UnsafeArchiveException('no está en disco');
    final compressedSize = File(local).lengthSync();
    final limit = maxBytes < maxTotalBytes ? maxBytes : maxTotalBytes;

    final source = InputFileStream(local);
    final written = <ExpandedFile>[];
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(source);
        // `archive` lanza cualquier cosa con un archivo que no es un zip.
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        throw UnsafeArchiveException('no es un .zip válido ($e)');
      }
      if (archive.files.length > maxEntries) {
        throw UnsafeArchiveException(
          'tiene ${archive.files.length} entradas (máximo $maxEntries)',
        );
      }

      var total = 0;
      for (final entry in archive.files) {
        if (!_extractable(entry)) continue;
        final name = entry.name;
        final segments = name.split('/');
        if (segments.length > maxDepth + 1) {
          throw UnsafeArchiveException('demasiadas carpetas en "$name"');
        }

        var entryBytes = 0;
        final counted = _decompressed(entry).map((chunk) {
          entryBytes += chunk.length;
          total += chunk.length;
          if (total > limit) {
            throw UnsafeArchiveException('descomprimido pasa de $limit bytes');
          }
          if (total > ratioFloorBytes && total > compressedSize * maxRatio) {
            throw UnsafeArchiveException(
              'se infla más de $maxRatio veces su tamaño',
            );
          }
          return chunk;
        });
        final path = await _files.saveStream(
          bytes: counted,
          suggestedName: segments.last,
          id: storeId,
          folder: folder,
          unique: true,
        );
        written.add(
          ExpandedFile(relativePath: path, entryName: name, bytes: entryBytes),
        );
      }
      // Sin nada que se pueda sacar —o no era un zip, y `archive` lo leyó
      // vacío— el `.zip` se queda como está: borrarlo sería perderlo.
      if (written.isEmpty) {
        throw const UnsafeArchiveException('no tiene nada que se pueda sacar');
      }
      return written;
    } on Object {
      for (final file in written) {
        await _files.delete(file.relativePath);
      }
      rethrow;
    } finally {
      await source.close();
    }
  }

  /// Si [entry] es un archivo que se puede sacar: ni carpeta, ni enlace, ni
  /// cifrado, ni con una ruta hostil, ni basura de otros sistemas.
  static bool _extractable(ArchiveFile entry) {
    if (!entry.isFile || entry.isSymbolicLink) return false;
    final content = entry.rawContent;
    if (content is ZipFile && (content.flags & 0x1) != 0) return false;
    final name = entry.name;
    if (!isSafeEntryName(name)) return false;
    final last = name.split('/').last;
    if (name.startsWith('__MACOSX/') || last == '.DS_Store') return false;
    if (last == 'Thumbs.db' || last == 'desktop.ini') return false;
    return true;
  }

  /// Lo que trae [entry], descomprimido, por tandas, con su CRC-32
  /// comprobado al final (ver `IncomingVault._decompressed`).
  static Stream<List<int>> _decompressed(ArchiveFile entry) async* {
    final content = entry.rawContent;
    if (content == null) return;
    final method = content is ZipFile
        ? content.compressionMethod
        : CompressionType.none;
    final compressed = content.getStream(decompress: false);
    final chunks = _chunksOf(compressed);
    final plain = switch (method) {
      CompressionType.deflate => chunks.transform(ZLibCodec(raw: true).decoder),
      CompressionType.none => chunks,
      _ => throw UnsafeArchiveException('compresión $method no soportada'),
    };
    var crc = 0;
    await for (final chunk in plain) {
      crc = getCrc32(chunk, crc);
      yield chunk;
    }
    final expected = entry.crc32;
    if (expected != null && crc != expected) {
      throw UnsafeArchiveException('"${entry.name}" no coincide con su CRC');
    }
  }

  static Stream<List<int>> _chunksOf(InputStream stream) async* {
    while (!stream.isEOS) {
      final size = stream.length < 64 * 1024 ? stream.length : 64 * 1024;
      yield stream.readBytes(size).toUint8List();
    }
  }
}

/// Si el nombre de una entrada de un `.zip` es una ruta relativa sana: con
/// `/`, sin tramos vacíos ni `.` ni `..`, sin `\`, `:` ni bytes nulos, y que
/// no empieza con `/`. El mismo criterio que `IncomingVault.isSafeOriginalPath`.
bool isSafeEntryName(String name) {
  if (name.isEmpty || name.startsWith('/')) return false;
  if (name.contains(r'\') || name.contains(':') || name.contains('\u0000')) {
    return false;
  }
  return name.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}
