import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';

/// Una imagen de cómo va a quedar la galería de un documento procesado.
sealed class PlannedImage {
  const PlannedImage();
}

/// Una copia que ya estaba y se queda, tal cual —solo puede cambiar de lugar—.
final class KeptImage extends PlannedImage {
  const KeptImage(this.image);
  final ProcessedImage image;
}

/// Una imagen de la fuente que entra: hay que copiarla.
final class NewImage extends PlannedImage {
  const NewImage(this.source);
  final SourceImage source;
}

/// Cómo va a quedar la sección Imágenes de un documento procesado después de
/// un cambio (decisión L), sin haberlo guardado: sirve igual para la vista
/// previa de la hoja y para guardar.
@immutable
class ImagesPlan {
  const ImagesPlan({required this.images, required this.removed});

  /// La galería como va a quedar, en orden.
  final List<PlannedImage> images;

  /// Las copias que se van —a la papelera del contenido, de donde se
  /// recuperan—.
  final List<ProcessedImage> removed;

  /// Las imágenes que hay que copiar de la fuente.
  List<SourceImage> get fresh => [
    for (final image in images)
      if (image case NewImage(:final source)) source,
  ];

  int get added => images.whereType<NewImage>().length;
  int get kept => images.whereType<KeptImage>().length;

  /// Lo que ocupa la galería como va a quedar, en bytes.
  int get sizeBytes => images.fold(
    0,
    (sum, image) =>
        sum +
        switch (image) {
          KeptImage(:final image) => image.sizeBytes,
          NewImage(:final source) => source.sizeBytes,
        },
  );

  /// Lo que suman las copias nuevas: el espacio que se va a ocupar de más.
  int get addedBytes => fresh.fold(0, (sum, source) => sum + source.sizeBytes);

  /// Si no cambia nada: ni entra ni sale ninguna, ni se mueve ninguna.
  bool get isNoOp {
    if (removed.isNotEmpty) return false;
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      if (image is NewImage) return false;
      if (image is KeptImage && image.image.position != i) return false;
    }
    return true;
  }
}

/// Cómo queda la galería —que hoy tiene [existing], en orden— si se le hace
/// [change] con [chosen] como lo elegido de la fuente, en el orden de la
/// fuente (decisión L). Pura: no lee ni escribe nada.
///
/// Una imagen es la misma si sale del mismo archivo de la fuente
/// (`ProcessedImage.sourceFilePath` y `SourceImage.path`): nunca se copia dos
/// veces.
///
/// - **Agregar** deja todas las que estaban, en su lugar, y suma al final las
///   elegidas que no están.
/// - **Reemplazar** deja exactamente las elegidas, en el orden de la fuente.
///   La que ya estaba se queda con su copia —no se vuelve a copiar—; la que no
///   se eligió se va.
/// - **Quitar** saca todas.
///
/// «Actualizar» no aplica: una imagen no tiene una versión de ahora en la
/// fuente —otro archivo es otra imagen—, así que se rechaza antes
/// (`SectionEdit.problemFor`).
ImagesPlan planImagesChange({
  required List<ProcessedImage> existing,
  required ProcessedChange change,
  required List<SourceImage> chosen,
}) {
  final bySource = {for (final image in existing) image.sourceFilePath: image};
  switch (change) {
    case ProcessedChange.remove:
      return ImagesPlan(images: const [], removed: existing);
    case ProcessedChange.add:
      final seen = {...bySource.keys};
      return ImagesPlan(
        images: [
          for (final image in existing) KeptImage(image),
          for (final source in chosen)
            if (seen.add(source.path)) NewImage(source),
        ],
        removed: const [],
      );
    case ProcessedChange.replace:
      final seen = <String>{};
      final images = <PlannedImage>[
        for (final source in chosen)
          if (seen.add(source.path))
            if (bySource[source.path] case final kept?)
              KeptImage(kept)
            else
              NewImage(source),
      ];
      return ImagesPlan(
        images: images,
        removed: [
          for (final image in existing)
            if (!seen.contains(image.sourceFilePath)) image,
        ],
      );
    case ProcessedChange.update:
      throw ArgumentError.value(
        change,
        'change',
        'Una imagen no tiene una versión de la fuente que traer.',
      );
  }
}
