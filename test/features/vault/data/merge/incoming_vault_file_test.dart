import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../../support/rss_sampler.dart';
import '../../../../support/test_vault.dart';

/// Arma en otro aislado un `.zip` con [databasePath] adentro como la entrada de
/// la base, comprimida como lo hace la app.
///
/// Es otro aislado a propósito: comprimir un archivo grande con `archive` usa
/// cientos de MB, y si eso pasara en el aislado de la prueba, la memoria del
/// proceso quedaría inflada y la medición de después no vería lo que crece.
Future<void> _zipDatabase(String zipPath, String databasePath) =>
    Isolate.run(() async {
      final encoder = ZipFileEncoder()..create(zipPath);
      await encoder.addFile(File(databasePath), kBackupDatabaseEntryName);
      await encoder.close();
    });

/// Abrir la copia DESDE EL DISCO (F12): el `.zip` de una bóveda grande no pasa
/// entero por la memoria, y se rechaza, se actualiza y se limpia igual que
/// cuando se abre desde bytes.
void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('sinapsis_incoming_file_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  /// Corre [body] con un directorio temporal PROPIO, para poder mirar qué dejó
  /// el código atrás sin que lo confundan otras pruebas corriendo a la vez.
  Future<T> withOwnTemp<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getSystemTempDirectory: () => tempRoot);

  List<String> leftovers() => [
    for (final e in tempRoot.listSync())
      if (p.basename(e.path).startsWith('sinapsis-merge-')) e.path,
  ];

  Future<File> writeZip(Map<String, List<int>> entries) async {
    final file = File(p.join(tempRoot.path, 'copia.zip'));
    await file.writeAsBytes(zipOf(entries));
    return file;
  }

  /// Si el `.zip` quedó abierto, en Windows no se puede borrar.
  void expectZipReleased(File zip) {
    zip.deleteSync();
    expect(zip.existsSync(), isFalse);
  }

  group('lo mismo que abrir los bytes', () {
    test('trae la misma base y los mismos originales, y los copia', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      // Más de un búfer de escritura (1 MiB): se copia en varias tandas.
      final big = List.generate(
        200000,
        (i) => 'línea $i del original',
      ).join('\n');
      await vault.saveSource(
        'a',
        text: 'Texto de a.',
        originalName: 'a.txt',
        originalContent: big,
      );
      await vault.saveSource('b', text: 'Texto de b.');
      final bytes = await vault.zip();
      final file = File(p.join(tempRoot.path, 'copia.zip'));
      await file.writeAsBytes(bytes);

      final fromBytes = await IncomingVault.open(bytes);
      addTearDown(fromBytes.dispose);
      final fromFile = await IncomingVault.openFile(file);
      addTearDown(fromFile.dispose);

      expect(fromFile.schemaVersion, fromBytes.schemaVersion);
      expect(fromFile.originalPaths.toSet(), fromBytes.originalPaths.toSet());
      expect(fromFile.originalPaths, ['originales/a/a.txt']);
      expect(
        fromFile.sizeOfOriginal('originales/a/a.txt'),
        fromBytes.sizeOfOriginal('originales/a/a.txt'),
      );
      List<String> ids(IncomingVault v) {
        final db = sqlite3.sqlite3.open(
          v.databaseFile.path,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          return [
            for (final r in db.select('SELECT id FROM item ORDER BY id'))
              r['id'] as String,
          ];
        } finally {
          db.close();
        }
      }

      expect(ids(fromFile), ['a', 'b']);
      expect(ids(fromFile), ids(fromBytes));

      final out = Directory(p.join(tempRoot.path, 'documentos'))..createSync();
      final copied = await fromFile.copyOriginalTo('originales/a/a.txt', out);
      expect(copied!.readAsStringSync(), big);
      expect(copied.path, p.join(out.path, 'originales', 'a', 'a.txt'));
    });

    test('la copia de una versión vieja se actualiza igual, la copia y no '
        'esta', () async {
      final file = File(p.join(tempRoot.path, 'vieja.zip'));
      await file.writeAsBytes(await vaultCopyAtV19(text: 'Texto viejo.'));

      final incoming = await IncomingVault.openFile(file);
      addTearDown(incoming.dispose);

      expect(incoming.schemaVersion, 19);
      final db = sqlite3.sqlite3.open(
        incoming.databaseFile.path,
        mode: sqlite3.OpenMode.readOnly,
      );
      addTearDown(db.close);
      expect(
        db.select('PRAGMA user_version').single.values.single,
        AppDatabase.currentSchemaVersion,
      );
    });

    test('las rutas peligrosas no se listan ni se copian', () async {
      final file = await writeZip({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(
          AppDatabase.currentSchemaVersion,
        ),
        'originales/bueno.txt': 'ok'.codeUnits,
        'originales/../fuera.txt': 'no'.codeUnits,
        'originales/a/../../fuera2.txt': 'no'.codeUnits,
        r'originales\raro.txt': 'no'.codeUnits,
        'fuera/de/originales.txt': 'no'.codeUnits,
      });

      final incoming = await IncomingVault.openFile(file);
      addTearDown(incoming.dispose);

      expect(incoming.originalPaths, ['originales/bueno.txt']);
    });
  });

  group('lo que se rechaza', () {
    test('un archivo que no es un .zip, sin dejar nada ni abierto', () async {
      final file = File(p.join(tempRoot.path, 'foto.zip'));
      await file.writeAsBytes(
        Uint8List.fromList(List.generate(4096, (i) => i)),
      );

      await withOwnTemp(() async {
        await expectLater(
          IncomingVault.openFile(file),
          throwsA(isA<InvalidVaultBackupException>()),
        );
      });

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });

    test('un .zip sin la base de Sinapsis adentro', () async {
      final file = await writeZip({'otra-cosa.txt': 'hola'.codeUnits});

      await withOwnTemp(() async {
        await expectLater(
          IncomingVault.openFile(file),
          throwsA(isA<InvalidVaultBackupException>()),
        );
      });

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });

    test('un archivo que no existe es otro archivo que elegir', () async {
      await expectLater(
        IncomingVault.openFile(File(p.join(tempRoot.path, 'no-esta.zip'))),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });

    test('una base de una versión más nueva que esta', () async {
      final file = await writeZip({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(
          AppDatabase.currentSchemaVersion + 1,
        ),
      });

      await withOwnTemp(() async {
        await expectLater(
          IncomingVault.openFile(file),
          throwsA(isA<VaultBackupTooNewException>()),
        );
      });

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });

    test('una base de una versión demasiado vieja', () async {
      final file = await writeZip({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(
          AppDatabase.minimumUpgradableSchemaVersion - 1,
        ),
      });

      await withOwnTemp(() async {
        await expectLater(
          IncomingVault.openFile(file),
          throwsA(isA<SchemaTooOldException>()),
        );
      });

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });

    test('una base que no es de SQLite', () async {
      final file = await writeZip({
        kBackupDatabaseEntryName: Uint8List.fromList(
          List.generate(8192, (i) => (i * 7) & 0xff),
        ),
      });

      await withOwnTemp(() async {
        await expectLater(
          IncomingVault.openFile(file),
          throwsA(isA<InvalidVaultBackupException>()),
        );
      });

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });
  });

  group('el contenido de cada entrada', () {
    test('una entrada guardada sin comprimir sale igual', () async {
      final text = List.generate(5000, (i) => 'línea $i').join('\n');
      final encoded = utf8.encode(text);
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            kBackupDatabaseEntryName,
            await sqliteBytesAtVersion(AppDatabase.currentSchemaVersion),
          ),
        )
        ..addFile(
          ArchiveFile.noCompress(
            'originales/plano.txt',
            encoded.length,
            encoded,
          ),
        );
      final file = File(p.join(tempRoot.path, 'sin-comprimir.zip'));
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
      final incoming = await IncomingVault.openFile(file);
      addTearDown(incoming.dispose);

      final out = Directory(p.join(tempRoot.path, 'documentos'))..createSync();
      final copied = await incoming.copyOriginalTo('originales/plano.txt', out);

      expect(copied!.readAsStringSync(), text);
    });

    test('se puede copiar dos veces el mismo original', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      await vault.saveSource(
        'a',
        originalName: 'a.txt',
        originalContent: 'hola',
      );
      final file = File(p.join(tempRoot.path, 'copia.zip'));
      await file.writeAsBytes(await vault.zip());
      final incoming = await IncomingVault.openFile(file);
      addTearDown(incoming.dispose);
      final one = Directory(p.join(tempRoot.path, 'uno'))..createSync();
      final two = Directory(p.join(tempRoot.path, 'dos'))..createSync();

      final first = await incoming.copyOriginalTo('originales/a/a.txt', one);
      final second = await incoming.copyOriginalTo('originales/a/a.txt', two);

      expect(first!.readAsStringSync(), 'hola');
      expect(second!.readAsStringSync(), 'hola');
    });

    test('una copia a la que le cambiaron bytes se rechaza y no deja el '
        'archivo a medias', () async {
      final text = 'ABCDEFGHIJ' * 100;
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            kBackupDatabaseEntryName,
            await sqliteBytesAtVersion(AppDatabase.currentSchemaVersion),
          ),
        )
        ..addFile(
          ArchiveFile.noCompress(
            'originales/plano.txt',
            text.length,
            text.codeUnits,
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
      // Sin comprimir, el texto está tal cual en el .zip: se cambia un byte.
      final at = String.fromCharCodes(bytes).indexOf('ABCDEFGHIJ');
      expect(at, greaterThan(0));
      bytes[at + 5] ^= 0xff;
      final file = File(p.join(tempRoot.path, 'rota.zip'));
      await file.writeAsBytes(bytes);
      // La base está bien: la copia se abre. Lo dañado es el original.
      final incoming = await IncomingVault.openFile(file);
      addTearDown(incoming.dispose);
      final out = Directory(p.join(tempRoot.path, 'documentos'))..createSync();

      await expectLater(
        incoming.copyOriginalTo('originales/plano.txt', out),
        throwsA(isA<FormatException>()),
      );

      // Ni un original dañado ni uno a medias en la carpeta de documentos: la
      // próxima fusión creería que ya está.
      expect(out.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });

  group('al terminar', () {
    test('dispose borra el temporal y suelta el .zip', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      await vault.saveSource('a', originalName: 'a.txt');
      final file = File(p.join(tempRoot.path, 'copia.zip'));
      await file.writeAsBytes(await vault.zip());

      final incoming = await withOwnTemp(() => IncomingVault.openFile(file));
      expect(leftovers(), hasLength(1));

      await incoming.dispose();

      expect(leftovers(), isEmpty);
      expectZipReleased(file);
    });
  });

  group('la memoria', () {
    test('un .zip de decenas de MB no pasa entero por ella', () async {
      // Una base de Sinapsis con unos 126 MB de contenido incompresible, que
      // ni el .zip ni la base extraída deberían pasar enteros por la memoria.
      //
      // El tamaño no es capricho: la memoria del proceso se mueve por su
      // cuenta varios MB —la recolección de basura— y una base chica se
      // perdía en ese ruido (una vez midió 24 MB con 63 de base). Con 126 MB,
      // lo que se busca detectar (la base y el .zip enteros en memoria: más de
      // 2 veces su peso) queda lejos del ruido y del umbral.
      //
      // Se mide la memoria privada comprometida y no la residente: en Windows
      // el sistema le recorta la residente al proceso cuando la máquina está
      // cargada, y las páginas que vuelven a entrar se contaban como
      // crecimiento —así midió una vez 51 MB contra un tope de 41—. Ver
      // `MemoryMeasure.privateCommit`.
      final dbFile = File(p.join(tempRoot.path, 'grande.sqlite'));
      final db = AppDatabase(NativeDatabase.createInBackground(dbFile));
      await db.customStatement(
        'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
      );
      await db.customStatement('''
        WITH RECURSIVE n(x) AS (
          SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 42000
        )
        INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
      await db.close();
      final dbBytes = dbFile.lengthSync();

      final zip = File(p.join(tempRoot.path, 'grande.zip'));
      await _zipDatabase(zip.path, dbFile.path);
      await dbFile.delete();

      final sampler = await RssSampler.start(
        measure: MemoryMeasure.privateCommit,
      );
      final incoming = await IncomingVault.openFile(zip);
      final growth = await sampler.stop();
      addTearDown(incoming.dispose);

      // La base salió entera al temporal...
      expect(incoming.databaseFile.lengthSync(), dbBytes);
      // ...y la memoria creció una fracción de lo que pesa: 12 MB de 164 con la
      // descompresión por tandas; 95 MB cuando se usaba `writeContent`, que
      // junta todo lo descomprimido en memoria antes de escribirlo. El umbral
      // —un cuarto— queda a tres veces del uno y a más de dos del otro.
      expect(
        growth,
        lessThan(dbBytes ~/ 4),
        reason:
            'creció ${growth ~/ 1048576} MB con una base de '
            '${dbBytes ~/ 1048576} MB',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
