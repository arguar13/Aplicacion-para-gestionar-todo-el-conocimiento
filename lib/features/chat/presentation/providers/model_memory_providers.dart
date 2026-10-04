import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/chat/data/services/model_memory_keeper.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';

/// Quien saca de la memoria los modelos de la IA cuando no hacen falta (F30,
/// ver `ModelMemoryKeeper`). Uno solo en toda la app.
final modelMemoryKeeperProvider = Provider<ModelMemoryKeeper>((ref) {
  final keeper = ModelMemoryKeeper(
    gate: ref.watch(languageModelGateProvider),
    gemma: ref.watch(gemmaEngineProvider),
    releaseEmbedder: ({unusedFor}) =>
        ref.read(embeddingServiceProvider).release(unusedFor: unusedFor),
    onError: (error, stackTrace) => ref
        .read(telemetryServiceProvider)
        .recordError(
          error,
          stackTrace,
          hint: 'ModelMemoryKeeper: sacar los modelos de la memoria',
        ),
  );
  ref.onDispose(keeper.dispose);
  return keeper;
});

/// Le pasa a [ModelMemoryKeeper] los avisos de Android: que falta memoria, y
/// que la app pasó a segundo plano o volvió. Lo registra la raíz de la app.
///
/// Pide el guardián al primer aviso, no al nacer: armarlo arma la cadena de
/// proveedores de los modelos, y la app no la necesita para arrancar.
class ModelMemoryObserver with WidgetsBindingObserver {
  ModelMemoryObserver(this._keeper);

  final ModelMemoryKeeper Function() _keeper;

  @override
  void didHaveMemoryPressure() => unawaited(_keeper().memoryPressure());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _keeper().appShown();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _keeper().appHidden();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }
}
