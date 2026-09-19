import 'package:freezed_annotation/freezed_annotation.dart';

part 'broken_link.freezed.dart';

/// Una nota que escribe un `[[enlace]]` sin destino: lo mínimo para
/// reconocerla en una lista y abrirla.
@freezed
sealed class BrokenLinkSource with _$BrokenLinkSource {
  const factory BrokenLinkSource({
    required String itemId,
    required String title,
  }) = _BrokenLinkSource;
}

/// Un `[[Título]]` que no tiene ninguna nota con ese título, con las notas de
/// la bóveda que lo escriben.
///
/// Se agrupa por título y no por nota que lo escribe: crear la nota que falta
/// completa el enlace en todas las notas que lo mencionan a la vez, así que
/// esa es la unidad sobre la que se decide.
@freezed
sealed class BrokenLink with _$BrokenLink {
  const factory BrokenLink({
    /// El título como se escribió —el de la primera nota que lo escribió—: con
    /// él se crea la nota que falta.
    required String title,

    /// El título para comparar: recortado y en minúsculas.
    required String normalizedTitle,

    /// Las notas que lo escriben, sin repetir ninguna.
    required List<BrokenLinkSource> sources,
  }) = _BrokenLink;
}
