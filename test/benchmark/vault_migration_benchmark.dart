import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/pre_migration_backup_io.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_compaction_advisor.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_vault_compactor.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/rss_sampler.dart';

/// Dónde y cómo corre la migración a escala: de dónde sale la bóveda vieja,
/// adónde va lo que se imprime y qué techo se exige.
class MigrationBenchmarkEnvironment {
  const MigrationBenchmarkEnvironment({
    required this.oldVaultFile,
    required this.log,
    required this.save,
    required this.reportName,
    this.description = 'escritorio, sin describir',
    this.ceiling = const Duration(minutes: 10),
    this.freeSpace = const _UnknownFreeSpace(),
  });

  /// La base de la bóveda sintética de 10.000 elementos en un esquema anterior
  /// (el criterio de F12 la pide de esquema v17, unos 909 MB), o `null` si no
  /// está: la medición se salta diciendo por qué. El generador solo arma el
  /// esquema actual, así que esta se trae de afuera —en un teléfono, con
  /// `adb push`; ver `tool/bench_android.ps1`—.
  final Future<File?> Function() oldVaultFile;

  final void Function(String message) log;
  final void Function(String name, String content) save;
  final String description;

  /// El nombre del informe: cada bóveda de partida —v17 o v20, por ejemplo—
  /// deja el suyo, para que las dos cifras convivan.
  final String reportName;

  /// Cuánto puede tardar la migración entera, con el respaldo previo del
  /// archivo. Es un techo contra una regresión de órdenes de magnitud, no la
  /// meta.
  final Duration ceiling;

  /// Cómo se sabe cuánto disco queda para el consejero de compactación. En un
  /// dispositivo, `DiskSpacePlusFreeSpaceProbe`; por defecto, «no se sabe» —lo
  /// que ese complemento contesta en escritorio, donde no existe—, porque una
  /// prueba de `flutter test` no tiene complementos que consultar.
  final FreeSpaceProbe freeSpace;
}

/// El disco libre que no se sabe: es lo que el complemento de espacio libre
/// dice en escritorio.
class _UnknownFreeSpace implements FreeSpaceProbe {
  const _UnknownFreeSpace();

  @override
  Future<int?> freeBytesAt(String path) async => null;
}

