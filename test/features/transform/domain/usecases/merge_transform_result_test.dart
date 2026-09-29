import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/domain/usecases/merge_transform_result.dart';

void main() {
  final at = DateTime(2026, 9, 29);

  final original = KnowledgeItem(
    id: 'a',
    title: 'dQw4w9WgXcQ',
    source: Source(
      id: 's',
      kind: SourceKind.youtube,
      capturedAt: at,
      url: 'https://youtu.be/dQw4w9WgXcQ',
    ),
    processingState: ProcessingState.processing,
    createdAt: at,
    updatedAt: at,
  );

  final transcript = Rendition.text(
    id: 'r',
    itemId: 'a',
    kind: RenditionKind.markdown,
    content: '[0:00] Hola',
    isPrimary: true,
    createdAt: at,
  );

  final enriched = original.copyWith(
    title: 'Título real',
    subtitle: 'Un canal',
    source: original.source.copyWith(
      authorName: 'Un canal',
      originalFilePath: 'audio/a.m4a',
    ),
    renditions: [transcript],
  );

  test('lo que trajo el transformador entra si el usuario no lo tocó', () {
    final merged = mergeTransformResult(
      original: original,
      enriched: enriched,
      current: original,
    );

    expect(merged.title, 'Título real');
    expect(merged.subtitle, 'Un canal');
    expect(merged.source.authorName, 'Un canal');
    expect(merged.source.originalFilePath, 'audio/a.m4a');
    expect(merged.renditions, [transcript]);
  });

  test('lo que el usuario cambió mientras tanto gana', () {
    // Le puso título a mano mientras el video se procesaba: vale más que el
    // que trajo YouTube.
    final current = original.copyWith(
      title: 'El himno que me pasó mi mamá',
      source: original.source.copyWith(authorName: 'Coro parroquial'),
    );

    final merged = mergeTransformResult(
      original: original,
      enriched: enriched,
      current: current,
    );

    expect(merged.title, 'El himno que me pasó mi mamá');
    expect(merged.source.authorName, 'Coro parroquial');
    // Lo que el usuario no tocó sigue entrando.
    expect(merged.subtitle, 'Un canal');
    expect(merged.renditions, [transcript]);
  });

  test('lo que un transformador no toca sale siempre de la versión '
      'actual', () {
    final current = original.copyWith(notes: 'Para la reunión del jueves');

    final merged = mergeTransformResult(
      original: original,
      enriched: enriched,
      current: current,
    );

    expect(merged.notes, 'Para la reunión del jueves');
  });
}
