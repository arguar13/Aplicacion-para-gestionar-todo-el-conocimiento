import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/chat_source_builder.dart';

/// Función pura, extraída de `LibraryVaultRetriever` (F16, 12b) para que un
/// caso de uso que ya sabe qué elementos usar —sin pasar por una
/// búsqueda— arme el mismo `ChatSource`, con el mismo offset real, sin
/// duplicar la lógica. El grueso de los casos (offset dentro de un chunk,
/// nota manual sin offset, texto principal vs. `searchableText`, truncado)
/// ya está cubierto indirectamente por `library_vault_retriever_test.dart`
/// —acá solo se confirma que la función sirve sola, sin una base detrás.
void main() {
  final now = DateTime(2026, 9, 24, 10);

  KnowledgeItem webItem(String content) => KnowledgeItem(
    id: 'item',
    title: 'Título',
    source: Source(id: 'src', kind: SourceKind.webPage, capturedAt: now),
    processingState: ProcessingState.ready,
    createdAt: now,
    updatedAt: now,
    renditions: [
      Rendition.text(
        id: 'rend',
        itemId: 'item',
        kind: RenditionKind.plainText,
        content: content,
        isPrimary: true,
        createdAt: now,
      ),
    ],
  );

  test('arma el ChatSource con el offset real de la fuente', () {
    final item = webItem('el contenido real de la fuente');

    final source = buildChatSource(item);

    expect(source.itemId, 'item');
    expect(source.itemTitle, 'Título');
    expect(source.excerpt, 'el contenido real de la fuente');
    expect(source.sourceCharStart, 0);
    expect(source.sourceCharEnd, 'el contenido real de la fuente'.length);
  });

  test('una nota manual nunca tiene offset', () {
    final item = KnowledgeItem(
      id: 'nota',
      title: 'Una nota',
      source: Source(id: 'src', kind: SourceKind.manualNote, capturedAt: now),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final source = buildChatSource(item);

    expect(source.sourceCharStart, isNull);
    expect(source.sourceCharEnd, isNull);
  });

  test('excerptLength acota cuánto entra, con el offset acorde', () {
    final item = webItem('0123456789');

    final source = buildChatSource(item, excerptLength: 4);

    expect(source.excerpt, '0123…');
    expect(source.sourceCharStart, 0);
    expect(source.sourceCharEnd, 4);
  });
}
