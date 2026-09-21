import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'synthetic_vault.dart';
import 'vault_backup_benchmark.dart';

/// La copia de la bóveda por tandas en escritorio; la medición está en
/// `vault_backup_benchmark.dart`, compartida con la de dispositivo
/// (`integration_test/vault_backup_benchmark_test.dart`).
///
///     flutter test test/benchmark/vault_backup_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark de la copia de la bóveda',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerVaultBackupBenchmark(
      BackupBenchmarkEnvironment(
        openVault: openBenchmarkVault,
        log: stdout.writeln,
        save: (name, content) {
          Directory(
            '.dart_tool/sinapsis_benchmark',
          ).createSync(recursive: true);
          File(
            '.dart_tool/sinapsis_benchmark/$name',
          ).writeAsStringSync(content);
        },
        description: const String.fromEnvironment(
          'BENCH_DEVICE_INFO',
          defaultValue: 'escritorio',
        ),
      ),
    ),
  );
}
