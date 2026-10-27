import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_text_provider.dart';

/// Un texto que se ofrece entero para escuchar —un libro, un PDF—: corto, se
/// parte ahí mismo; largo, fuera del hilo de la pantalla, y mientras tanto no
/// se ofrece nada.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  ReadableText text(String content) => (
    id: 'study:r1',
    title: 'Un libro',
    sourceKey: 'r1',
    content: content,
    markdown: true,
  );

  test('un texto corto se parte enseguida, igual que siempre', () {
    const content = '# Título\n\nUna **línea**.\nOtra línea.';

    final document = container.read(readableTextProvider(text(content)))!;

    expect(document.id, 'study:r1');
    expect(document.title, 'Un libro');
    expect(document.scopes, isEmpty);
    expect(
      document.segments,
      buildReadableSegments(content, sourceKey: 'r1', markdown: true),
    );
    expect(document.segments.map((s) => s.spoken), [
      'Título',
      'Una línea.',
      'Otra línea.',
    ]);
  });

  test('uno largo se parte aparte: hasta tenerlo no se ofrece nada, y '
      'después es el mismo documento', () async {
    final content = List.filled(
      kSegmentsInlineChars ~/ 20 + 1,
      'Una línea de texto.',
    ).join('\n');
    expect(content.length, greaterThan(kSegmentsInlineChars));
    final key = text(content);
    final subscription = container.listen(readableTextProvider(key), (_, _) {});
    addTearDown(subscription.close);

    expect(subscription.read(), isNull);

    ReadableDocument? document;
    for (var i = 0; i < 200 && document == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      document = subscription.read();
    }

    expect(document, isNotNull);
    expect(
      document!.segments,
      buildReadableSegments(content, sourceKey: 'r1', markdown: true),
    );
  });

  test(
    'si nadie lo mira ya cuando termina de partirse, no pasa nada',
    () async {
      final content = List.filled(
        kSegmentsInlineChars ~/ 20 + 1,
        'Una línea de texto.',
      ).join('\n');
      final subscription = container.listen(
        readableTextProvider(text(content)),
        (_, _) {},
      );

      expect(subscription.read(), isNull);
      subscription.close();
      // Lo que termina de partirse después no tiene a quién avisarle.
      await Future<void>.delayed(const Duration(seconds: 2));
    },
  );

  test('el mismo texto es una sola cuenta mientras alguien lo mire', () {
    final subscription = container.listen(
      readableTextProvider(text('Hola.')),
      (_, _) {},
    );
    addTearDown(subscription.close);

    expect(
      container.read(readableTextProvider(text('Hola.'))),
      same(subscription.read()),
    );
  });
}
