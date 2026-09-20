import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/benchmark/synthetic_vault.dart';
import '../test/benchmark/vault_merge_benchmark.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// La fusión a escala, EN el dispositivo: los mismos pasos que en escritorio
/// (`test/benchmark/vault_merge_benchmark.dart`), con la misma bóveda de 10.000
/// elementos y ~300.000 chunks y una variante suya modificada por otro
/// dispositivo.
///
/// Copia la bóveda tres veces (dos dispositivos y la copia entrante) y arma una
/// cuarta al importar en una vacía: necesita unos 3 GB libres. Se corre con
/// `tool/bench_android.ps1 -Target vault_merge_benchmark_test`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  group(
    'benchmark de la fusión a escala, en el dispositivo',
    () => registerVaultMergeBenchmark(
      MergeBenchmarkEnvironment(
        vaultFile: () async {
          final temporary = await getTemporaryDirectory();
          final directory = Directory('${temporary.path}/sinapsis_benchmark');
          final opened = await openBenchmarkVault(directory: directory);
          final profile = opened.vault.profile;
          await opened.db.close();
          return (
            file: benchmarkVaultFile(profile: profile, directory: directory),
            profile: profile,
          );
        },
        log: debugPrint,
        save: (name, content) {
          reports[name] = content;
          binding.reportData = Map<String, dynamic>.of(reports);
        },
        description: _deviceInfo,
        // Sin cifras de un teléfono todavía: techos que solo avisan de algo
        // absurdo, hasta tener un primer dato real.
        firstMergeCeiling: const Duration(minutes: 30),
        repeatMergeCeiling: const Duration(minutes: 10),
        importCeiling: const Duration(hours: 2),
      ),
    ),
  );
}
