import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/benchmark/reference_benchmark.dart';
import '../test/benchmark/vault_benchmark.dart' show BenchmarkEnvironment;
import 'support/device_benchmark_directory.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// La bóveda con referencias, EN el dispositivo: los mismos escenarios que en
/// escritorio (`test/benchmark/reference_benchmark.dart`), con su propia
/// bóveda de 15.000 elementos —para tener 10.000 fuentes con referencia—.
///
/// Se corre con `tool/bench_android.ps1 -Target reference_benchmark_test`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  group(
    'benchmark de la bóveda con referencias, en el dispositivo',
    () => registerReferenceBenchmark(
      BenchmarkEnvironment(
        open: () async {
          final directory = await deviceBenchmarkDirectory();
          return openReferenceBenchmarkVault(directory: directory);
        },
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
