import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';

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

    test('muchas copias a la vez no chocan entre sí', () async {
      // Antes el archivo de trabajo se llamaba con la hora en microsegundos, y
      // en Windows —reloj a saltos de un milisegundo— dos copias casi
      // simultáneas elegían el mismo y una fallaba con «database is locked».
      final copies = await Future.wait([
        for (var i = 0; i < 12; i++) service.buildBackup(),
      ]);

      for (final bytes in copies) {
        expect(await service.isValidBackup(bytes), isTrue);
      }
    });

    test('no deja archivos de trabajo, ni si la copia falla', () async {
      final temp = await Directory.systemTemp.createTemp('sinapsis_bk_test_');
      addTearDown(() => temp.delete(recursive: true));

      await IOOverrides.runZoned(() async {
        await service.buildBackup();
        // Una base cerrada: `VACUUM INTO` falla a mitad de la copia.
        await db.close();
        await expectLater(service.buildBackup(), throwsA(isA<Object>()));
      }, getSystemTempDirectory: () => temp);

      expect(temp.listSync(), isEmpty);
      // Vuelve a abrirse una para que el `tearDown` pueda cerrarla.
      db = AppDatabase(NativeDatabase.memory());
      service = LocalVaultBackupService(
        database: db,
        documentsDirectory: () async => docsDir,
      );
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
}
