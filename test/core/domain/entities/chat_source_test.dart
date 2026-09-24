import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';

/// El código de `ChatSource` a JSON y de vuelta (F16, D2): el offset tiene
/// que sobrevivir la vuelta igual que el resto, y un mensaje guardado antes
/// de que existiera —sin esas dos claves— tiene que seguir leyéndose.
void main() {
  test('el offset sobrevive una vuelta completa por JSON', () {
    const source = ChatSource(
      itemId: 'item-1',
      itemTitle: 'Un elemento',
      excerpt: 'El fragmento citado.',
      sourceCharStart: 12,
      sourceCharEnd: 34,
    );

    final decoded = decodeChatSources(encodeChatSources([source]));

    expect(decoded, [source]);
  });

  test('sin offset, viaja como `null` y no como un dato inventado', () {
    const source = ChatSource(
      itemId: 'item-1',
      itemTitle: 'Un elemento',
      excerpt: 'El fragmento citado.',
    );

    final decoded = decodeChatSources(encodeChatSources([source]));

    expect(decoded.single.sourceCharStart, isNull);
    expect(decoded.single.sourceCharEnd, isNull);
  });

  test('un mensaje guardado antes de que el offset existiera se sigue '
      'leyendo, sin él', () {
    const oldJson =
        '[{"itemId":"item-1","itemTitle":"Un elemento", '
        '"excerpt":"citado"}]';

    final decoded = decodeChatSources(oldJson);

    expect(decoded, hasLength(1));
    expect(decoded.single.itemId, 'item-1');
    expect(decoded.single.sourceCharStart, isNull);
    expect(decoded.single.sourceCharEnd, isNull);
  });
}
