import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/benchmark/synthetic_vault.dart';
import '../test/benchmark/vault_benchmark.dart';
import 'support/device_benchmark_directory.dart';

/// Cómo se llama el equipo donde corre, para el encabezado del informe:
/// `tool/bench_android.ps1` lo arma con el modelo, el Android y la memoria del
/// teléfono.
const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// El benchmark de la bóveda sintética, para correr EN el dispositivo: los
/// mismos escenarios que en escritorio, pero exigiendo el objetivo del encargo
/// tal cual —FTS < 300 ms, detalle < 200 ms, grafo local < 500 ms— porque acá
/// el teléfono es el teléfono.
///
/// Se corre en modo profile, que es el código de la app de verdad; en debug,
/// las cifras del Dart serían de 5 a 10 veces peores:
///
///     tool/bench_android.ps1
///
/// que arma este comando:
///
///     flutter drive --profile --flavor staging -d <dispositivo> \
///       --driver=test_driver/integration_test.dart \
///       --target=integration_test/vault_benchmark_test.dart
///
/// La primera vez arma la bóveda de 10.000 elementos y ~300.000 chunks en el
/// directorio temporal del dispositivo, y necesita unos 1,2 GB libres. Los
/// informes viajan a la PC por `reportData` y los guarda el driver
/// (`test_driver/integration_test.dart`).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  group(
    'benchmark de la bóveda sintética, en el dispositivo',
    () => registerVaultBenchmark(
      BenchmarkEnvironment(
        open: () async =>
            openBenchmarkVault(directory: await deviceBenchmarkDirectory()),
        log: debugPrint,
        save: (name, content) {
          reports[name] = content;
          binding.reportData = Map<String, dynamic>.of(reports);
        },
        description: _deviceInfo,
      ),
    ),
  );
}
