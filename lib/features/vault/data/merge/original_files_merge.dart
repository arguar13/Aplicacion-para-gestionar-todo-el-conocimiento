import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

/// Lo que hizo [OriginalFilesMerge].
class OriginalFilesResult {
  const OriginalFilesResult({
    this.copied = 0,
    this.copiedBytes = 0,
    this.missing = 0,
    this.differing = 0,
  });

  /// Archivos que faltaban acá y se copiaron de la copia, y cuánto pesan.
  final int copied;
  final int copiedBytes;

  /// Archivos que un elemento de acá referencia y no están ni acá ni en la
  /// copia: el elemento queda con su texto y sin su original.
  final int missing;

  /// Archivos que están en las dos con la misma ruta y distinto peso. Se queda
  /// el de acá: un archivo original no se pisa nunca.
  final int differing;
}

/// Copia a la carpeta de documentos los archivos originales que la copia trae y
/// esta bóveda necesita (F11).
///
/// «Necesita» es: los que alguna fila de acá referencia —la fuente o una forma
/// de archivo—, después de la fusión, y que en el disco no están. Así entran
/// los de los elementos nuevos y los de un elemento que ya estaba y había
/// perdido el suyo, y no entra un archivo que ninguna fila usa.
///
/// Nunca pisa un archivo que ya está. Y lo que copia lo lleva anotado: si la
/// fusión falla —antes o después de este paso—, [rollback] borra exactamente
/// eso, y la carpeta de documentos queda como estaba. El disco no tiene
/// transacciones; esto es lo más cerca.
class OriginalFilesMerge {
  OriginalFilesMerge({required Directory documents}) : _documents = documents;

  final Directory _documents;
  final List<File> _created = [];

  /// Copia lo que falta. Corre con la copia adjuntada y las filas ya escritas.
  Future<OriginalFilesResult> copy({
    required AppDatabase database,
    required IncomingVault incoming,
  }) async {
    final referenced = await database.customSelect('''
      SELECT original_blob_path AS path FROM main.source
       WHERE original_blob_path IS NOT NULL
      UNION
      SELECT relative_path AS path FROM main.renditions
       WHERE relative_path IS NOT NULL''').get();

    final inBackup = incoming.originalPaths.toSet();
    var copied = 0;
    var bytes = 0;
    var missing = 0;
    var differing = 0;
    for (final row in referenced) {
      final path = row.read<String>('path');
      final local = File(
        p.join(_documents.path, p.joinAll(p.posix.split(path))),
      );

      if (local.existsSync()) {
        final theirs = incoming.sizeOfOriginal(path);
        if (theirs != null && theirs != local.lengthSync()) differing++;
        continue;
      }
      if (!inBackup.contains(path)) {
        missing++;
        continue;
      }

      final written = await incoming.copyOriginalTo(path, _documents);
      if (written == null) {
        missing++;
        continue;
      }
      _created.add(written);
      copied++;
      bytes += written.lengthSync();
    }
    return OriginalFilesResult(
      copied: copied,
      copiedBytes: bytes,
      missing: missing,
      differing: differing,
    );
  }

  /// Borra lo que [copy] copió, y las carpetas que quedaron vacías por eso.
  Future<void> rollback() async {
    for (final file in _created) {
      try {
        if (file.existsSync()) await file.delete();
        final parent = file.parent;
        if (parent.existsSync() && parent.listSync().isEmpty) {
          await parent.delete();
        }
        // No poder borrar un archivo recién copiado no es motivo para tapar el
        // error que llevó hasta acá.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    _created.clear();
  }
}
