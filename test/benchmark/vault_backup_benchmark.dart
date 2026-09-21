import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/rss_sampler.dart';
import 'synthetic_vault.dart';

/// Dónde y cómo corre la medición de la copia de la bóveda: de dónde sale la
/// bóveda de 10.000 elementos, adónde va lo que se imprime y qué techos se
/// exigen.
class BackupBenchmarkEnvironment {
  const BackupBenchmarkEnvironment({
    required this.openVault,
    required this.log,
    required this.save,
    this.description = 'escritorio, sin describir',
    this.timeCeiling = const Duration(minutes: 30),
    this.gateway,
  });

  /// Abre —o arma, la primera vez— la bóveda sintética de 10.000 elementos.
  final Future<({AppDatabase db, SyntheticVault vault})> Function() openVault;

  final void Function(String message) log;
  final void Function(String name, String content) save;
  final String description;

  /// Cuánto puede tardar cada paso: un techo contra una regresión de órdenes de
  /// magnitud, no la meta.
  final Duration timeCeiling;

  /// Si no es `null`, la copia armada se guarda además donde el usuario elija
  /// con el selector del sistema —como hace la app—, se vuelve a elegir con el
  /// selector de archivos y se abre desde lo elegido, midiendo cuánto tarda y
  /// cuánta memoria usa cada paso. Los selectores NO se cierran solos: hace
  /// falta alguien que los maneje (`tool/bench_android_pick_folder.ps1`), y por
  /// eso solo se pasa cuando se pide.
  final VaultBackupFileGateway? gateway;
}

