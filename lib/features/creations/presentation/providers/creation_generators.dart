import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/data_table/data_table_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/mind_map/mind_map_kind.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/providers/presentation_providers.dart';
import 'package:sinapsis/features/creations/quiz/presentation/quiz_kind.dart';
import 'package:sinapsis/features/creations/report/presentation/report_kind.dart';

/// Los generadores de «Lo creado» (F43, ola 3): **uno por tipo, y sumar uno es
/// una línea acá**, con el proveedor que arma el suyo en la carpeta de su tipo
/// (`lib/features/creations/<tipo>/`):
///
/// ```dart
/// final creationGeneratorsProvider = Provider<List<CreationGenerator>>(
///   (ref) => [
///     ref.watch(mindMapGeneratorProvider),
///   ],
/// );
/// ```
///
/// Las tres de extraer no tienen generador: no le piden nada a la IA. Un tipo
/// de la IA sin generador todavía queda fallido por «sin soporte» si se lo
/// pide (`CreationFailure.unsupported`).
final creationGeneratorsProvider = Provider<List<CreationGenerator>>(
  (ref) => [
    ref.watch(infographicGeneratorProvider),
    ref.watch(reportGeneratorProvider),
    ref.watch(mindMapGeneratorProvider),
    ref.watch(dataTableGeneratorProvider),
    ref.watch(flashcardsGeneratorProvider),
    ref.watch(quizGeneratorProvider),
    ref.watch(presentationGeneratorProvider),
    ref.watch(podcastGeneratorProvider),
  ],
);

/// Los de [creationGeneratorsProvider], por tipo: lo que lee la cola. Dos para
/// el mismo tipo es un error de armado, y se dice en el acto.
final creationGeneratorRegistryProvider =
    Provider<Map<StudyCreationKind, CreationGenerator>>((ref) {
      final registry = <StudyCreationKind, CreationGenerator>{};
      for (final generator in ref.watch(creationGeneratorsProvider)) {
        if (generator.kind.isLiveView) {
          throw StateError(
            '${generator.kind.storageKey} es de extraer: no lleva generador.',
          );
        }
        if (registry.containsKey(generator.kind)) {
          throw StateError(
            'Dos generadores para ${generator.kind.storageKey}.',
          );
        }
        registry[generator.kind] = generator;
      }
      return Map.unmodifiable(registry);
    });
