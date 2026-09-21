import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';

/// El mapa de conocimiento calcula en un isolate, y un `Isolate.run` no
/// termina bajo el reloj simulado de las pruebas de widgets: con estos
/// overrides el motor y el acomodo del grafo calculan en el propio isolate y
/// sin esperar, que es lo mismo pero que una prueba puede recorrer.
///
/// Los necesita toda prueba que monte la pantalla del Mapa —que es la pestaña
/// de lo que antes era el grafo—, con el arnés de la biblioteca o por su
/// cuenta.
final List<Override> mapInlineOverrides = [
  mapLayoutRunnerProvider.overrideWithValue((job) async => runLayout(job)),
  knowledgeMapEngineProvider.overrideWith((ref) {
    final engine = KnowledgeMapEngine(
      repository: ref.watch(knowledgeMapRepositoryProvider),
      telemetry: ref.watch(telemetryServiceProvider),
      compute: (input, memory) async => computeMap(input, memory),
      debounce: Duration.zero,
      maxWait: Duration.zero,
    );
    ref.onDispose(engine.dispose);
    return engine;
  }),
];
