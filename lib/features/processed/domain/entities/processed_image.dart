import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'processed_image.freezed.dart';

/// De dónde sale una imagen que ofrece una fuente (F41, decisión L).
enum SourceImageOrigin {
  /// El archivo de la fuente misma: una imagen guardada, una captura, o la
  /// foto de una publicación.
  original,

  /// Una foto de su «Contenido» (F30): las del artículo de una página
  /// guardada, o las demás fotos del carrusel de una publicación.
  content,
}

/// Una imagen que una fuente ofrece para llevar a Procesado (decisión L).
///
/// Solo lo que hace falta para mostrarla en miniatura, decir cuánto ocupa y
/// copiarla: dónde está, cuánto pesa y cómo se llama. Nunca sus bytes: una
/// página con trescientas fotos se lista sin abrir ninguna.
@freezed
sealed class SourceImage with _$SourceImage {
  const factory SourceImage({
    /// El archivo, relativo al almacén (`FileStore`). Es su identidad: otro
    /// archivo es otra imagen —un original de la Biblioteca no se reescribe—,
    /// y es lo que dice, al volver a triar, si ya está en el procesado.
    required String path,
    required SourceImageOrigin origin,

    /// Cuánto pesa, en bytes: lo que va a ocupar su copia.
    required int sizeBytes,

    /// Con qué nombre se ofrecía: el texto alternativo de una foto de la
    /// página. `null` si no tenía.
    String? title,

    /// El tipo que dijo el servidor, si lo dijo.
    String? mimeType,
  }) = _SourceImage;
}

/// Cuántas imágenes ofrece una fuente y cuánto pesan todas juntas: la cabeza
/// de la grilla de la hoja, sin listar ninguna.
@freezed
sealed class SourceImagesSummary with _$SourceImagesSummary {
  const factory SourceImagesSummary({
    required int count,
    required int sizeBytes,
  }) = _SourceImagesSummary;

  static const none = SourceImagesSummary(count: 0, sizeBytes: 0);
}

/// Una imagen guardada en un documento procesado (decisión L): **una copia
/// propia** del archivo de la fuente, como la copia del original (decisión
/// H). Ocupa su espacio, y viaja con el documento en la papelera, la copia y
/// la unión de bóvedas. Ver `ProcessedImages`.
@freezed
sealed class ProcessedImage with _$ProcessedImage {
  const factory ProcessedImage({
    /// La forma del procesado que guarda la copia: su identidad.
    required String renditionId,
    required String documentId,

    /// Su lugar en la galería, de 0 en adelante.
    required int position,

    /// La copia, relativa al almacén: para abrirla, `FileStore.localPathOf`.
    required String relativePath,

    /// Cuánto pesa la copia.
    required int sizeBytes,

    /// El archivo de la fuente del que salió. Soltarlo de la fuente no toca
    /// la copia, y al revés; sirve para no copiar dos veces la misma imagen.
    required String sourceFilePath,
    required DateTime copiedAt,
    String? title,
    String? mimeType,
  }) = _ProcessedImage;
}

/// Qué imágenes de la fuente se eligieron en la hoja (decisión L): todas
/// —menos algunas— o solo algunas, por su `SourceImage.path`.
///
/// «Todas» no enumera nada: una fuente con trescientas fotos se elige entera
/// sin haberlas cargado. Quien la resuelve (`ProcessSourceUseCase`) lee la
/// lista de la fuente al guardar.
@freezed
sealed class ImageChoice with _$ImageChoice {
  /// Todas las que ofrece la fuente, salvo [except].
  const factory ImageChoice.all({@Default(<String>{}) Set<String> except}) =
      AllImages;

  /// Solo [paths].
  const factory ImageChoice.only(Set<String> paths) = SomeImages;

  const ImageChoice._();

  /// Ninguna.
  static const none = ImageChoice.only(<String>{});

  /// Si la imagen [path] va.
  bool includes(String path) => switch (this) {
    AllImages(:final except) => !except.contains(path),
    SomeImages(:final paths) => paths.contains(path),
  };

  /// La misma elección con [path] dada vuelta: elegida si no lo estaba, y al
  /// revés.
  ImageChoice toggled(String path) => switch (this) {
    AllImages(:final except) => ImageChoice.all(
      except: except.contains(path)
          ? ({...except}..remove(path))
          : {...except, path},
    ),
    SomeImages(:final paths) => ImageChoice.only(
      paths.contains(path) ? ({...paths}..remove(path)) : {...paths, path},
    ),
  };

  /// Cuántas van, de las [offered] que ofrece la fuente.
  int countOf(int offered) => switch (this) {
    AllImages(:final except) => (offered - except.length).clamp(0, offered),
    SomeImages(:final paths) => paths.length,
  };
}

/// Una copia de una imagen de la fuente ya hecha y todavía sin guardar en la
/// base: lo que deja `ProcessedRepository.stageImages`. Si el guardado no
/// llega, `ProcessedRepository.discardStagedImages` la borra.
@immutable
class StagedImage {
  const StagedImage({
    required this.source,
    required this.relativePath,
    required this.sizeBytes,
  });

  /// La imagen de la fuente que se copió.
  final SourceImage source;

  /// Dónde quedó la copia, relativa al almacén.
  final String relativePath;

  /// Cuánto pesa la copia.
  final int sizeBytes;
}

/// Cómo deshacer lo que se le hizo a la galería de un documento al procesar.
@immutable
class ProcessedImagesUndo {
  const ProcessedImagesUndo({
    required this.previous,
    required this.created,
    required this.trashed,
  });

  /// La galería como estaba, con sus lugares.
  final List<ProcessedImage> previous;

  /// Las copias que entraron: deshacer las borra, con su archivo.
  final List<ProcessedImage> created;

  /// Las filas de la papelera del contenido adonde fueron las que salieron:
  /// deshacer las devuelve a la galería.
  final List<String> trashed;
}

/// El comprobante de haber quitado una imagen de la galería: con él,
/// «Deshacer» la devuelve a su lugar (`ProcessedRepository.restoreImage`).
@immutable
class ProcessedImageRemoval {
  const ProcessedImageRemoval({required this.trashedId, required this.image});

  /// Su fila en la papelera del contenido: el archivo espera ahí 30 días.
  final String trashedId;
  final ProcessedImage image;
}
