import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_compaction_advisor.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';

/// Un disco con el espacio que cada prueba diga, que además anota dónde se le
/// preguntó.
class _FakeDisk implements FreeSpaceProbe {
  _FakeDisk(this.free);

  int? free;
  final asked = <String>[];

  @override
  Future<int?> freeBytesAt(String path) async {
    asked.add(path);
    return free;
  }
}

/// Corre contra SQLite y un archivo de verdad: lo que se mide son páginas, y
/// solo un archivo real las tiene como las tiene la app.
void main() {
  late Directory dir;
  late File file;
  late _FakeDisk disk;
  AppDatabase? db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sinapsis_compaction_');
    file = File(p.join(dir.path, 'sinapsis.sqlite'));
    disk = _FakeDisk(1 << 40);
  });

  tearDown(() async {
    await db?.close();
    db = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Una bóveda en archivo con [rows] filas de relleno —dos por página—, de las
  /// cuales se borran las que cumplan [deleteWhere]: las páginas que quedan
  /// sin ninguna fila son las que un borrado deja libres.
  Future<AppDatabase> vault({
    int rows = 0,
    String? deleteWhere,
    bool incremental = false,
  }) async {
    final opened = AppDatabase(
      NativeDatabase(
        file,
        // Tiene que ser antes de crear la primera tabla: después de eso, solo
        // un VACUUM lo cambia.
        setup: incremental
            ? (raw) => raw.execute('PRAGMA auto_vacuum = INCREMENTAL')
            : null,
      ),
    );
    db = opened;
    if (rows > 0) {
      await opened.customStatement(
        'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
      );
      final blob = Uint8List(2000);
      await opened.transaction(() async {
        for (var id = 1; id <= rows; id++) {
          await opened.customStatement(
            'INSERT INTO relleno (id, v) VALUES (?, ?)',
            [id, blob],
          );
        }
      });
      if (deleteWhere != null) {
        await opened.customStatement('DELETE FROM relleno WHERE $deleteWhere');
      }
    }
    return opened;
  }

  SqliteCompactionAdvisor advisorOn(AppDatabase database) =>
      SqliteCompactionAdvisor(database: database, freeSpace: disk);

  group('lo que mide de la base', () {
    test('las páginas del archivo y las libres que dejó un borrado', () async {
      final database = await vault(rows: 600, deleteWhere: 'id <= 400');

      final assessment = await advisorOn(database).assess();

      // El archivo es exactamente las páginas que dice tener.
      expect(assessment.fileBytes, file.lengthSync());
      expect(assessment.pageSize, 4096);
      // Borrar dos tercios de las filas dejó páginas libres, y lo recuperable
      // es exactamente esas páginas.
      expect(assessment.freePages, greaterThan(150));
      expect(
        assessment.reclaimableBytes,
        assessment.freePages * assessment.pageSize,
      );
      expect(
        assessment.usefulBytes + assessment.reclaimableBytes,
        assessment.fileBytes,
      );
      expect(assessment.autoVacuum, AutoVacuumMode.none);
      expect(assessment.needsFullRewrite, isTrue);
    });

    test('una base recién creada no tiene nada que recuperar, haya el disco '
        'que haya', () async {
      disk.free = 0;

      final assessment = await advisorOn(await vault()).assess();

      expect(assessment.freePages, 0);
      expect(assessment.reclaimableBytes, 0);
      expect(assessment.verdict, CompactionVerdict.nothingToReclaim);
    });

    test('reconoce una base en modo incremental', () async {
      final database = await vault(
        rows: 600,
        deleteWhere: 'id <= 400',
        incremental: true,
      );

      final assessment = await advisorOn(database).assess();

      expect(assessment.autoVacuum, AutoVacuumMode.incremental);
      expect(assessment.needsFullRewrite, isFalse);
      // En modo incremental se recupera de a tramos: no pide el doble.
      expect(
        assessment.requiredBytes,
        2 * kIncrementalStepPages * assessment.pageSize,
      );
    });

    test('mide de nuevo cada vez: después de reusar páginas, las libres son '
        'otras', () async {
      final database = await vault(rows: 600, deleteWhere: 'id <= 400');
      final advisor = advisorOn(database);
      final before = await advisor.assess();

      // Filas nuevas ocupan las páginas libres antes de agrandar el archivo.
      final blob = Uint8List(2000);
      for (var id = 1000; id < 1200; id++) {
        await database.customStatement(
          'INSERT INTO relleno (id, v) VALUES (?, ?)',
          [id, blob],
        );
      }
      final after = await advisor.assess();

      expect(after.freePages, lessThan(before.freePages));
    });
  });

  group('el espacio libre', () {
    test('se le pregunta al disco por la carpeta donde vive la base', () async {
      final database = await vault(rows: 200, deleteWhere: 'id <= 100');

      await advisorOn(database).assess();

      expect(disk.asked, [dir.path]);
    });

    test('una base en memoria no tiene disco que preguntar', () async {
      final memory = AppDatabase(NativeDatabase.memory());
      addTearDown(memory.close);

      final assessment = await advisorOn(memory).assess();

      expect(disk.asked, isEmpty);
      expect(assessment.freeSpaceBytes, isNull);
    });
  });

  group('el veredicto', () {
    late SqliteCompactionAdvisor advisor;

    setUp(() async {
      advisor = advisorOn(await vault(rows: 600, deleteWhere: 'id <= 400'));
    });

    /// La misma base con otro disco: lo único que cambia es cuánto hay libre.
    Future<CompactionAssessment> assessWith(int? free) {
      disk.free = free;
      return advisor.assess();
    }

    test('con lugar de sobra, listo para compactar', () async {
      final assessment = await assessWith(1 << 40);

      expect(assessment.verdict, CompactionVerdict.ready);
      expect(assessment.missingBytes, 0);
    });

    test('con justo lo que hace falta, todavía se puede', () async {
      final probe = await assessWith(1 << 40);

      final exact = await assessWith(probe.requiredBytes);

      expect(exact.verdict, CompactionVerdict.ready);
    });

    test('a un byte de lo que hace falta, no: y dice cuánto falta', () async {
      final probe = await assessWith(1 << 40);

      final short = await assessWith(probe.requiredBytes - 1);

      expect(short.verdict, CompactionVerdict.notEnoughSpace);
      expect(short.missingBytes, 1);
    });

    test('si el sistema no dice cuánto hay, se puede intentar', () async {
      final assessment = await assessWith(null);

      expect(assessment.verdict, CompactionVerdict.spaceUnknown);
      expect(assessment.missingBytes, 0);
    });
  });
}
