import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';

/// Un elemento de prueba con procedencia completa.
///
/// Compartido entre las pruebas de los tres exportadores: los tres verifican
/// básicamente lo mismo —que el título, la procedencia y el contenido lleguen
/// al archivo— sobre elementos con la misma forma.
KnowledgeItem sampleKnowledgeItem({
  String title = 'La estructura de las revoluciones científicas',
  String? subtitle = 'Thomas Kuhn',
  String? notes,
  DateTime? capturedAt,
  String? url = 'https://ejemplo.org/kuhn',
  String? authorName = 'Thomas Kuhn',
  String? authorUrl,
  DateTime? publishedAt,
  List<Tag> tags = const [],
  List<Rendition> renditions = const [],
}) {
  final captured = capturedAt ?? DateTime(2026, 9, 11, 10);

  return KnowledgeItem(
    id: 'item-1',
    title: title,
    subtitle: subtitle,
    notes: notes,
    source: Source(
      id: 'src-1',
      kind: SourceKind.webPage,
      capturedAt: captured,
      url: url,
      authorName: authorName,
      authorUrl: authorUrl,
      publishedAt: publishedAt,
    ),
    processingState: ProcessingState.ready,
    createdAt: captured,
    updatedAt: captured,
    tags: tags,
    renditions: renditions,
  );
}

/// Una forma de texto de ejemplo, la que produce casi cualquier transformador.
Rendition sampleTextRendition(
  String content, {
  String id = 'rend-1',
  bool isPrimary = true,
}) => Rendition.text(
  id: id,
  itemId: 'item-1',
  kind: RenditionKind.markdown,
  content: content,
  isPrimary: isPrimary,
  createdAt: DateTime(2026, 9, 11, 10),
);
