import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Corre contra SQLite y un sistema de archivos de verdad, en un directorio
/// temporal — igual que `app_database_test.dart`: lo que se prueba acá es
/// `VACUUM INTO` y el recorrido real de archivos, algo que un doble de
/// `AppDatabase` o de `Directory` no ejercitaría.
void main() {
  late AppDatabase db;
  late Directory docsDir;
  late LocalVaultBackupService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    docsDir = await Directory.systemTemp.createTemp('sinapsis_backup_test_');
    service = LocalVaultBackupService(
      database: db,
      documentsDirectory: () async => docsDir,
    );
  });

  tearDown(() async {
    await db.close();
    if (docsDir.existsSync()) await docsDir.delete(recursive: true);
  });

  Future<void> writeOriginal(String relativePath, String content) async {
    final file = File(p.join(docsDir.path, 'originales', relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  group('buildBackup', () {
    test('arma un zip con la base y los archivos originales', () async {
      await writeOriginal('doc-1/nota.txt', 'contenido de prueba');

      final bytes = await service.buildBackup();
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.files.map((f) => f.name), contains('sinapsis.sqlite'));
      expect(
        archive.files.map((f) => f.name),
        contains('originales/doc-1/nota.txt'),
      );

      final noteEntry = archive.files.firstWhere(
        (f) => f.name == 'originales/doc-1/nota.txt',
      );
      expect(
        String.fromCharCodes(noteEntry.content as List<int>),
        'contenido de prueba',
      );
    });

    test('funciona sin ningún archivo original guardado todavía', () async {
      final bytes = await service.buildBackup();
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.files.map((f) => f.name), ['sinapsis.sqlite']);
    });
  });

  group('isValidBackup', () {
    test('true para un backup armado por este mismo servicio', () async {
      final bytes = await service.buildBackup();
      expect(await service.isValidBackup(bytes), isTrue);
    });

    test('false para bytes que no son un zip', () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4]);
      expect(await service.isValidBackup(garbage), isFalse);
    });

    test('false para un zip que no trae la base de datos', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('otra-cosa.txt', [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

      expect(await service.isValidBackup(bytes), isFalse);
    });
  });

  group('restoreBackup', () {
    test('reemplaza los archivos originales por los del backup', () async {
      await writeOriginal('viejo/archivo.txt', 'esto debería desaparecer');
      final backupBeforeChange = await service.buildBackup();

      // Después de armar el backup, la bóveda "actual" cambia: agrega un
      // archivo nuevo que no estaba en la copia.
      await writeOriginal('nuevo/archivo.txt', 'esto es posterior al backup');

      await service.restoreBackup(backupBeforeChange);

      final restoredOld = File(
        p.join(docsDir.path, 'originales', 'viejo', 'archivo.txt'),
      );
      final restoredNew = File(
        p.join(docsDir.path, 'originales', 'nuevo', 'archivo.txt'),
      );

      expect(await restoredOld.readAsString(), 'esto debería desaparecer');
      // El archivo posterior al backup no estaba en el zip, así que
      // restaurar lo borra: es justo lo que significa "reemplazar todo".
      expect(restoredNew.existsSync(), isFalse);
    });

    test('escribe la base de datos del backup en el lugar esperado', () async {
      final bytes = await service.buildBackup();
      await service.restoreBackup(bytes);

      final dbFile = File(p.join(docsDir.path, 'sinapsis.sqlite'));
      expect(dbFile.existsSync(), isTrue);
    });

    test(
      'lanza InvalidVaultBackupException si el zip no trae la base',
      () async {
        final archive = Archive()
          ..addFile(ArchiveFile.bytes('otra-cosa.txt', [1, 2, 3]));
        final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

        expect(
          () => service.restoreBackup(bytes),
          throwsA(isA<InvalidVaultBackupException>()),
        );
      },
    );
  });
}
