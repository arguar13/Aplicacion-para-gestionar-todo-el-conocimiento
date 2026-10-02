import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';
import 'package:sinapsis/core/util/transcript_sync.dart';

void main() {
  const content = '[0:00] No hay intervención\n[0:14] docente ahí.';
  const timings = [
    TimedWord('No', 100),
    TimedWord('hay', 400),
    TimedWord('intervención', 700),
    TimedWord('docente', 14100),
    TimedWord('ahí.', 14600),
  ];

  String textOf(String content, SyncSpan? span) =>
      span == null ? '' : content.substring(span.start, span.end);

  group('palabra por palabra, con los tiempos medidos', () {
    final sync = TranscriptSync.build(content, timings);

    test('en cada momento, la palabra que se está diciendo', () {
      expect(sync.isWordLevel, isTrue);
      expect(sync.at(Duration.zero), isNull);
      expect(
        textOf(content, sync.at(const Duration(milliseconds: 450))),
        'hay',
      );
      expect(
        textOf(content, sync.at(const Duration(milliseconds: 14300))),
        'docente',
      );
      expect(textOf(content, sync.at(const Duration(minutes: 3))), 'ahí.');
    });

    test('las marcas de cada renglón no son palabras dichas', () {
      expect(sync.spans.map((s) => content.substring(s.start, s.end)), [
        'No',
        'hay',
        'intervención',
        'docente',
        'ahí.',
      ]);
    });

    test('tocar una palabra da su momento; entre palabras, el de la '
        'siguiente', () {
      final tapped = content.indexOf('docente') + 2;
      expect(sync.atOffset(tapped)?.startMs, 14100);
      expect(sync.atOffset(content.indexOf(' hay'))?.startMs, 400);
    });
  });

  test('después de "Quitar marcas de tiempo", siguen sirviendo', () {
    const stripped = 'No hay intervención\ndocente ahí.';
    final sync = TranscriptSync.build(stripped, timings);

    expect(
      textOf(stripped, sync.at(const Duration(milliseconds: 14650))),
      'ahí.',
    );
    expect(sync.spans, hasLength(5));
  });

  test('una palabra corregida a mano queda sin resaltar, y el resto sigue '
      'en su lugar', () {
    const edited = '[0:00] No hay intervenciones\n[0:14] docente ahí.';
    final sync = TranscriptSync.build(edited, timings);

    expect(sync.spans.map((s) => edited.substring(s.start, s.end)), [
      'No',
      'hay',
      'docente',
      'ahí.',
    ]);
    expect(
      textOf(edited, sync.at(const Duration(milliseconds: 14200))),
      'docente',
    );
  });

  test('sin tiempos —una transcripción de antes—, renglón por renglón con '
      'su marca: lo que se sabe con certeza', () {
    final sync = TranscriptSync.build(content, const []);

    expect(sync.isWordLevel, isFalse);
    expect(
      textOf(content, sync.at(const Duration(seconds: 3))),
      'No hay intervención',
    );
    expect(
      textOf(content, sync.at(const Duration(seconds: 20))),
      'docente ahí.',
    );
  });

  test('las marcas de más de una hora se leen bien', () {
    const long = '[59:58] antes\n[1:00:02] después';
    final sync = TranscriptSync.build(long, const []);

    expect(
      textOf(long, sync.at(const Duration(minutes: 60, seconds: 1))),
      'antes',
    );
    expect(
      textOf(long, sync.at(const Duration(hours: 1, seconds: 2))),
      'después',
    );
  });

  test('un texto sin marcas ni tiempos no tiene nada que seguir', () {
    expect(
      TranscriptSync.build('Una nota cualquiera.', const []).isEmpty,
      isTrue,
    );
  });
}
