import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../../support/test_vault.dart';

/// La copia de otra bóveda, abierta para leerla (F11): se desempaqueta, se
/// pone al día si es de una versión vieja, se rechaza con un motivo si no se
/// puede, y no deja nada atrás.
void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('sinapsis_incoming_test_');
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

  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('una copia del esquema actual', () {
    test('se abre tal cual y trae sus datos', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      await vault.saveSource('a', text: 'Texto de a.');

      final incoming = await IncomingVault.open(await vault.zip());
      addTearDown(incoming.dispose);

      expect(incoming.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(incoming.databaseFile.existsSync(), isTrue);

      final db = sqlite3.sqlite3.open(
        incoming.databaseFile.path,
        mode: sqlite3.OpenMode.readOnly,
      );
      addTearDown(db.close);
      expect(db.select('SELECT id FROM item').single['id'], 'a');
      expect(
        db.select('SELECT content FROM renditions').single['content'],
        'Texto de a.',
      );
    });

    test('la conexión de esta bóveda la ve adjuntada, y la suelta', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      final other = await TestVault.create(deviceId: 'pc');
      addTearDown(other.dispose);
      await other.saveSource('b');

      final incoming = await IncomingVault.open(await other.zip());
      addTearDown(incoming.dispose);

      await incoming.attachTo(vault.db);
      final seen = await vault.db
          .customSelect('SELECT id FROM $kIncomingSchema.item')
          .get();
      expect(seen.map((r) => r.read<String>('id')), ['b']);
      // Esta bóveda sigue sin tener nada propio.
      expect(await vault.count('item'), 0);

      await incoming.detachFrom(vault.db);
      final attached = await vault.db
          .customSelect('PRAGMA database_list')
          .get();
      expect(attached.map((r) => r.read<String>('name')), ['main']);
    });
  });

  group('una copia de una versión vieja', () {
    test('se actualiza LA COPIA, con sus datos intactos', () async {
      final incoming = await IncomingVault.open(
        await vaultCopyAtV19(text: 'Texto viejo.'),
      );
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
      // Las tablas de la 20 existen, vacías: la copia ya tiene la forma de
      // esta versión y se puede leer junto a la de esta bóveda.
      expect(
        db.select('SELECT COUNT(*) AS n FROM field_version').single['n'],
        0,
      );
      expect(db.select('SELECT COUNT(*) AS n FROM review_log').single['n'], 0);
      // Y lo que había, exacto.
      expect(
        db.select('SELECT title FROM item').single['title'],
        'Fuente vieja',
      );
      expect(
        db.select('SELECT content FROM renditions').single['content'],
        'Texto viejo.',
      );
    });

    test('esta bóveda no se toca al leer una copia vieja', () async {
      final vault = await TestVault.create(deviceId: 'tel');
      addTearDown(vault.dispose);
      await vault.saveSource('a');
      final before = await vault.counts();

      final incoming = await IncomingVault.open(await vaultCopyAtV19());
      addTearDown(incoming.dispose);
      await incoming.attachTo(vault.db);
      await incoming.detachFrom(vault.db);

      expect(await vault.counts(), before);
    });
  });

  group('lo que se rechaza, con su motivo', () {
    test('un esquema más nuevo que el de esta versión', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(99),
      });

      await expectLater(
        IncomingVault.open(zip),
        throwsA(
          isA<VaultBackupTooNewException>()
              .having((e) => e.backupVersion, 'backupVersion', 99)
              .having(
                (e) => e.currentVersion,
                'currentVersion',
                AppDatabase.currentSchemaVersion,
              ),
        ),
      );
    });

    test('un esquema demasiado viejo para actualizarlo', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(14),
      });

      await expectLater(
        IncomingVault.open(zip),
        throwsA(
          isA<SchemaTooOldException>()
              .having((e) => e.from, 'from', 14)
              .having(
                (e) => e.minimum,
                'minimum',
                AppDatabase.minimumUpgradableSchemaVersion,
              ),
        ),
      );
    });

    test('lo que no es un zip', () async {
      await expectLater(
        IncomingVault.open(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });

    test('un zip sin la base de Sinapsis', () async {
      final zip = zipOf({'otra-cosa.txt': utf8Bytes('hola')});

      await expectLater(
        IncomingVault.open(zip),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });

    test('una base que no es de SQLite', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: utf8Bytes(
          'esto no es una base de datos' * 20,
        ),
      });

      await expectLater(
        IncomingVault.open(zip),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });

    test('una base de SQLite sin versión de esquema', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(0),
      });

      await expectLater(
        IncomingVault.open(zip),
        throwsA(isA<InvalidVaultBackupException>()),
      );
    });

    test('no deja el temporal si la rechaza', () async {
      await withOwnTemp(() async {
        for (final zip in [
          zipOf({kBackupDatabaseEntryName: await sqliteBytesAtVersion(99)}),
          zipOf({kBackupDatabaseEntryName: await sqliteBytesAtVersion(14)}),
          zipOf({kBackupDatabaseEntryName: await sqliteBytesAtVersion(0)}),
          zipOf({kBackupDatabaseEntryName: utf8Bytes('basura' * 50)}),
        ]) {
          await expectLater(IncomingVault.open(zip), throwsA(isA<Object>()));
        }
      });

      expect(leftovers(), isEmpty);
    });
  });

  group('el temporal', () {
    test('vive mientras se usa y se va con dispose', () async {
      final vault = await TestVault.create(deviceId: 'pc');
      addTearDown(vault.dispose);
      await vault.saveSource('a');

      final incoming = await withOwnTemp(
        () async => IncomingVault.open(await vault.zip()),
      );

      expect(leftovers(), hasLength(1));
      expect(incoming.directory.existsSync(), isTrue);

      await incoming.dispose();

      expect(leftovers(), isEmpty);
      expect(incoming.directory.existsSync(), isFalse);
    });

    test('dispose dos veces no falla', () async {
      final vault = await TestVault.create(deviceId: 'pc');
      addTearDown(vault.dispose);
      final incoming = await IncomingVault.open(await vault.zip());

      await incoming.dispose();
      await incoming.dispose();
    });
  });

  group('los archivos originales de la copia', () {
    late IncomingVault incoming;

    setUp(() async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(
          AppDatabase.currentSchemaVersion,
        ),
        'originales/a/informe.pdf': utf8Bytes('pdf de a'),
        'originales/b/audio.mp3': utf8Bytes('audio de b, más largo'),
      });
      incoming = await IncomingVault.open(zip);
    });

    tearDown(() => incoming.dispose());

    test('se listan, sin la base', () {
      expect(incoming.originalPaths.toSet(), {
        'originales/a/informe.pdf',
        'originales/b/audio.mp3',
      });
    });

    test('se sabe cuánto pesa cada uno sin descomprimirlo', () {
      expect(incoming.sizeOfOriginal('originales/a/informe.pdf'), 8);
      expect(
        incoming.sizeOfOriginal('originales/b/audio.mp3'),
        utf8.encode('audio de b, más largo').length,
      );
      expect(incoming.sizeOfOriginal('originales/c/no-esta.txt'), isNull);
    });

    test('se copian a la carpeta de documentos, en su misma ruta', () async {
      final root = await Directory.systemTemp.createTemp('sinapsis_docs_');
      addTearDown(() => root.delete(recursive: true));

      final out = await incoming.copyOriginalTo(
        'originales/a/informe.pdf',
        root,
      );

      expect(out, isNotNull);
      expect(p.isWithin(root.path, out!.path), isTrue);
      expect(out.readAsStringSync(), 'pdf de a');
      expect(
        File(p.join(root.path, 'originales', 'a', 'informe.pdf')).existsSync(),
        isTrue,
      );
    });

    test('uno que la copia no trae no se copia', () async {
      final root = await Directory.systemTemp.createTemp('sinapsis_docs_');
      addTearDown(() => root.delete(recursive: true));

      expect(
        await incoming.copyOriginalTo('originales/z/nada.txt', root),
        isNull,
      );
      expect(root.listSync(), isEmpty);
    });
  });

  group('una copia que trae rutas que salen de la bóveda', () {
    test('se ignoran: no se listan ni se copian', () async {
      final zip = zipOf({
        kBackupDatabaseEntryName: await sqliteBytesAtVersion(
          AppDatabase.currentSchemaVersion,
        ),
        'originales/a/bien.txt': utf8Bytes('bien'),
        'originales/../../fuera.txt': utf8Bytes('mal'),
        'originales/a/../../fuera2.txt': utf8Bytes('mal'),
        r'originales\a\barra-invertida.txt': utf8Bytes('mal'),
        r'originales/a\..\..\fuera3.txt': utf8Bytes('mal'),
        'originales/C:/unidad.txt': utf8Bytes('mal'),
        '/originales/absoluta.txt': utf8Bytes('mal'),
        'fuera-de-originales/otra.txt': utf8Bytes('mal'),
      });
      final incoming = await IncomingVault.open(zip);
      addTearDown(incoming.dispose);
      final root = await Directory.systemTemp.createTemp('sinapsis_docs_');
      addTearDown(() => root.delete(recursive: true));

      expect(incoming.originalPaths.toList(), ['originales/a/bien.txt']);

      for (final name in [
        'originales/../../fuera.txt',
        'originales/a/../../fuera2.txt',
        r'originales/a\..\..\fuera3.txt',
        'originales/C:/unidad.txt',
        '/originales/absoluta.txt',
      ]) {
        expect(await incoming.copyOriginalTo(name, root), isNull, reason: name);
        expect(incoming.sizeOfOriginal(name), isNull, reason: name);
      }
      expect(root.listSync(recursive: true), isEmpty);
    });

    test('isSafeOriginalPath dice qué rutas sirven', () {
      for (final ok in [
        'originales/a/b.pdf',
        'originales/3f2a-11/mi informe (1).pdf',
        'originales/x/ñandú.txt',
      ]) {
        expect(IncomingVault.isSafeOriginalPath(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        'originales',
        'originales/',
        'originales//a.txt',
        'originales/./a.txt',
        'originales/../a.txt',
        'originales/a/..',
        'otra/a.txt',
        r'originales/a\b.txt',
        'originales/a:b.txt',
        'originales/a\u0000b.txt',
      ]) {
        expect(IncomingVault.isSafeOriginalPath(bad), isFalse, reason: bad);
      }
    });
  });
}
