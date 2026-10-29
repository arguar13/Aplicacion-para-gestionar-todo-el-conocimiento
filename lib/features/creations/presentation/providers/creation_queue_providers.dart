import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/domain/services/creation_material_builder.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_generators.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart'
    as study;
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Quien arma el material que entra en la ventana del modelo.
final creationMaterialBuilderProvider = Provider<CreationMaterialBuilder>(
  (ref) => CreationMaterialBuilder(
    processed: ref.watch(processedRepositoryProvider),
    scopes: ref.watch(creationScopeResolverProvider),
  ),
);

/// La cola de crear: «Generar ahora» y «Generar más tarde».
///
/// Deliberadamente NO autoDispose y sin `ref.watch` —como la cola de
/// procesamiento—: tiene que seguir trabajando aunque la persona cambie de
/// pantalla, y cambiar de modelo no puede descartarla con lo que tenía
/// esperando. Sus dependencias se leen al usarlas.
final creationQueueProvider = Provider<CreationQueue>((ref) {
  final queue = CreationQueue(
    repository: () => ref.read(studyCreationRepositoryProvider),
    scopes: () => ref.read(creationScopeResolverProvider),
    material: () => ref.read(creationMaterialBuilderProvider),
    generators: () => ref.read(creationGeneratorRegistryProvider),
    personWriter: () => ref.read(structuredWriterProvider),
    backgroundWriter: () => ref.read(backgroundLanguageModelProvider),
    readiness: () => ref.read(languageModelStatusCheckProvider),
    modelName: () => ref.read(languageModelNameProvider)(),
    keeper: () =>
        ref.read(longWorkCoordinatorProvider).keeperFor(LongWorkOwner.creating),
    analyzeForStudy: (documentId) =>
        unawaited(_analyzeProcessedForStudy(ref, documentId)),
    onError: (error, stackTrace) => ref
        .read(telemetryServiceProvider)
        .recordError(error, stackTrace, hint: 'CreationQueue'),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// Pide el análisis de estudio de siempre (F36, F41 decisión I) del documento
/// procesado [documentId], si no está completo, no está corriendo y el modelo
/// puede: lo que les falta a las de extraer.
Future<void> _analyzeProcessedForStudy(Ref ref, String documentId) async {
  final text =
      (await ref.read(processedRepositoryProvider).studyTextOf(documentId))
          .getRight()
          .toNullable();
  if (text == null) return;
  final notifier = ref.read(study.studyAnalysisProvider(text.key).notifier);
  if (notifier.isRunning) return;
  final studied = await ref
      .read(study.studyRepositoryProvider)
      .watch(text.key)
      .first;
  if (studied.complete) return;
  final status = await ref.read(languageModelStatusCheckProvider)();
  if (!status.isReady) return;
  await notifier.start(
    content: text.content,
    markdown: text.markdown,
    itemId: documentId,
  );
}
