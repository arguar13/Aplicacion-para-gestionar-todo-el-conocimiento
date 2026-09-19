import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/pre_migration_backup.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart' as sql;

/// Una base drift sin tablas propias: lo único que hace es migrar de 12 a
/// 13 insertando una fila marcadora. Sirve para comprobar el ORDEN —que el
/// respaldo se toma antes de que la migración toque nada— sin depender de
/// qué haga hoy la migración real de `AppDatabase`, que cambiará.
class _ProbeDatabase extends GeneratedDatabase {
  _ProbeDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      await customStatement("INSERT INTO notas VALUES ('migrada')");
    },
  );
}

/// De nivel superior, como la del código real: drift la envía al isolate que
/// hospeda la base, y solo viajan funciones que no capturan estado.
void _setupForTest(CommonDatabase db) {
  backupBeforeMigration(db, targetVersion: 13);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sinapsis_backup_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  /// Deja en disco una base con la tabla `notas` y esas filas, a [version].
  String createDatabase(
    String name, {
    required int version,
    List<String> rows = const [],
  }) {
    final path = p.join(tmp.path, name);
    final db = sql.sqlite3.open(path)
      ..execute('CREATE TABLE notas (texto TEXT NOT NULL)');
    for (final row in rows) {
      db.execute('INSERT INTO notas VALUES (?)', [row]);
    }
    db
      ..userVersion = version
      ..close();
    return path;
  }

  /// Corre [body] con la base de [path] abierta y la cierra después.
  T withDatabase<T>(String path, T Function(sql.Database db) body) {
    final db = sql.sqlite3.open(path);
    try {
      return body(db);
    } finally {
      db.close();
    }
  }

  List<String> notasEn(String path) => withDatabase(
    path,
    (db) => db
        .select('SELECT texto FROM notas ORDER BY rowid')
        .map((row) => row['texto'] as String)
        .toList(),
  );

  int versionDe(String path) => withDatabase(path, (db) => db.userVersion);

  List<String> respaldosEn() =>
      tmp
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.endsWith('.bak'))
          .toList()
        ..sort();

  test('una base de una versión anterior se respalda entera antes de '
      'migrar', () {
    final path = createDatabase(
      'sinapsis.sqlite',
      version: 12,
      rows: ['uno', 'dos', 'tres'],
    );

    final backup = withDatabase(
      path,
      (db) => backupBeforeMigration(db, targetVersion: 13),
    );

    expect(backup, '$path.pre-v12.bak');
    expect(File(backup!).existsSync(), isTrue);
    // La copia es una base SQLite de verdad, con todo y con su versión.
    expect(notasEn(backup), ['uno', 'dos', 'tres']);
    expect(versionDe(backup), 12);
    // Y el original no se tocó.
    expect(notasEn(path), ['uno', 'dos', 'tres']);
    expect(versionDe(path), 12);
  });

  test('la copia incluye lo que todavía está en el -wal sin consolidar', () {
    final path = p.join(tmp.path, 'sinapsis.sqlite');
    // Como la deja drift: en modo WAL, donde lo último escrito puede vivir
    // solo en el `-wal`. Copiar el archivo a mano lo perdería.
    final db = sql.sqlite3.open(path)
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('CREATE TABLE notas (texto TEXT NOT NULL)')
      ..execute("INSERT INTO notas VALUES ('en el wal')")
      ..userVersion = 12;

    // La premisa: copiar el archivo principal a mano NO se lleva lo que
    // sigue en el `-wal` —ni siquiera la tabla—, así que el test de abajo
    // distingue de verdad un `VACUUM INTO` de una copia de archivo.
    final rawCopy = p.join(tmp.path, 'copia_a_mano.sqlite');
    File(path).copySync(rawCopy);
    expect(() => notasEn(rawCopy), throwsA(isA<sql.SqliteException>()));

    final backup = backupBeforeMigration(db, targetVersion: 13);
    db.close();

    expect(notasEn(backup!), ['en el wal']);
  });

  test('una base recién creada no se respalda', () {
    final path = createDatabase('sinapsis.sqlite', version: 0);

    final backup = withDatabase(
      path,
      (db) => backupBeforeMigration(db, targetVersion: 13),
    );

    expect(backup, isNull);
    expect(respaldosEn(), isEmpty);
  });

  test('una base que ya está al día no se respalda', () {
    final path = createDatabase('sinapsis.sqlite', version: 13);

    final backup = withDatabase(
      path,
      (db) => backupBeforeMigration(db, targetVersion: 13),
    );

    expect(backup, isNull);
    expect(respaldosEn(), isEmpty);
  });

  test('una base en memoria no se respalda: no hay archivo que copiar', () {
    final db = sql.sqlite3.openInMemory()..userVersion = 5;

    final backup = backupBeforeMigration(db, targetVersion: 13);
    db.close();

    expect(backup, isNull);
    expect(respaldosEn(), isEmpty);
  });

  test('un respaldo anterior del mismo salto se reemplaza por el nuevo', () {
    final path = createDatabase(
      'sinapsis.sqlite',
      version: 12,
      rows: ['vigente'],
    );
    // Resto de un intento anterior: `VACUUM INTO` se negaría a escribir
    // encima de un archivo que ya existe.
    File('$path.pre-v12.bak').writeAsStringSync('basura de un intento viejo');

    final backup = withDatabase(
      path,
      (db) => backupBeforeMigration(db, targetVersion: 13),
    );

    expect(notasEn(backup!), ['vigente']);
  });

  test('conserva solo los últimos respaldos y no toca los de otra base', () {
    final path = createDatabase('sinapsis.sqlite', version: 12, rows: ['x']);
    // Cuatro respaldos de migraciones anteriores, con fechas escalonadas.
    for (final (index, version) in [8, 9, 10, 11].indexed) {
      File('$path.pre-v$version.bak')
        ..writeAsStringSync('viejo')
        ..setLastModifiedSync(DateTime(2026, 1, 1 + index));
    }
    // De otra base: no es asunto de este respaldo.
    File(p.join(tmp.path, 'otra.sqlite.pre-v3.bak')).writeAsStringSync('ajeno');

    // Con el `keep` por defecto: 4 viejos + el nuevo = 5, quedan 3.
    withDatabase(path, (db) => backupBeforeMigration(db, targetVersion: 13));

    expect(respaldosEn(), [
      'otra.sqlite.pre-v3.bak',
      'sinapsis.sqlite.pre-v10.bak',
      'sinapsis.sqlite.pre-v11.bak',
      'sinapsis.sqlite.pre-v12.bak',
    ]);
  });

  test('una ruta con comilla simple no rompe el respaldo', () {
    final path = createDatabase(
      "la bóveda d'Ana.sqlite",
      version: 12,
      rows: ['a'],
    );

    final backup = withDatabase(
      path,
      (db) => backupBeforeMigration(db, targetVersion: 13),
    );

    expect(notasEn(backup!), ['a']);
  });

  test('si no puede respaldar, lanza y deja la base como estaba', () {
    final path = createDatabase(
      'sinapsis.sqlite',
      version: 12,
      rows: ['intacta'],
    );
    // Un directorio donde iría el respaldo: `VACUUM INTO` no puede crear
    // el archivo. Es un fallo determinista en cualquier plataforma.
    Directory('$path.pre-v12.bak').createSync();

    expect(
      () => withDatabase(
        path,
        (db) => backupBeforeMigration(db, targetVersion: 13),
      ),
      throwsA(isA<PreMigrationBackupException>()),
    );

    expect(notasEn(path), ['intacta']);
    expect(versionDe(path), 12);
  });

  group('con drift de por medio', () {
    test('el respaldo se toma ANTES de que corra la migración', () async {
      final path = createDatabase(
        'sinapsis.sqlite',
        version: 12,
        rows: ['a', 'b'],
      );

      final db = _ProbeDatabase(
        NativeDatabase(
          File(path),
          setup: (db) => backupBeforeMigration(db, targetVersion: 13),
        ),
      );
      // Forzar la apertura: recién ahí drift corre `setup` y migra.
      await db.customSelect('SELECT 1').get();
      await db.close();

      // La base migró...
      expect(notasEn(path), ['a', 'b', 'migrada']);
      expect(versionDe(path), 13);
      // ...y el respaldo quedó en el estado de ANTES.
      expect(notasEn('$path.pre-v12.bak'), ['a', 'b']);
      expect(versionDe('$path.pre-v12.bak'), 12);
    });

    test('si el respaldo falla, la migración no corre', () async {
      final path = createDatabase(
        'sinapsis.sqlite',
        version: 12,
        rows: ['a', 'b'],
      );
      Directory('$path.pre-v12.bak').createSync();

      final db = _ProbeDatabase(
        NativeDatabase(
          File(path),
          setup: (db) => backupBeforeMigration(db, targetVersion: 13),
        ),
      );

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<PreMigrationBackupException>()),
      );
      await db.close();

      expect(notasEn(path), ['a', 'b']);
      expect(versionDe(path), 12);
    });

    test('la función de setup viaja bien al isolate de la base', () async {
      final path = createDatabase('sinapsis.sqlite', version: 12, rows: ['a']);

      // Como en producción: `driftDatabase` con `native.setup`, que abre
      // la base en un isolate de fondo y le envía la función.
      final db = _ProbeDatabase(
        driftDatabase(
          name: 'sinapsis_backup_test',
          native: DriftNativeOptions(
            databasePath: () async => path,
            tempDirectoryPath: () async => tmp.path,
            setup: _setupForTest,
          ),
        ),
      );
      await db.customSelect('SELECT 1').get();
      await db.close();

      expect(notasEn(path), ['a', 'migrada']);
      expect(notasEn('$path.pre-v12.bak'), ['a']);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
