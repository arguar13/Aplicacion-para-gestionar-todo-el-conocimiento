import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';

part 'knowledge_item.freezed.dart';

/// Una cosa guardada: el centro de todo.
///
/// Es un agregado, no una fila: trae su [Source] y sus [renditions] ya
/// cargadas. En la base esas tres cosas viven en tablas separadas, y está
/// bien que así sea; pero a quien lo usa no le sirve un elemento sin saber de
/// dónde vino ni en qué forma está, así que el repositorio los junta antes de
/// entregarlo.
///
/// [title] y [subtitle] son dos niveles y no uno porque el requisito de
/// filtrar por ambos es explícito, y porque distinguen bien cosas que un solo
/// campo confunde: un video y su canal, un capítulo y su libro.
@freezed
sealed class KnowledgeItem with _$KnowledgeItem {
  const factory KnowledgeItem({
    required String id,
    required String title,
    required Source source,
    required ProcessingState processingState,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// Las formas en que existe este contenido. Puede estar vacía mientras la
    /// conversión está en la cola: el elemento se guarda enseguida, con su
    /// enlace y su título, y la transcripción llega después.
    @Default(<Rendition>[]) List<Rendition> renditions,
    @Default(<Tag>[]) List<Tag> tags,
    String? subtitle,

    /// Lo que escribió el usuario sobre esto, aparte del contenido en sí.
    String? notes,
  }) = _KnowledgeItem;

  const KnowledgeItem._();

  /// La forma que corresponde mostrar por defecto.
  ///
  /// Si ninguna está marcada como principal, cae en la primera que haya:
  /// mostrar algo imperfecto es mejor que mostrar una pantalla vacía por una
  /// bandera que quedó sin poner.
  Rendition? get primaryRendition {
    if (renditions.isEmpty) return null;
    return renditions.firstWhere(
      (r) => r.primary,
      orElse: () => renditions.first,
    );
  }

  /// El texto completo de este elemento, para el índice de búsqueda.
  ///
  /// Concatena las formas que tienen texto; las que son archivos no aportan
  /// nada acá (una imagen se vuelve buscable recién cuando el reconocimiento
  /// de texto produce su propia rendition).
  String get searchableText =>
      renditions.map((r) => r.searchableText).whereType<String>().join('\n\n');

  /// Si todavía se está trabajando sobre esto.
  bool get isBeingProcessed =>
      processingState == ProcessingState.pending ||
      processingState == ProcessingState.processing;
}
