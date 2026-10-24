import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_page_segments.dart';

ReadableSegment _segment(int start, int end) =>
    ReadableSegment(sourceKey: 'r', start: start, end: end, spoken: '$start');

void main() {
  // Tres páginas con un hueco entre ellas, como las que parte
  // `readerPageRanges`.
  const pages = [
    (start: 0, end: 100),
    (start: 110, end: 200),
    (start: 210, end: 300),
  ];

  String key(int page) => 'libro:page:$page';

  List<ReadableSegment> carry(
    List<ReadableSegment> segments, {
    int from = 0,
    int until = 3,
  }) =>
      readerPageSegments(segments, pages, from: from, until: until, keyOf: key);

  test('cada pedazo cae en su página, con la posición contada desde su '
      'comienzo y el nombre de esa página', () {
    final carried = carry([
      _segment(10, 20),
      _segment(120, 140),
      _segment(250, 260),
    ]);

    expect(carried.map((s) => (s.sourceKey, s.start, s.end)), [
      ('libro:page:0', 10, 20),
      ('libro:page:1', 10, 30),
      ('libro:page:2', 40, 50),
    ]);
    expect(carried.map((s) => s.spoken), ['10', '120', '250']);
  });

  test('uno que empieza justo donde empieza una página cae en ella, no en la '
      'anterior', () {
    final carried = carry([
      _segment(0, 5),
      _segment(110, 115),
      _segment(210, 215),
    ]);

    expect(carried.map((s) => (s.sourceKey, s.start)), [
      ('libro:page:0', 0),
      ('libro:page:1', 0),
      ('libro:page:2', 0),
    ]);
  });

  test('solo las páginas pedidas: las demás quedan afuera', () {
    final carried = carry(
      [_segment(10, 20), _segment(120, 140), _segment(250, 260)],
      from: 1,
      until: 2,
    );

    expect(carried.map((s) => s.sourceKey), ['libro:page:1']);
  });

  test('uno que cruza el final de su página se corta ahí', () {
    final carried = carry([_segment(90, 150)]);

    expect(carried.single.sourceKey, 'libro:page:0');
    expect(carried.single.end, 100);
  });

  test('uno que cae entre dos páginas, o después de la última, no está en '
      'ninguna', () {
    expect(carry([_segment(102, 108), _segment(305, 310)]), isEmpty);
  });

  test('sin páginas, nada', () {
    expect(
      readerPageSegments(
        [_segment(0, 5)],
        const [],
        from: 0,
        until: 0,
        keyOf: key,
      ),
      isEmpty,
    );
  });
}