/// La copia de la bóveda entera, armada y vuelta a abrir (F12).
///
/// Lo que se mide es lo que importa en un teléfono: cuánta MEMORIA usa armar la
/// copia y abrirla —no debe crecer con lo que pesa la bóveda: todo pasa por
/// tandas—, cuánto tarda, y cuánto pesa el `.zip` respecto de la base. Y que lo
/// que sale es la misma bóveda: la copia se abre, trae los 10.000 elementos y
/// los originales salen idénticos.
void registerVaultBackupBenchmark(BackupBenchmarkEnvironment env) {
  test(
    'armar la copia de la bóveda de 10.000 elementos y volver a abrirla',
    () async {
      final report = StringBuffer('# Copia de la bóveda, por tandas\n\n')
        ..writeln('Equipo: ${env.description}')
        ..writeln();
      // Con los selectores del sistema, alguien —un guion— los maneja mientras
      // corre, y eso le cuesta tiempo a la máquina: sus pasos de armar y abrir
      // no son los de la corrida limpia.
      if (env.gateway != null) {
        report
          ..writeln(
            'Con los selectores del sistema manejados desde afuera: los '
            'tiempos de armar y de abrir salen más lentos que en la corrida '
            'limpia (`latest_backup_report.md`); lo que esta corrida mide es '
            'guardar y elegir la copia.',
          )
          ..writeln();
      }
      void say(String line) {
        env.log(line);
        report.writeln(line);
      }

      String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

      final opened = await env.openVault();
      final db = opened.db;
      addTearDown(db.close);

      // Unos originales, además de la base: de texto, que se comprimen, y PDF,
      // que se guardan tal cual.
      final docs = await Directory.systemTemp.createTemp('sinapsis_docs_');
      addTearDown(() async {
        try {
          await docs.delete(recursive: true);
          // En Windows un archivo recién cerrado puede tardar en soltarse.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
      });
      final originals = Directory(p.join(docs.path, 'originales', 'doc-1'))
        ..createSync(recursive: true);
      final random = Random(11);
      for (var i = 0; i < 6; i++) {
        File(p.join(originals.path, 'texto-$i.txt')).writeAsStringSync(
          List.generate(160000, (n) => 'renglón $n del texto $i').join('\n'),
        );
        File(p.join(originals.path, 'libro-$i.pdf')).writeAsBytesSync(
          List.generate(4 * 1024 * 1024, (_) => random.nextInt(256)),
        );
      }
      final originalsBytes = originals.listSync().whereType<File>().fold<int>(
        0,
        (sum, f) => sum + f.lengthSync(),
      );

      final service = LocalVaultBackupService(
        database: db,
        documentsDirectory: () async => docs,
      );
      final dbBytes =
          (await db.customSelect('PRAGMA page_count').getSingle()).read<int>(
            'page_count',
          ) *
          (await db.customSelect('PRAGMA page_size').getSingle()).read<int>(
            'page_size',
          );
      say(
        '- la bóveda: ${mb(dbBytes)} de base, ${opened.vault.profile.items} '
        'elementos, y ${mb(originalsBytes)} de originales (12 archivos)',
      );
      final originalItems =
          (await db.customSelect('SELECT COUNT(*) AS n FROM item').getSingle())
              .read<int>('n');
      int itemsIn(IncomingVault vault) {
        final copy = sqlite3.sqlite3.open(
          vault.databaseFile.path,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          return copy.select('SELECT COUNT(*) AS n FROM item').first['n']
              as int;
        } finally {
          copy.close();
        }
      }

      // Como en la app: dónde va se pregunta ANTES de armar, que lleva minutos.
      final gateway = env.gateway;
      final target = gateway == null
          ? null
          : await gateway.chooseTarget(fileName: 'sinapsis-backup-bench.zip');
      if (gateway != null) {
        expect(target, isNotNull, reason: 'se eligió una carpeta');
      }

      // --- Armar la copia ---
      var sampler = await RssSampler.start();
      var watch = Stopwatch()..start();
      final built = await service.buildBackupFile();
      final buildMs = watch.elapsedMilliseconds;
      final buildGrowth = await sampler.stop();
      addTearDown(() => service.discardBackup(built));
      say(
        '- **armar la copia: $buildMs ms**; el .zip pesa '
        '${mb(built.sizeBytes)} '
        '(${(built.sizeBytes * 100 / (dbBytes + originalsBytes)).round()} % de '
        'lo que ocupan la base y los originales); memoria residente '
        '+${mb(buildGrowth)}',
      );

      // --- Guardarla donde se eligió ---
      String? savedAt;
      int? saveMs;
      int? saveGrowth;
      if (gateway != null && target != null) {
        sampler = await RssSampler.start();
        watch = Stopwatch()..start();
        savedAt = await gateway.save(target: target, sourcePath: built.path);
        saveMs = watch.elapsedMilliseconds;
        saveGrowth = await sampler.stop();
        final mbPerSecond = built.sizeBytes / 1048576 / (saveMs / 1000);
        say(
          '- **guardarla en la carpeta elegida con el selector del sistema: '
          '$saveMs ms** (${mbPerSecond.toStringAsFixed(0)} MB/s); quedó en '
          '$savedAt; memoria residente +${mb(saveGrowth)}',
        );
      }

      // --- Elegirla de vuelta, como al traer otra copia ---
      if (gateway != null && savedAt != null) {
        sampler = await RssSampler.start();
        watch = Stopwatch()..start();
        final pickedPath = await gateway.pickZip();
        final pickMs = watch.elapsedMilliseconds;
        final pickGrowth = await sampler.stop();
        expect(pickedPath, isNotNull, reason: 'se eligió la copia guardada');
        final picked = File(pickedPath!);
        say(
          '- **elegirla con el selector del sistema: $pickMs ms**; el selector '
          'la copia al almacenamiento temporal de la app '
          '(${mb(picked.lengthSync())}); memoria residente '
          '+${mb(pickGrowth)}',
        );
        expect(
          picked.lengthSync(),
          built.sizeBytes,
          reason: 'la copia elegida es la guardada',
        );
        final again = await IncomingVault.openFile(picked);
        final pickedItems = itemsIn(again);
        await again.dispose();
        expect(
          pickedItems,
          originalItems,
          reason: 'la copia elegida trae todos los elementos',
        );
        await gateway.discardPicked();
        expect(
          picked.existsSync(),
          isFalse,
          reason:
              'soltar lo elegido borra la copia del almacenamiento temporal',
        );
        say(
          '- la copia elegida se abre desde su ruta con sus $pickedItems '
          'elementos y, al soltarla, el almacenamiento temporal de la app '
          'queda sin ella',
        );
      }

      // --- Abrirla ---
      sampler = await RssSampler.start();
      watch = Stopwatch()..start();
      final incoming = await IncomingVault.openFile(File(built.path));
      final openMs = watch.elapsedMilliseconds;
      final openGrowth = await sampler.stop();
      addTearDown(incoming.dispose);
      say(
        '- **abrirla (sacar la base a un temporal y dejarla lista): '
        '$openMs ms**; '
        'memoria residente +${mb(openGrowth)}',
      );

      // --- Que es la misma bóveda ---
      final copiedItems = itemsIn(incoming);
      expect(
        copiedItems,
        originalItems,
        reason: 'la copia trae todos los elementos',
      );
      expect(incoming.originalPaths.length, 12);
      final restored = Directory(p.join(docs.path, 'restaurado'))..createSync();
      final copiedPdf = await incoming.copyOriginalTo(
        'originales/doc-1/libro-0.pdf',
        restored,
      );
      expect(
        copiedPdf!.readAsBytesSync(),
        File(p.join(originals.path, 'libro-0.pdf')).readAsBytesSync(),
      );
      say(
        '- la copia se lee de vuelta con el CRC de cada entrada verificado: '
        '$copiedItems elementos, 12 originales, un PDF idéntico',
      );
      say(
        '- memoria residente máxima del proceso: '
        '${ProcessInfo.maxRss ~/ 1048576} MB',
      );

      env.save(
        gateway == null
            ? 'latest_backup_report.md'
            : 'latest_backup_saf_report.md',
        report.toString(),
      );

      // Ni armarla ni abrirla deben crecer con la bóveda: una fracción de lo
      // que pesa la base. Sin un dato real de un teléfono, un cuarto es un
      // techo sin estrenar.
      expect(buildGrowth, lessThan(dbBytes ~/ 4), reason: 'armar la copia');
      expect(openGrowth, lessThan(dbBytes ~/ 4), reason: 'abrir la copia');
      expect(buildMs, lessThan(env.timeCeiling.inMilliseconds));
      expect(openMs, lessThan(env.timeCeiling.inMilliseconds));
      if (saveMs != null && saveGrowth != null) {
        expect(saveGrowth, lessThan(dbBytes ~/ 4), reason: 'guardar la copia');
        expect(saveMs, lessThan(env.timeCeiling.inMilliseconds));
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