/// La migración de una bóveda de 10.000 elementos y ~300.000 chunks, de una
/// vez, hasta el esquema de esta versión: lo que le pasa a quien actualiza la
/// app con la bóveda llena.
///
/// Lo que se mide es la apertura de la base, que es donde migra —con el
/// respaldo previo del archivo entero (`VACUUM INTO`), que en un teléfono es
/// escribir cientos de megas en flash—, y lo que se comprueba es que no se
/// perdió nada: los conteos de las tablas iguales antes y después, las tablas
/// nuevas vacías, ninguna clave rota y el invariante de los chunks sobre la
/// bóveda entera.
void registerVaultMigrationBenchmark(MigrationBenchmarkEnvironment env) {
  test(
    'migrar la bóveda vieja al esquema actual, con el respaldo previo',
    () async {
      final source = await env.oldVaultFile();
      if (source == null) {
        env.log('Se salta: no hay una bóveda de un esquema anterior.');
        markTestSkipped('falta la bóveda de un esquema anterior');
        return;
      }

      final report = StringBuffer('# Migración a escala\n\n')
        ..writeln('Equipo: ${env.description}')
        ..writeln();
      void say(String line) {
        env.log(line);
        report.writeln(line);
      }

      final work = await Directory.systemTemp.createTemp('sinapsis_migration_');
      addTearDown(() async {
        try {
          await work.delete(recursive: true);
          // En Windows un archivo recién cerrado puede tardar en soltarse.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
      });

      final copy = File(p.join(work.path, 'vault.sqlite'));
      final copyWatch = Stopwatch()..start();
      await source.copy(copy.path);
      say(
        '- la bóveda de partida: ${source.lengthSync() ~/ (1024 * 1024)} MB, '
        'copiada en ${copyWatch.elapsedMilliseconds} ms',
      );

      // Los conteos de antes, con SQLite crudo: la base todavía es la vieja y
      // abrirla con drift la migraría.
      final raw = sqlite3.sqlite3.open(
        copy.path,
        mode: sqlite3.OpenMode.readOnly,
      );
      final fromVersion = raw.select('PRAGMA user_version').first.values.first;
      final existing = {
        for (final row in raw.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name'] as String,
      };
      final tables = [
        for (final table in [
          ...VaultCounts.userDataTables,
          ...VaultCounts.modelTables,
        ])
          if (existing.contains(table)) table,
      ];
      final before = {
        for (final table in tables)
          table:
              raw.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int,
      };
      raw.close();
      say(
        '- esquema de partida v$fromVersion; ${before['item']} elementos, '
        '${before['chunks']} chunks, ${before['renditions']} formas',
      );

      final watch = Stopwatch()..start();
      final db = AppDatabase(
        NativeDatabase(
          copy,
          setup: (rawDb) => backupBeforeMigration(
            rawDb,
            targetVersion: AppDatabase.currentSchemaVersion,
          ),
        ),
        deviceId: 'bench',
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final migrateMs = watch.elapsedMilliseconds;
      final backups = [
        for (final file in work.listSync().whereType<File>())
          if (file.path.endsWith('.bak'))
            '${file.lengthSync() ~/ (1024 * 1024)} MB',
      ];
      const target = AppDatabase.currentSchemaVersion;
      say(
        '- **migración de v$fromVersion a v$target, con el respaldo previo: '
        '$migrateMs ms** (respaldo: ${backups.join(', ')})',
      );

      final after = <String, int>{};
      for (final table in before.keys) {
        after[table] =
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
      }
      expect(after, before, reason: 'ninguna tabla cambió de tamaño');
      for (final table in VaultCounts.durabilityTables) {
        final n =
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
        expect(n, 0, reason: '$table nace vacía');
      }
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      say(
        '- los ${before.length} conteos, iguales; tablas nuevas vacías; '
        'sin claves rotas',
      );

      final invariantWatch = Stopwatch()..start();
      final invariant = await verifyChunkInvariant(db);
      say(
        '- `verifyChunkInvariant`, entera: ${invariant.summary()} '
        '(${invariantWatch.elapsedMilliseconds} ms)',
      );
      expect(invariant.holds, isTrue, reason: invariant.summary());

      // Después de migrar, la bóveda pesa lo mismo que antes pero con las
      // páginas de lo que la migración reemplazó libres: es lo que la
      // compactación guiada le ofrece devolver (F12). Se mide sobre esta misma
      // base, ya migrada: es el caso real.
      String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
      final advisor = SqliteCompactionAdvisor(
        database: db,
        freeSpace: env.freeSpace,
      );
      final assessment = await advisor.assess();
      final freeSpace = assessment.freeSpaceBytes;
      final free = freeSpace == null ? 'sin dato' : mb(freeSpace);
      say(
        '- después de migrar: el archivo ocupa ${mb(assessment.fileBytes)} y '
        '${mb(assessment.reclaimableBytes)} se pueden recuperar; espacio libre '
        '$free, '
        'la compactación necesita ${mb(assessment.requiredBytes)} '
        '(${assessment.verdict.name})',
      );
      if (assessment.verdict == CompactionVerdict.notEnoughSpace ||
          assessment.verdict == CompactionVerdict.nothingToReclaim) {
        say('- no se compacta: ${assessment.verdict.name}');
      } else {
        final sampler = await RssSampler.start();
        final compactWatch = Stopwatch()..start();
        final phaseStarts = <CompactionPhase, int>{};
        final result =
            await SqliteVaultCompactor(database: db, advisor: advisor).compact(
              onProgress: (progress) => phaseStarts.putIfAbsent(
                progress.phase,
                () => compactWatch.elapsedMilliseconds,
              ),
            );
        final growth = await sampler.stop();
        final total = compactWatch.elapsedMilliseconds;
        final rewriteMs =
            (phaseStarts[CompactionPhase.verifying] ?? total) -
            (phaseStarts[CompactionPhase.rewriting] ?? 0);
        final verifyMs =
            total - (phaseStarts[CompactionPhase.verifying] ?? total);
        say(
          '- **compactación (VACUUM con `temp_store = FILE`, y comprobación): '
          '$total ms** —reescribir $rewriteMs ms, comprobar $verifyMs ms—; '
          'el archivo pasó de ${mb(result.bytesBefore)} a '
          '${mb(result.bytesAfter)} '
          '(devolvió ${mb(result.freedBytes)}); ${result.sourcesVerified} '
          'fuentes comprobadas; memoria residente +${mb(growth)} con '
          '${mb(assessment.usefulBytes)} de contenido útil',
        );
        expect(result.freedBytes, greaterThan(0));
        expect(result.sourcesVerified, greaterThan(0));
        // Sin `temp_store = FILE`, VACUUM juntaría en memoria todo lo útil.
        expect(
          growth,
          lessThan(assessment.usefulBytes ~/ 2),
          reason: 'la compactación no debe cargar la bóveda en memoria',
        );
      }

      say(
        '- memoria residente máxima del proceso: '
        '${ProcessInfo.maxRss ~/ (1024 * 1024)} MB',
      );

      env.save(env.reportName, report.toString());
      expect(migrateMs, lessThan(env.ceiling.inMilliseconds));
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
