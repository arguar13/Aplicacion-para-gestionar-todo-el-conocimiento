import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// El nombre con el que se ve la base de la copia una vez adjuntada a la de
/// esta bóveda: `incoming.item`, `incoming.renditions`…
const kIncomingSchema = 'incoming';

/// Una copia de otra bóveda, abierta SOLO para leerla (F11).
///
/// Desempaqueta el `.zip` en un temporal y se asegura de que la base de la
/// copia tenga el esquema de esta versión de la app: si es más vieja, la
/// actualiza ELLA —la copia, en su temporal, con los mismos pasos y compuertas
/// que cualquier migración; el respaldo es el propio `.zip`, que no se toca—,
/// nunca esta bóveda. Con la base al día,
/// las dos tienen las mismas tablas y las mismas columnas, y se pueden leer
/// juntas con una sola consulta adjuntándola a la conexión de esta bóveda
/// ([attachTo]).
///
/// Es de un solo uso: al terminar, [dispose] borra el temporal.
class IncomingVault {
  IncomingVault._({
    required this.directory,
    required this.databaseFile,
    required this.schemaVersion,
    required Archive archive,
  }) : _archive = archive;

  /// El temporal donde vive la copia desempaquetada.
  final Directory directory;

  /// La base de la copia, ya con el esquema de esta versión.
  final File databaseFile;

  /// El esquema que traía la base de la copia, ANTES de actualizarla.
  final int schemaVersion;

  final Archive _archive;

