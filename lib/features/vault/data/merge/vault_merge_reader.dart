import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';

/// Lee una copia de otra bóveda contra ESTA y dice qué traería (F11).
///
/// La vista previa en seco de una fusión: solo lee las dos bases, con la de la
/// copia adjuntada a la conexión de esta, y no escribe ninguna. Lo hace en
/// SQL y no trayendo las filas a Dart: una bóveda de diez mil elementos se
/// cuenta en milisegundos, y sus textos no pasan por la memoria.
class VaultMergeReader {
  const VaultMergeReader({
    required AppDatabase database,
    required Directory documentsDirectory,
  }) : _db = database,
       _documents = documentsDirectory;

  final AppDatabase _db;

  /// La carpeta de documentos de esta bóveda: donde están sus archivos
  /// originales.
  final Directory _documents;

  static const _incoming = kIncomingSchema;

  /// Qué traería [incoming]. La adjunta a la base de esta bóveda mientras
  /// cuenta y la suelta al terminar, pase lo que pase.
  Future<VaultMergePreview> preview(IncomingVault incoming) async {
    await incoming.attachTo(_db);
    try {
      return await _count(incoming);
    } finally {
      await incoming.detachFrom(_db);
    }
  }

  Future<VaultMergePreview> _count(IncomingVault incoming) async {
    // Los elementos, por tipo y según los tenga esta bóveda o no: el
    // identificador es la identidad, así que uno que las dos tienen es el mismo
    // aunque se haya editado en cada una.
    final items = await _db.customSelect('''
      SELECT i.kind AS kind,
             EXISTS (SELECT 1 FROM main.item m WHERE m.id = i.id) AS common,
             COUNT(*) AS n
        FROM $_incoming.item i
       GROUP BY i.kind, common''').get();

    var newSources = 0;
    var newNotes = 0;
    var common = 0;
    var total = 0;
    for (final row in items) {
      final n = row.read<int>('n');
      total += n;
      if (row.read<int>('common') == 1) {
        common += n;
      } else if (row.read<String>('kind') == 'note') {
        newNotes += n;
      } else {
        newSources += n;
      }
    }

    final files = await _files(incoming);

    return VaultMergePreview(
      incomingItems: total,
      newSources: newSources,
      newNotes: newNotes,
      commonItems: common,
      // Un vínculo es el mismo si tiene el mismo id o si une lo mismo con el
      // mismo tipo: dos bóvedas pudieron crearlo por separado.
      newRelations: await _scalar('''
        SELECT COUNT(*) FROM $_incoming.relations r
         WHERE NOT EXISTS (
           SELECT 1 FROM main.relations m
            WHERE m.id = r.id
               OR (m.from_item_id = r.from_item_id
                   AND m.to_item_id = r.to_item_id
                   AND m.kind = r.kind))'''),
      newHighlights: await _scalar(
        '''
        SELECT COUNT(*) FROM $_incoming.highlights h
         WHERE NOT EXISTS (SELECT 1 FROM main.highlights m WHERE m.id = h.id)''',
      ),
      newFlashcards: await _scalar(
        '''
        SELECT COUNT(*) FROM $_incoming.flashcards f
         WHERE NOT EXISTS (SELECT 1 FROM main.flashcards m WHERE m.id = f.id)''',
      ),
      // Un espacio es el mismo si tiene el mismo id o el mismo nombre sin
      // distinguir mayúsculas: dos con el mismo nombre no pueden convivir.
      newSpaces: await _scalar('''
        SELECT COUNT(*) FROM $_incoming.spaces s
         WHERE NOT EXISTS (
           SELECT 1 FROM main.spaces m
            WHERE m.id = s.id OR lower(m.name) = lower(s.name))'''),
      newFiles: files.missingLocally.length,
      newFilesBytes: files.missingLocallyBytes,
      filesMissingInBackup: files.missingInBackup,
    );
  }

  Future<int> _scalar(String sql) async =>
      (await _db.customSelect(sql).getSingle()).data.values.first! as int;

  /// Los archivos originales que la copia referencia: cuáles esta bóveda no
  /// tiene y cuáles la copia dice tener y no trae.
  Future<_Files> _files(IncomingVault incoming) async {
    final referenced = <String>{};
    for (final row in await _db.customSelect('''
      SELECT original_blob_path AS path FROM $_incoming.source
       WHERE original_blob_path IS NOT NULL
      UNION
      SELECT relative_path AS path FROM $_incoming.renditions
       WHERE relative_path IS NOT NULL''').get()) {
      referenced.add(row.read<String>('path'));
    }

    final inBackup = incoming.originalPaths.toSet();
    final missingLocally = <String>[];
    var bytes = 0;
    var missingInBackup = 0;
    for (final path in referenced) {
      final local = File(
        p.join(_documents.path, p.joinAll(p.posix.split(path))),
      );
      if (local.existsSync()) continue;
      if (inBackup.contains(path)) {
        missingLocally.add(path);
        bytes += incoming.sizeOfOriginal(path) ?? 0;
      } else {
        missingInBackup++;
      }
    }
    return _Files(missingLocally, bytes, missingInBackup);
  }
}

class _Files {
  const _Files(
    this.missingLocally,
    this.missingLocallyBytes,
    this.missingInBackup,
  );

  final List<String> missingLocally;
  final int missingLocallyBytes;
  final int missingInBackup;
}
