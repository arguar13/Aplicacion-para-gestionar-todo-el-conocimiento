import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/pre_migration_backup_exception.dart';
import 'package:sqlite3/common.dart';

/// Cuántas copias previas a una migración se conservan.
const kPreMigrationBackupsToKeep = 3;

/// Si la base que se acaba de abrir es de una versión anterior a
/// [targetVersion] —o sea, drift está por migrarla—, la copia ANTES de que
/// migre, a `<base>.pre-v<versión-actual>.bak`. Devuelve la ruta de la
/// copia, o `null` si no hacía falta (base nueva, ya al día, o en memoria).
///
/// Está pensada para el `setup` de la conexión nativa de drift: corre sobre
/// el SQLite crudo, antes de que drift toque nada. Tiene que ser así y no
/// dentro de `onUpgrade`: drift corre las migraciones en una transacción y
/// `VACUUM INTO` no puede ejecutarse dentro de una.
///
/// `VACUUM INTO` y no copiar el archivo a mano: deja una copia consistente
/// aunque haya un `-wal` sin consolidar — el mismo motivo que ya llevó a
/// `VaultBackupService` a usarlo (decisión 16).
///
/// Solo respalda la base. Los archivos originales (PDF, audio, imágenes)
/// no los toca ninguna migración de este encargo. Conserva las últimas
/// [keep] copias.
String? backupBeforeMigration(
  CommonDatabase db, {
  required int targetVersion,
  int keep = kPreMigrationBackupsToKeep,
}) {
  final currentVersion = db.userVersion;
  // 0 es una base recién creada: `onCreate` no migra nada.
  if (currentVersion == 0 || currentVersion >= targetVersion) return null;

  final databaseFile = _mainDatabaseFile(db);
  if (databaseFile == null) return null;

  final backupPath = '$databaseFile.pre-v$currentVersion.bak';
  try {
    // `VACUUM INTO` se niega a escribir sobre un archivo que ya existe —el
    // resto de un intento anterior—.
    final leftover = File(backupPath);
    if (leftover.existsSync()) leftover.deleteSync();

    final quoted = backupPath.replaceAll("'", "''");
    db.execute("VACUUM INTO '$quoted'");
  } on Object catch (e) {
    throw PreMigrationBackupException(
      'No se pudo respaldar la base antes de migrar de v$currentVersion a '
      'v$targetVersion; se cancela la migración para no arriesgar datos.',
      e,
    );
  }

  _pruneOldBackups(databaseFile, keep: keep);
  return backupPath;
}

/// La ruta del archivo de la base principal, o `null` si es en memoria o
/// temporal (`file` viene vacío).
String? _mainDatabaseFile(CommonDatabase db) {
  for (final row in db.select('PRAGMA database_list')) {
    if (row['name'] == 'main') {
      final file = row['file'] as String?;
      return (file == null || file.isEmpty) ? null : file;
    }
  }
  return null;
}

void _pruneOldBackups(String databaseFile, {required int keep}) {
  final prefix = '${p.basename(databaseFile)}.pre-v';
  final backups =
      File(databaseFile).parent.listSync().whereType<File>().where((f) {
          final name = p.basename(f.path);
          return name.startsWith(prefix) && name.endsWith('.bak');
        }).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  for (final old in backups.skip(keep)) {
    try {
      old.deleteSync();
    } on FileSystemException {
      // No poder borrar una copia VIEJA no compromete nada: la copia nueva
      // ya está hecha y verificada por `VACUUM INTO`. Quedará de más
      // hasta la próxima migración.
    }
  }
}
