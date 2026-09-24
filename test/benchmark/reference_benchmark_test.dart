import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'reference_benchmark.dart';
import 'vault_benchmark.dart' show BenchmarkEnvironment, kDesktopFactor;

/// La bóveda con referencias en escritorio; la medición está en
/// `reference_benchmark.dart`, compartida con la de dispositivo
/// (`integration_test/reference_benchmark_test.dart`).
///
///     flutter test test/benchmark/reference_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark de la bóveda con referencias',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerReferenceBenchmark(
      BenchmarkEnvironment(
        open: openReferenceBenchmarkVault,
        log: stdout.writeln,
        save: (name, content) {
          Directory(
            '.dart_tool/sinapsis_benchmark',
          ).createSync(recursive: true);
          File(
            '.dart_tool/sinapsis_benchmark/$name',
          ).writeAsStringSync(content);
        },
        targetDivisor: kDesktopFactor,
        description: const String.fromEnvironment(
          'BENCH_DEVICE_INFO',
          defaultValue: 'escritorio',
        ),
      ),
    ),
  );
}
