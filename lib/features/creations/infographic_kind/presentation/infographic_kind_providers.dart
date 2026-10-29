import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_view.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_generator.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustrator.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';

/// Quien dibuja las ilustraciones de una infografía: al generarla y desde el
/// visor. Sus dependencias se leen al usarlas —como la cola—: cambiar de
/// cuenta no lo rearma.
final infographicIllustratorProvider = Provider<InfographicIllustrator>(
  (ref) => InfographicIllustrator(
    service: () => ref.read(illustrationServiceProvider),
    store: () => ref.read(creationIllustrationStoreProvider),
    textAccountId: () => creationTextAccountId(ref),
  ),
);

/// El generador de la infografía, para `creationGeneratorsProvider`.
final infographicGeneratorProvider = Provider<CreationGenerator>(
  (ref) => InfographicGenerator(
    illustrator: ref.watch(infographicIllustratorProvider),
  ),
);

/// Las ilustraciones ya hechas de una lámina, como las pide `InfographicView`.
@immutable
class InfographicIllustrations {
  const InfographicIllustrations(this.references);

  /// Las de [sheet].
  factory InfographicIllustrations.of(Infographic sheet) =>
      InfographicIllustrations(
        InfographicIllustrationPlan.references(sheet).toList()..sort(),
      );

  final List<String> references;

  @override
  bool operator ==(Object other) =>
      other is InfographicIllustrations &&
      listEquals(other.references, references);

  @override
  int get hashCode => Object.hashAll(references);
}

/// Las imágenes de [InfographicIllustrations], leídas del almacén: por
/// referencia, la imagen en memoria. Una que ya no está no figura, y su
/// lugar se dibuja.
///
/// Las imágenes se arman una vez por lámina: así no parpadean al
/// redibujarse, y la misma sirve a la lámina, a la galería y a la hoja de
/// diseño.
final infographicImagesProvider = FutureProvider.autoDispose
    .family<Map<String, ImageProvider>, InfographicIllustrations>((
      ref,
      illustrations,
    ) async {
      final store = ref.watch(creationIllustrationStoreProvider);
      return {
        for (final reference in illustrations.references)
          if (await store.read(reference) case final bytes?)
            reference: MemoryImage(bytes),
      };
    });

/// El resolvedor de `InfographicView` sobre [images]; `null` sin ninguna.
InfographicIllustrationResolver? infographicResolver(
  Map<String, ImageProvider> images,
) => images.isEmpty ? null : (reference) => images[reference];

/// Lee las imágenes de [sheet] de una vez, para dibujarla fuera de pantalla
/// (la imagen y el PDF).
Future<InfographicIllustrationResolver?> loadInfographicResolver(
  CreationIllustrationStore store,
  Infographic sheet,
) async {
  final images = <String, ImageProvider>{
    for (final reference in InfographicIllustrationPlan.references(sheet))
      if (await store.read(reference) case final bytes?)
        reference: MemoryImage(bytes),
  };
  return infographicResolver(images);
}

/// El diseño que se ve en el visor de una creación mientras se lo cambia —lo
/// comparten el visor y su botón de la barra—; `null`, el guardado.
final infographicLiveDesignProvider = StateProvider.autoDispose
    .family<InfographicDesign?, String>((ref, creationId) => null);
