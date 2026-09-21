import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/features/vault/data/services/disk_space_plus_free_space_probe.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../test/benchmark/vault_migration_benchmark.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// La migración a escala, EN el dispositivo: la bóveda de 10.000 elementos de
/// un esquema anterior (v17, ~909 MB) llevada de una vez al esquema actual,
/// con el respaldo previo del archivo entero —el peor caso de entrada y salida
/// contra la flash—.
///
/// La bóveda vieja no se puede armar en el teléfono —el generador solo arma la
/// actual—: se empuja con `tool/bench_android.ps1 -PushVaults`, a la carpeta
/// `files/bench` de la app. Necesita unos 3 GB libres (la bóveda, su copia y el
/// respaldo).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  // En Android SQLite no tiene dónde dejar sus temporales si no se le dice: la
  // app real se lo dice con drift_flutter, y estas pruebas abren la base
  // directo.
  setUpAll(() async {
    sqlite3.sqlite3.tempDirectory = (await getTemporaryDirectory()).path;
  });

  group(
    'benchmark de la migración a escala, en el dispositivo',
    () => registerVaultMigrationBenchmark(
      MigrationBenchmarkEnvironment(
        oldVaultFile: () async {
          final external = await getExternalStorageDirectory();
          if (external == null) return null;
          final file = File('${external.path}/bench/vault_s17_g4_10000.sqlite');
          return file.existsSync() ? file : null;
        },
        log: debugPrint,
        save: (name, content) {
          reports[name] = content;
          binding.reportData = Map<String, dynamic>.of(reports);
        },
        description: _deviceInfo,
        // En el dispositivo el complemento existe: el consejero mira el disco.
        freeSpace: const DiskSpacePlusFreeSpaceProbe(),
        // Sin cifras de un teléfono todavía: un techo que solo avisa de algo
        // absurdo, hasta tener un primer dato real.
        ceiling: const Duration(minutes: 30),
      ),
    ),
  );
}
