import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';

import '../../../../support/time_growth.dart';

/// Partir un libro entero en lo que se lee de una vez lleva segundos en un
/// teléfono: tocar «Escuchar» no puede dejar la interfaz esperándolo.
void main() {
  String stamp(int i) => '[${i ~/ 60}:${(i % 60).toString().padLeft(2, '0')}] ';

  String book(int lines, {bool timestamps = false}) => List.generate(
    lines,
    (i) =>
        '${timestamps ? stamp(i) : ''}'
        'La **revolución** industrial cambió el [mundo](http://x.y) de forma '
        'profunda. Nada volvió a ser igual para los pueblos de la línea $i.',
  ).join('\n');

  group('buildReadableSegmentsOff', () {
    test('un libro largo da los mismos pedazos que partirlo acá', () async {
      final content = book(700);
      expect(content.length, greaterThan(kSegmentsInlineChars));

      expect(
        await buildReadableSegmentsOff(
          content,
          sourceKey: 'r1',
          markdown: true,
        ),
        buildReadableSegments(content, sourceKey: 'r1', markdown: true),
      );
    });

    test('la transcripción larga conserva la marca de tiempo fuera de lo que '
        'se dice, como acá', () async {
      final content = book(700, timestamps: true);

      final off = await buildReadableSegmentsOff(
        content,
        sourceKey: 'r1',
        transcript: true,
      );

      expect(
        off,
        buildReadableSegments(content, sourceKey: 'r1', transcript: true),
      );
      expect(off.first.spoken, startsWith('La '));
    });

    test('no traba el hilo de la interfaz: partirlo acá lo deja sin atender '
        'todo el tiempo que lleva; en otro hilo, una fracción', () async {
      final content = book(6000);

      final inline = await stallShare(
        () async => buildReadableSegments(content, sourceKey: 'r1'),
      );
      final off = await stallShare(
        () => buildReadableSegmentsOff(content, sourceKey: 'r1'),
      );

      expect(inline, greaterThan(0.8));
      expect(off, lessThan(0.5));
    });

    test('un texto corto se parte en el momento, con lo mismo', () async {
      const content = 'Una línea.\nOtra línea, más larga.';

      expect(
        await buildReadableSegmentsOff(content, sourceKey: 'r1'),
        buildReadableSegments(content, sourceKey: 'r1'),
      );
    });
  });

  group('studyReadableDocumentOff', () {
    test('es el mismo documento que studyReadableDocument', () async {
      final content = book(700);
      final text = (
        itemId: 'i1',
        renditionId: 'r1',
        content: content,
        markdown: true,
      );

      final off = await studyReadableDocumentOff(
        text: text,
        title: 'Un libro',
        scopes: const {},
      );

      expect(
        off,
        studyReadableDocument(text: text, title: 'Un libro', scopes: const {}),
      );
    });

    test('la transcripción de un audio o un video también se ofrece entera, '
        'igual que en el hilo de la interfaz (F40)', () async {
      final text = (
        itemId: 'i1',
        renditionId: 'r1',
        content: book(700),
        markdown: false,
      );

      final off = await studyReadableDocumentOff(
        text: text,
        title: 'Un audio',
        scopes: const {},
        transcript: true,
      );

      expect(off.segments, isNotEmpty);
      expect(
        off,
        studyReadableDocument(
          text: text,
          title: 'Un audio',
          scopes: const {},
          transcript: true,
        ),
      );
    });
  });
}
