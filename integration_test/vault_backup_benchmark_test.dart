import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/features/vault/data/services/system_vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../test/benchmark/synthetic_vault.dart';
import '../test/benchmark/vault_backup_benchmark.dart';
import 'support/device_benchmark_directory.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Con `BENCH_SAVE_TO_FOLDER=true` (`tool/bench_android.ps1 -SaveToFolder`) la
/// copia se guarda además con el selector de carpetas del sistema, como en la
/// app; alguien tiene que manejar ese selector: ver
/// `tool/bench_android_pick_folder.ps1`.
const _saveToFolder = bool.fromEnvironment('BENCH_SAVE_TO_FOLDER');

VaultBackupFileGateway? _gatewayToUse() =>
    _saveToFolder ? const SystemVaultBackupFileGateway() : null;

/// La copia de la bóveda de 10.000 elementos armada por tandas y vuelta a
/// abrir, EN el dispositivo: cuánta memoria usa, cuánto tarda y cuánto pesa
/// el `.zip`.
///
/// Arma la bóveda en el directorio temporal del dispositivo la primera vez
/// —varios minutos y ~1,2 GB—. Necesita unos 3 GB libres: la bóveda, el `.zip`
/// y la base sacada de él.
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
    'benchmark de la copia de la bóveda, en el dispositivo',
    () => registerVaultBackupBenchmark(
      BackupBenchmarkEnvironment(
        openVault: () async =>
            openBenchmarkVault(directory: await deviceBenchmarkDirectory()),
        log: debugPrint,
        save: (name, content) {
          reports[name] = content;
          binding.reportData = Map<String, dynamic>.of(reports);
        },
        description: _deviceInfo,
        gateway: _gatewayToUse(),
      ),
    ),
  );
}
