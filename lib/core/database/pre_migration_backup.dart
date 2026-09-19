// Respaldo automático de la base ANTES de que drift la migre — F8.
//
// Import condicional: en nativo hace la copia de verdad; en web, donde no
// hay un archivo que copiar, es un no-op (la migración es transaccional:
// si falla, SQLite revierte y la base queda como estaba).
export 'pre_migration_backup_exception.dart';
export 'pre_migration_backup_stub.dart'
    if (dart.library.io) 'pre_migration_backup_io.dart';
