import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/entities/built_vault_backup.dart';
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

  /// Los bytes de una copia escritos a un archivo, que es como se lee: por su
  /// ruta, del disco.
  Future<String> asFile(Uint8List bytes, {String name = 'copia.zip'}) async {
    final file = File(p.join(docsDir.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

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

      for (final (i, bytes) in copies.indexed) {
        expect(
          await service.isValidBackup(await asFile(bytes, name: 'copia$i.zip')),
          isTrue,
        );
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

  group('buildBackupFile', () {
    test('arma el .zip en un archivo, con la base y los originales', () async {
      await writeOriginal('doc-1/nota.txt', 'contenido de prueba');
      await writeOriginal('doc-1/libro.pdf', 'no se comprime');

      final built = await service.buildBackupFile();
      addTearDown(() => service.discardBackup(built));

      final file = File(built.path);
      expect(file.existsSync(), isTrue);
      expect(built.sizeBytes, file.lengthSync());
      final archive = ZipDecoder().decodeBytes(
        file.readAsBytesSync(),
        verify: true,
      );
      expect(archive.files.map((f) => f.name).toSet(), {
        'sinapsis.sqlite',
        'originales/doc-1/nota.txt',
        'originales/doc-1/libro.pdf',
      });
      // Lo ya comprimido se guarda tal cual; lo demás, comprimido.
      CompressionType methodOf(String name) =>
          archive.files.firstWhere((f) => f.name == name).compression!;
      expect(methodOf('originales/doc-1/libro.pdf'), CompressionType.none);
      expect(methodOf('sinapsis.sqlite'), CompressionType.deflate);
    });

    test(
      'la base de la copia no queda además suelta en la carpeta de trabajo',
      () async {
        final built = await service.buildBackupFile();
        addTearDown(() => service.discardBackup(built));

        final leftovers = File(
          built.path,
        ).parent.listSync().map((e) => p.basename(e.path));

        expect(leftovers, ['copia.zip']);
      },
    );

    test('soltarla borra el .zip y su carpeta de trabajo', () async {
      final built = await service.buildBackupFile();

      await service.discardBackup(built);

      expect(File(built.path).existsSync(), isFalse);
      expect(File(built.path).parent.existsSync(), isFalse);
    });

    test('soltarla no borra una carpeta que no armó este servicio', () async {
      final stranger = await Directory.systemTemp.createTemp('otra_cosa_');
      addTearDown(() => stranger.delete(recursive: true));
      final file = File(p.join(stranger.path, 'importante.zip'))
        ..writeAsBytesSync([1, 2, 3]);

      await service.discardBackup(
        BuiltVaultBackup(path: file.path, sizeBytes: 3),
      );

      expect(file.existsSync(), isTrue);
    });

    test(
      'la copia armada se fusiona: es la misma que arma buildBackup',
      () async {
        final built = await service.buildBackupFile();
        addTearDown(() => service.discardBackup(built));

        final preview = await service.previewMerge(built.path);

        expect(preview.hasNothingNew, isTrue);
      },
    );

    test('si falla armándola, no deja la carpeta de trabajo', () async {
      final temp = await Directory.systemTemp.createTemp('sinapsis_bk_test_');
      addTearDown(() => temp.delete(recursive: true));

      await IOOverrides.runZoned(() async {
        // Una copia que sale bien no deja nada tampoco, una vez soltada.
        await service.discardBackup(await service.buildBackupFile());
        // Una base cerrada —después de haberla usado—: `VACUUM INTO` falla.
        await db.close();
        await expectLater(service.buildBackupFile(), throwsA(isA<Object>()));
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

  group('previewMerge y mergeBackup, por ruta', () {
    test('la copia de esta misma bóveda no trae nada nuevo', () async {
      final path = await asFile(await service.buildBackup());

      final preview = await service.previewMerge(path);

      expect(preview.hasNothingNew, isTrue);
    });

    test(
      'un archivo que no existe es una copia inválida, no un fallo',
      () async {
        final missing = p.join(docsDir.path, 'no-esta.zip');

        await expectLater(
          service.previewMerge(missing),
          throwsA(isA<InvalidVaultBackupException>()),
        );
        await expectLater(
          service.mergeBackup(missing),
          throwsA(isA<InvalidVaultBackupException>()),
        );
      },
    );

    test('ni ver qué traería ni fusionar dejan el archivo abierto', () async {
      final path = await asFile(await service.buildBackup());

      await service.previewMerge(path);
      await service.mergeBackup(path);

      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('isValidBackup', () {
    test('true para un backup armado por este mismo servicio', () async {
      final bytes = await service.buildBackup();
      expect(await service.isValidBackup(await asFile(bytes)), isTrue);
    });

    test('false para bytes que no son un zip', () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4]);
      expect(await service.isValidBackup(await asFile(garbage)), isFalse);
    });

    test('false para un zip que no trae la base de datos', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('otra-cosa.txt', [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

      expect(await service.isValidBackup(await asFile(bytes)), isFalse);
    });

    test('false para un archivo que no existe', () async {
      final missing = p.join(docsDir.path, 'no-esta.zip');

      expect(await service.isValidBackup(missing), isFalse);
    });

    test('no deja el archivo abierto: se puede borrar después', () async {
      final path = await asFile(await service.buildBackup());

      expect(await service.isValidBackup(path), isTrue);

      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
    });
  });
}
