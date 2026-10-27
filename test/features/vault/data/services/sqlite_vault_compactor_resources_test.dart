import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_compaction_advisor.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_vault_compactor.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

class _PlentyOfDisk implements FreeSpaceProbe {
  @override
  Future<int?> freeBytesAt(String path) async => 1 << 40;
}

/// Lo que cuesta compactar y DÓNDE vive la copia de trabajo, medido con una
/// base de decenas de MB para que la diferencia no se pierda en el ruido.
///
/// La base corre en un aislado aparte —como la de la app—: así este aislado
/// puede mirar la carpeta de temporales y el diario MIENTRAS SQLite trabaja. Es
/// lo que sostiene la regla de `CompactionAssessment` (`requiredBytes`) y el
/// `PRAGMA temp_store = FILE` de la compactación: ver la decisión 45 de
/// docs/arquitectura.md.
///
/// Lo que se afirma no depende de la carga de la máquina: es dónde está la
/// copia de trabajo —un archivo temporal del tamaño de lo útil, o ninguno—, que
/// decide SQLite según `temp_store`. La memoria del proceso (`ProcessInfo`) NO
/// se afirma: es de todo el proceso, la mueven el recolector, el sistema al
/// recortar el conjunto de trabajo y cualquier otra cosa que corra a la vez, y
/// con la máquina cargada daba falsos rojos. Se deja en el mensaje de falla
/// como dato, no como condición.
/// Armar y compactar decenas de MB lleva segundos; con la máquina ocupada, más.
/// El tope por defecto de 30 s es contra un cuelgue, no contra la carga.
const _heavy = Timeout(Duration(minutes: 3));

void main() {
  const mib = 1024 * 1024;
  late Directory dir;
  late String? tempDirectoryBefore;

  /// 30.000 filas de 3.000 bytes incompresibles —una por página— de las cuales
  /// se borra la mitad: unos 120 MB de archivo, 60 de contenido útil.
  Future<({AppDatabase db, File file, int useful})> build() async {
    final file = File(p.join(dir.path, 'sinapsis.sqlite'));
    final db = AppDatabase(NativeDatabase.createInBackground(file));
    await db.customStatement(
      'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
    );
    await db.customStatement('''
      WITH RECURSIVE n(x) AS (
        SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 30000
      )
      INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
    await db.customStatement('DELETE FROM relleno WHERE id % 2 = 0');
    final assessment = await SqliteCompactionAdvisor(
      database: db,
      freeSpace: _PlentyOfDisk(),
    ).assess();
    return (db: db, file: file, useful: assessment.usefulBytes);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sinapsis_compactor_res_');
    // Los temporales de SQLite van a una carpeta de esta prueba: así se ve solo
    // lo que su base escribe, y no lo de otras pruebas que corran a la vez.
    tempDirectoryBefore = sqlite3.tempDirectory;
    Directory(p.join(dir.path, 'temporales')).createSync();
    sqlite3.tempDirectory = p.join(dir.path, 'temporales');
  });

  tearDown(() async {
    sqlite3.tempDirectory = tempDirectoryBefore;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  /// Lo más que llegó a pesar, mientras corre [work], cada cosa que SQLite
  /// escribe aparte del archivo: los temporales (donde vive la copia de trabajo
  /// de `VACUUM` si va a disco), el diario de reversión y lo que crezca el
  /// archivo; más el pico de memoria del proceso, solo como dato para el
  /// mensaje de falla.
  Future<({int tempPeak, int journalPeak, int diskPeak, int rssGrowth})>
  measure(File file, Future<void> Function() work) async {
    final rssBefore = ProcessInfo.currentRss;
    final sizeBefore = file.lengthSync();
    var rssPeak = rssBefore;
    var tempPeak = 0;
    var journalPeak = 0;
    var diskPeak = 0;

    int lengthOf(String path) {
      try {
        return File(path).lengthSync();
      } on FileSystemException {
        // El archivo se borró o SQLite lo tiene abierto sin compartirlo.
        return 0;
      }
    }

    final sampler = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > rssPeak) rssPeak = rss;
      final temporales = Directory(p.join(dir.path, 'temporales'))
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + lengthOf(f.path));
      final journal = lengthOf('${file.path}-journal');
      final growth = lengthOf(file.path) - sizeBefore;
      final extra = (growth > 0 ? growth : 0) + journal + temporales;
      if (temporales > tempPeak) tempPeak = temporales;
      if (journal > journalPeak) journalPeak = journal;
      if (extra > diskPeak) diskPeak = extra;
    });
    try {
      await work();
    } finally {
      sampler.cancel();
    }
    return (
      tempPeak: tempPeak,
      journalPeak: journalPeak,
      diskPeak: diskPeak,
      rssGrowth: rssPeak - rssBefore,
    );
  }

  test('compactar lleva la copia de trabajo al disco y no a la memoria, y el '
      'disco que pide entra en lo que el consejero exige', () async {
    final vault = await build();
    addTearDown(vault.db.close);
    final assessment = await SqliteCompactionAdvisor(
      database: vault.db,
      freeSpace: _PlentyOfDisk(),
    ).assess();
    final compactor = SqliteVaultCompactor(
      database: vault.db,
      advisor: SqliteCompactionAdvisor(
        database: vault.db,
        freeSpace: _PlentyOfDisk(),
      ),
    );

    final cost = await measure(vault.file, compactor.compact);

    final detail =
        'útil ${vault.useful ~/ mib} MB; temporales ${cost.tempPeak ~/ mib} '
        'MB, diario ${cost.journalPeak ~/ mib} MB, '
        'disco ${cost.diskPeak ~/ mib} MB; '
        'memoria del proceso +${cost.rssGrowth ~/ mib} MB (dato)';

    // Dónde vive la copia de trabajo: sin `temp_store = FILE` es de memoria y
    // no hay ningún temporal (ver el control de abajo). Con él, es un archivo
    // temporal que llega a lo útil: la copia de todo lo que la bóveda tiene de
    // verdad, en disco y no en RAM.
    expect(cost.tempPeak, greaterThan(vault.useful ~/ 2), reason: detail);
    // El disco: además del temporal, el diario —del tamaño de lo útil—; y no
    // más de lo que el consejero le exige a quien compacta.
    expect(cost.diskPeak, greaterThan(vault.useful ~/ 2), reason: detail);
    expect(
      cost.diskPeak,
      lessThanOrEqualTo(assessment.requiredBytes),
      reason: detail,
    );
  }, timeout: _heavy);

  test('CONTROL: un VACUUM sin `temp_store = FILE` sí carga en memoria lo útil '
      '(por eso la compactación lo pone)', () async {
    // Si esto deja de cumplirse —una versión de SQLite compilada con los
    // temporales en archivo—, el `PRAGMA temp_store = FILE` de la compactación
    // deja de hacer falta y esta prueba avisa.
    final vault = await build();
    addTearDown(vault.db.close);

    final cost = await measure(
      vault.file,
      () => vault.db.customStatement('VACUUM'),
    );

    // La copia de trabajo no tiene dónde caer en disco: ningún temporal que se
    // acerque a lo útil. Si apareciera uno, SQLite ya la manda a archivo sola.
    expect(
      cost.tempPeak,
      lessThan(vault.useful ~/ 10),
      reason:
          'apareció un temporal de ${cost.tempPeak ~/ mib} MB con '
          '${vault.useful ~/ mib} MB de contenido útil',
    );
    // Y sigue habiendo diario: lo único que trabajó en disco fue la reversión.
    expect(cost.journalPeak, greaterThan(vault.useful ~/ 2));
  }, timeout: _heavy);
}
