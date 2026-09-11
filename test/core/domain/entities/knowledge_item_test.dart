import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);

  final source = Source(
    id: 'src-1',
    kind: SourceKind.youtube,
    capturedAt: now,
    url: 'https://youtube.com/watch?v=abc',
  );

  KnowledgeItem buildItem({
    List<Rendition> renditions = const [],
    ProcessingState state = ProcessingState.ready,
  }) => KnowledgeItem(
    id: 'item-1',
    title: 'Una charla',
    source: source,
    processingState: state,
    createdAt: now,
    updatedAt: now,
    renditions: renditions,
  );

  Rendition text(String id, String content, {bool isPrimary = false}) =>
      Rendition.text(
        id: id,
        itemId: 'item-1',
        kind: RenditionKind.plainText,
        content: content,
        isPrimary: isPrimary,
        createdAt: now,
      );

  Rendition file(String id, {bool isPrimary = false}) => Rendition.file(
    id: id,
    itemId: 'item-1',
    kind: RenditionKind.image,
    relativePath: 'imagenes/$id.png',
    isPrimary: isPrimary,
    createdAt: now,
  );

  group('primaryRendition', () {
    test('sin formas, no hay ninguna que mostrar', () {
      expect(buildItem().primaryRendition, isNull);
    });

    test('devuelve la marcada como principal, esté donde esté en la lista', () {
      final item = buildItem(
        renditions: [
          text('a', 'primera'),
          text('b', 'la buena', isPrimary: true),
          text('c', 'tercera'),
        ],
      );

      expect(item.primaryRendition?.renditionId, 'b');
    });

    test('si ninguna está marcada, cae en la primera', () {
      // Mostrar algo imperfecto es mejor que dejar una pantalla en blanco
      // por una bandera que quedó sin poner.
      final item = buildItem(
        renditions: [text('a', 'primera'), text('b', 'segunda')],
      );

      expect(item.primaryRendition?.renditionId, 'a');
    });
  });

  group('searchableText', () {
    test('junta el texto de todas las formas que lo tienen', () {
      final item = buildItem(
        renditions: [
          text('a', 'la transcripción menciona enzimas'),
          text('b', 'el resumen menciona catalizadores'),
        ],
      );

      expect(item.searchableText, contains('enzimas'));
      expect(item.searchableText, contains('catalizadores'));
    });

    test('las formas que son archivos no aportan nada', () {
      // Una imagen se vuelve buscable recién cuando el reconocimiento de
      // texto produce su propia forma de texto.
      final item = buildItem(
        renditions: [file('img'), text('a', 'el único texto')],
      );

      expect(item.searchableText, 'el único texto');
    });

    test('sin formas de texto, queda vacío en vez de null', () {
      expect(buildItem(renditions: [file('img')]).searchableText, isEmpty);
      expect(buildItem().searchableText, isEmpty);
    });
  });

  group('isBeingProcessed', () {
    test('es cierto mientras está en la cola o en curso', () {
      expect(
        buildItem(state: ProcessingState.pending).isBeingProcessed,
        isTrue,
      );
      expect(
        buildItem(state: ProcessingState.processing).isBeingProcessed,
        isTrue,
      );
    });

    test('deja de serlo al terminar, con éxito o sin él', () {
      expect(buildItem().isBeingProcessed, isFalse);
      // Un fallo tampoco es "en proceso": el elemento existe con lo que se
      // pudo obtener, y la conversión se puede reintentar cuando el usuario
      // quiera.
      expect(
        buildItem(state: ProcessingState.failed).isBeingProcessed,
        isFalse,
      );
    });
  });

  group('Rendition', () {
    test('las dos variantes responden a los mismos datos comunes', () {
      final t = text('a', 'contenido', isPrimary: true);
      final f = file('b', isPrimary: true);

      expect(t.renditionId, 'a');
      expect(f.renditionId, 'b');
      expect(t.primary, isTrue);
      expect(f.primary, isTrue);
      expect(t.renditionKind, RenditionKind.plainText);
      expect(f.renditionKind, RenditionKind.image);
    });

    test('solo la de texto aporta texto buscable', () {
      expect(text('a', 'algo').searchableText, 'algo');
      expect(file('b').searchableText, isNull);
    });

    test('una forma no marcada como principal lo informa', () {
      expect(text('a', 'x').primary, isFalse);
      expect(file('b').primary, isFalse);
    });
  });
}
