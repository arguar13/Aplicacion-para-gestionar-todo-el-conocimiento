import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// [VaultBackupService] sobre el sistema de archivos, para Android, Windows,
/// Linux y macOS —donde `dart:io` existe—. Sin equivalente en la web: no hay
/// carpeta de documentos real ahí, y esta operación en particular no es la
/// prioridad de la decisión 9 (OPFS) en docs/arquitectura.md.
///
/// El nombre del archivo de la base adentro del `.zip` coincide a propósito
/// con el que usa `AppDatabase.open()` (`sinapsis.sqlite`, resuelto por
/// `drift_flutter`): así el mismo `.zip` sirve para llevar la bóveda de
/// Android a Windows o al revés, sin importar de qué plataforma salió.
class LocalVaultBackupService implements VaultBackupService {
  const LocalVaultBackupService({
    required AppDatabase database,
    Future<Directory> Function() documentsDirectory =
        getApplicationDocumentsDirectory,
  }) : _database = database,
       _documentsDirectory = documentsDirectory;

  final AppDatabase _database;
  final Future<Directory> Function() _documentsDirectory;

  static const _databaseEntryName = 'sinapsis.sqlite';
  static const _originalsFolder = 'originales';

  @override
  Future<Uint8List> buildBackup() async {
    final docsDir = await _documentsDirectory();
    // `Directory.systemTemp` y no `path_provider`, a propósito: esto es un
    // archivo de trabajo descartable, no algo que la app necesite encontrar
    // de nuevo entre reinicios — no hace falta el canal de plataforma de
    // `getTemporaryDirectory()` para eso, y así esta clase se puede probar
    // con `flutter test` puro, sin inicializar ningún binding.
    final tempDbCopy = File(
      p.join(
        Directory.systemTemp.path,
        'sinapsis-backup-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      ),
    );

    // `VACUUM INTO` deja una copia consistente del archivo aunque la base
    // siga abierta y en uso —a diferencia de copiar el archivo a mano, que
    // podría llevarse una escritura a mitad de camino, o los archivos `-wal`
    // / `-shm` sueltos si la conexión usa journal en modo WAL—. Corre sobre
    // la misma conexión que ya tiene la app abierta: no hace falta cerrar
    // nada para exportar.
    await _database.customStatement('VACUUM INTO ?', [tempDbCopy.path]);

    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(_databaseEntryName, await tempDbCopy.readAsBytes()),
      );
    await tempDbCopy.delete();

    final originalsDir = Directory(p.join(docsDir.path, _originalsFolder));
    if (originalsDir.existsSync()) {
      await for (final entity in originalsDir.list(recursive: true)) {
        if (entity is! File) continue;

        final relative = p.posix.joinAll(
          p.split(p.relative(entity.path, from: docsDir.path)),
        );
        archive.addFile(
          ArchiveFile.bytes(relative, await entity.readAsBytes()),
        );
      }
    }

    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  @override
  Future<bool> isValidBackup(Uint8List zipBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      return archive.files.any((file) => file.name == _databaseEntryName);
      // `decodeBytes` lanza sobre cualquier cosa que no sea un zip válido
      // —un PDF, una foto, un archivo a medio bajar—.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> restoreBackup(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    ArchiveFile? databaseFile;
    for (final file in archive.files) {
      if (file.name == _databaseEntryName) {
        databaseFile = file;
        break;
      }
    }
    if (databaseFile == null) {
      throw const InvalidVaultBackupException(
        'El archivo no tiene la base de datos de Sinapsis adentro.',
      );
    }

    final docsDir = await _documentsDirectory();
    final dbPath = p.join(docsDir.path, _databaseEntryName);

    await File(
      dbPath,
    ).writeAsBytes(databaseFile.content as List<int>, flush: true);
    // Restos de la base anterior que `VACUUM INTO` no deja, pero que un
    // cierre en modo WAL sí podría: sin esto, SQLite podría intentar
    // "recuperar" la base nueva aplicando el journal de la vieja.
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final journalFile = File('$dbPath$suffix');
      if (journalFile.existsSync()) await journalFile.delete();
    }

    final originalsDir = Directory(p.join(docsDir.path, _originalsFolder));
    if (originalsDir.existsSync()) {
      await originalsDir.delete(recursive: true);
    }

    for (final file in archive.files) {
      if (file.name == _databaseEntryName || !file.isFile) continue;

      final outFile = File(
        p.join(docsDir.path, p.joinAll(p.posix.split(file.name))),
      );
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>, flush: true);
    }
  }
}
