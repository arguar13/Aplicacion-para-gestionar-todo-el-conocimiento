import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/device_identity.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_session_controller.dart';

import '../test/benchmark/synthetic_vault.dart';
import 'support/device_benchmark_directory.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Sin nada compartido desde otra app: lo que llega por el botón de compartir
/// no depende de cuánto haya en la bóveda, y el plugin no tiene con qué
/// contestar fuera de un teléfono.
class _NothingShared implements SharedContentListener {
  const _NothingShared();

  @override
  Future<List<CaptureRequest>> initial() async => const [];

  @override
  Stream<List<CaptureRequest>> get stream => const Stream.empty();
}

/// La apertura de la app con la bóveda de 10.000 elementos, EN el dispositivo:
/// cuánto pasa desde que se monta la app hasta que la Biblioteca muestra el
/// primer elemento. Es lo que ve alguien que abre la app con la bóveda llena.
///
/// Lo que cuenta: abrir la base de la bóveda sintética —la conexión y su
/// verificación—, armar los proveedores y el router, y la primera consulta de
/// la lista, con la app de verdad y sin el PIN (se entra ya desbloqueada:
/// teclear no se mide). Lo que NO cuenta, y se mide aparte: el arranque del
/// motor y del proceso —independiente de cuánto haya en la bóveda—, con
/// `flutter run --profile --trace-startup --flavor staging`, que imprime
/// cuándo se pintó el primer cuadro. Y el caché de archivos del sistema no se
/// vacía: si la bóveda se acaba de armar, sus páginas están en memoria; un
/// teléfono recién reiniciado sería peor.
///
/// La app no toca su base propia: se le pasa la de la bóveda sintética.
///
///     tool/bench_android.ps1 -Target cold_start_benchmark_test
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('apertura de la app con 10.000 elementos, hasta la lista', (
    tester,
  ) async {
    final report = StringBuffer('# Apertura de la app a escala\n\n')
      ..writeln('Equipo: $_deviceInfo')
      ..writeln();
    void say(String line) {
      debugPrint(line);
      report.writeln(line);
    }

    EnvConfig.initialize(AppFlavor.dev);
    final directory = await deviceBenchmarkDirectory();
    final opened = await openBenchmarkVault(directory: directory);
    final profile = opened.vault.profile;
    await opened.db.close();
    final file = benchmarkVaultFile(profile: profile, directory: directory);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final rssBefore = ProcessInfo.currentRss ~/ (1024 * 1024);
    final total = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(
            const DeviceIdentity('bench'),
          ),
          // La base de la bóveda sintética, abierta al leerla por primera
          // vez, como abre la suya la app: su apertura entra en lo medido.
          appDatabaseProvider.overrideWith((ref) {
            final database = AppDatabase(
              NativeDatabase.createInBackground(file),
              deviceId: 'bench',
            );
            ref.onDispose(database.close);
            return database;
          }),
          sharedContentListenerProvider.overrideWithValue(
            const _NothingShared(),
          ),
          // Ya desbloqueada: el PIN no se mide.
          vaultSessionControllerProvider.overrideWith(
            (ref) => VaultSessionController(
              checkVaultExists: ref.watch(checkVaultExistsUseCaseProvider),
              logger: ref.watch(appLoggerProvider),
            )..markUnlocked(),
          ),
        ],
        child: const App(),
      ),
    );
    final firstFrameMs = total.elapsedMilliseconds;

    while (find.byType(LibraryItemCard).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(total.elapsed, lessThan(const Duration(minutes: 2)));
    }
    final firstListMs = total.elapsedMilliseconds;

    final megabytes = file.lengthSync() ~/ (1024 * 1024);
    say('- bóveda: ${profile.items} elementos ($megabytes MB)');
    say('- de montar la app al primer cuadro: $firstFrameMs ms');
    say('- **de montar la app a la primera lista: $firstListMs ms**');
    say(
      '- memoria residente: $rssBefore MB antes, '
      '${ProcessInfo.currentRss ~/ (1024 * 1024)} MB después',
    );

    binding.reportData = {
      ...?binding.reportData,
      'latest_cold_start_report.md': report.toString(),
    };
  }, timeout: const Timeout(Duration(minutes: 10)));
}
