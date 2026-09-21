import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/vault_merge_reader.dart';
import 'package:sinapsis/features/vault/data/merge/vault_merger.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';
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

  static const _databaseEntryName = kBackupDatabaseEntryName;
  static const _originalsFolder = kBackupOriginalsFolder;

  @override
  Future<Uint8List> buildBackup() async {
    final docsDir = await _documentsDirectory();
    // `Directory.systemTemp` y no `path_provider`, a propósito: esto es un
    // archivo de trabajo descartable, no algo que la app necesite encontrar
    // de nuevo entre reinicios — no hace falta el canal de plataforma de
    // `getTemporaryDirectory()` para eso, y así esta clase se puede probar
    // con `flutter test` puro, sin inicializar ningún binding.
    //
    // Un directorio propio, creado por el sistema, y no un nombre armado con la
    // hora: en Windows el reloj avanza a saltos de un milisegundo, y dos copias
    // pedidas casi a la vez —dos procesos, o dos pruebas en paralelo— elegían
    // el mismo archivo y `VACUUM INTO` fallaba con «database is locked». Y como
    // se borra en un `finally`, una copia que falla no deja el archivo a
    // medias.
    final workDir = await Directory.systemTemp.createTemp('sinapsis-backup-');
    final Uint8List databaseBytes;
    try {
      final tempDbCopy = File(p.join(workDir.path, _databaseEntryName));

      // `VACUUM INTO` deja una copia consistente del archivo aunque la base
      // siga abierta y en uso —a diferencia de copiar el archivo a mano, que
      // podría llevarse una escritura a mitad de camino, o los archivos `-wal`
      // / `-shm` sueltos si la conexión usa journal en modo WAL—. Corre sobre
      // la misma conexión que ya tiene la app abierta: no hace falta cerrar
      // nada para exportar.
      await _database.customStatement('VACUUM INTO ?', [tempDbCopy.path]);
      databaseBytes = await tempDbCopy.readAsBytes();
    } finally {
      await workDir.delete(recursive: true);
    }

    final archive = Archive()
      ..addFile(ArchiveFile.bytes(_databaseEntryName, databaseBytes));

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
  Future<bool> isValidBackup(String zipPath) async {
    InputFileStream? input;
    try {
      // Solo se lee el índice del final del archivo: no hace falta abrir la
      // copia entera para saber si trae la base.
      input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(input);
      return archive.files.any((file) => file.name == _databaseEntryName);
      // Lanza sobre cualquier cosa que no sea un zip válido —un PDF, una foto,
      // un archivo a medio bajar— y sobre un archivo que ya no está.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    } finally {
      await input?.close();
    }
  }

  @override
  Future<VaultMergePreview> previewMerge(String zipPath) async {
    final incoming = await IncomingVault.openFile(File(zipPath));
    try {
      return await VaultMergeReader(
        database: _database,
        documentsDirectory: await _documentsDirectory(),
      ).preview(incoming);
    } finally {
      await incoming.dispose();
    }
  }

  @override
  Future<VaultMergeResult> mergeBackup(String zipPath) async {
    final incoming = await IncomingVault.openFile(File(zipPath));
    try {
      return await VaultMerger(
        database: _database,
        documentsDirectory: await _documentsDirectory(),
      ).merge(incoming);
    } finally {
      await incoming.dispose();
    }
  }
}