  /// Abre la copia [zipBytes].
  ///
  /// Lanza [InvalidVaultBackupException] si no es un `.zip` con una base de
  /// Sinapsis adentro, [VaultBackupTooNewException] si su esquema es más nuevo
  /// que el de esta versión, y [SchemaTooOldException] si es tan viejo que esta
  /// versión no sabe actualizarlo. Antes de lanzar deja el temporal limpio.
  static Future<IncomingVault> open(Uint8List zipBytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
      // `decodeBytes` lanza sobre cualquier cosa que no sea un zip válido.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw const InvalidVaultBackupException(
        'El archivo no es una copia de Sinapsis: no es un .zip válido.',
      );
    }

    ArchiveFile? databaseEntry;
    for (final file in archive.files) {
      if (file.name == kBackupDatabaseEntryName) databaseEntry = file;
    }
    if (databaseEntry == null) {
      throw const InvalidVaultBackupException(
        'El archivo no tiene la base de datos de Sinapsis adentro.',
      );
    }

    final directory = await Directory.systemTemp.createTemp('sinapsis-merge-');
    try {
      final file = File(p.join(directory.path, 'incoming.sqlite'));
      await file.writeAsBytes(databaseEntry.content as List<int>, flush: true);

      return IncomingVault._(
        directory: directory,
        databaseFile: file,
        schemaVersion: await _readyToRead(file),
        archive: archive,
      );
      // Cualquier fallo deja el temporal limpio: nadie más sabe que existe.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await _deleteQuietly(directory);
      rethrow;
    }
  }

  /// Abre una copia que ya está descomprimida: el archivo de su base [source].
  ///
  /// Para las pruebas y los bancos de medida, que fusionan bóvedas de cientos
  /// de megas sin empaquetarlas en un `.zip` que cabría mal en memoria. Trabaja
  /// sobre una copia del archivo —el original no se toca— y no trae archivos
  /// originales. Se rechaza igual que [open].
  static Future<IncomingVault> fromDatabaseFile(File source) async {
    final directory = await Directory.systemTemp.createTemp('sinapsis-merge-');
    try {
      final file = File(p.join(directory.path, 'incoming.sqlite'));
      await source.copy(file.path);

      return IncomingVault._(
        directory: directory,
        databaseFile: file,
        schemaVersion: await _readyToRead(file),
        archive: Archive(),
      );
      // Igual que en [open]: cualquier fallo deja el temporal limpio.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await _deleteQuietly(directory);
      rethrow;
    }
  }

  /// Comprueba el esquema de la base [file] y, si es más vieja, la actualiza.
  /// Devuelve el esquema que traía.
  static Future<int> _readyToRead(File file) async {
    final version = _userVersionOf(file);
    if (version > AppDatabase.currentSchemaVersion) {
      throw VaultBackupTooNewException(
        backupVersion: version,
        currentVersion: AppDatabase.currentSchemaVersion,
      );
    }
    if (version < AppDatabase.minimumUpgradableSchemaVersion) {
      throw SchemaTooOldException(
        from: version,
        minimum: AppDatabase.minimumUpgradableSchemaVersion,
      );
    }
    if (version < AppDatabase.currentSchemaVersion) await _upgrade(file);
    return version;
  }

  /// El esquema de la base [file], leído sin abrirla con drift: abrirla la
  /// migraría, y para saber si hace falta —o si no se puede— hay que mirar
  /// antes.
  static int _userVersionOf(File file) {
    final sqlite3.Database db;
    try {
      db = sqlite3.sqlite3.open(file.path, mode: sqlite3.OpenMode.readOnly);
    } on sqlite3.SqliteException {
      throw const InvalidVaultBackupException(
        'La base de datos de la copia no se puede abrir.',
      );
    }
    try {
      final version = db.select('PRAGMA user_version').first.values.first;
      // Un archivo que no es una base de SQLite falla recién al leer.
      if (version is! int || version == 0) {
        throw const InvalidVaultBackupException(
          'La base de datos de la copia está vacía.',
        );
      }
      return version;
    } on sqlite3.SqliteException {
      throw const InvalidVaultBackupException(
        'La base de datos de la copia está dañada o no es de Sinapsis.',
      );
    } finally {
      db.close();
    }
  }

  /// Deja la base [file] con el esquema de esta versión abriéndola con
  /// `AppDatabase`, que la migra.
  static Future<void> _upgrade(File file) async {
    // Drift avisa cuando se crea una segunda base de la misma clase porque dos
    // sobre el MISMO ejecutor se pisarían. Esta es de otro archivo, con su
    // propia conexión: el aviso no aplica, y solo se calla mientras se crea.
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final AppDatabase db;
    try {
      db = AppDatabase(NativeDatabase(file));
    } finally {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
    }
    try {
      await db.customSelect('SELECT 1').get();
    } finally {
      await db.close();
    }
  }

  /// Adjunta la base de la copia a la conexión de [local], como
  /// [kIncomingSchema]. No puede haber una transacción abierta: SQLite no deja
  /// adjuntar dentro de una.
  Future<void> attachTo(AppDatabase local) => local.customStatement(
    'ATTACH DATABASE ? AS $kIncomingSchema',
    [databaseFile.path],
  );

  /// Suelta la base de la copia de la conexión de [local].
  Future<void> detachFrom(AppDatabase local) =>
      local.customStatement('DETACH DATABASE $kIncomingSchema');

  /// Si [name] es la ruta de un archivo original que se puede copiar sin salir
  /// de la carpeta de documentos: dentro de `originales/`, con `/`, sin
  /// segmentos vacíos ni `.` ni `..`, y sin `\`, `:` ni bytes nulos.
  ///
  /// Un `.zip` trae los nombres que quiso quien lo armó, y `originales/../..`
  /// escribiría fuera de la bóveda. Lo que guarda la app nunca es así —el
  /// almacén sanea los nombres a letras, números, espacio, punto, guion y guion
  /// bajo—, así que este filtro solo deja afuera lo que una copia legítima no
  /// tiene.
  static bool isSafeOriginalPath(String name) {
    if (!name.startsWith('$kBackupOriginalsFolder/')) return false;
    if (name.contains(r'\') || name.contains(':') || name.contains('\u0000')) {
      return false;
    }
    return name.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
  }

  /// Los archivos de la copia que son originales y [isSafeOriginalPath] deja
  /// pasar.
  Iterable<ArchiveFile> get _originals => _archive.files.where(
    (file) => file.isFile && isSafeOriginalPath(file.name),
  );

  /// Las rutas —relativas a la carpeta de documentos, con `/`— de los archivos
  /// originales que trae la copia.
  Iterable<String> get originalPaths => _originals.map((file) => file.name);

  /// Cuánto pesa, sin descomprimirlo, el archivo [relativePath] de la copia; o
  /// `null` si la copia no lo trae.
  int? sizeOfOriginal(String relativePath) {
    for (final file in _originals) {
      if (file.name == relativePath) return file.size;
    }
    return null;
  }

  /// Copia el archivo original [relativePath] de la copia a [root], en la misma
  /// ruta relativa. Devuelve el archivo escrito, o `null` si la copia no lo
  /// trae.
  Future<File?> copyOriginalTo(String relativePath, Directory root) async {
    for (final file in _originals) {
      if (file.name != relativePath) continue;
      final out = File(
        p.join(root.path, p.joinAll(p.posix.split(relativePath))),
      );
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>, flush: true);
      return out;
    }
    return null;
  }

  /// Borra el temporal. Se llama al terminar, pase lo que pase.
  Future<void> dispose() => _deleteQuietly(directory);

  static Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      // En Windows un archivo recién cerrado puede tardar en soltarse: un
      // temporal que no se pudo borrar no es motivo para fallar una fusión que
      // ya terminó.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}
