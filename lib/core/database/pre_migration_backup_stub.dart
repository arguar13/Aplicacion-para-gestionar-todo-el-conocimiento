import 'package:sqlite3/common.dart';

/// Cuántas copias previas a una migración se conservan. Sin efecto en web.
const kPreMigrationBackupsToKeep = 3;

/// En web no hay un archivo de base que copiar —vive en OPFS/IndexedDB, y
/// drift ni siquiera llama a `setup` ahí—: no hace nada. La protección en
/// web es que la migración corre en una transacción; si falla, revierte.
String? backupBeforeMigration(
  CommonDatabase db, {
  required int targetVersion,
  int keep = kPreMigrationBackupsToKeep,
}) => null;
