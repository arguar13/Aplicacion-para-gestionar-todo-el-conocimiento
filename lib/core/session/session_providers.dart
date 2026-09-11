import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/token_storage.dart';
import 'package:sinapsis/core/session/session_controller.dart';
import 'package:sinapsis/core/session/session_state.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';

/// Deliberadamente NO autoDispose: la sesión debe sobrevivir mientras la
/// app esté abierta, sin importar qué pantalla esté montada.
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      return SessionController(
        tokenStorage: ref.watch(tokenStorageProvider),
        logger: ref.watch(appLoggerProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });
