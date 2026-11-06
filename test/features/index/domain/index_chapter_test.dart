import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_chapter.dart';

import '../../../support/fake_index_repository.dart';

/// Lo que hace falta de un capítulo para hacer algo con él (F46, paso 4): su
/// tramo en el texto, qué título es entre los iguales y su pasaje para el
/// chat.
void main() {
  // Cada capítulo empieza en i * 100 (ver `indexChapters`).
  final entries = indexChapters('d', [
    (1, 'La Monarquía'),
    (2, 'Rómulo'),
    (3, 'La loba'),
    (2, 'Numa'),
    (1, 'La República'),
    (2, 'Referencias'),
    (1, 'Referencias'),
  ]);

  group('el tramo de un capítulo', () {
    test('llega hasta el siguiente de su nivel, con sus subcapítulos '
        'adentro', () {
      expect(indexChapterSpan(entries, entries[1]), (start: 100, end: 300));
      expect(indexChapterSpan(entries, entries[0]), (start: 0, end: 400));
    });

    test('o hasta uno de nivel más alto', () {
      expect(indexChapterSpan(entries, entries[3]), (start: 300, end: 400));
      expect(indexChapterSpan(entries, entries[2]), (start: 200, end: 300));
    });

    test('el último llega hasta el final del texto', () {
      expect(indexChapterSpan(entries, entries.last), (start: 600, end: null));
    });

    test('un capítulo siguiente sin lugar no lo corta: sigue buscando', () {
      final lost = [
        ...entries.take(1),
        entries[4].copyWith(textStart: null, textEnd: null, textPage: null),
        ...entries.skip(5),
      ];
      expect(indexChapterSpan(lost, lost[0]), (start: 0, end: 600));
    });

    test('«Texto completo» es el texto entero; una imagen y un capítulo sin '
        'lugar no tienen tramo', () {
      expect(
        indexChapterSpan([indexWholeText('d', 1)], indexWholeText('d', 1)),
        (start: 0, end: null),
      );
      final image = indexImage('d', 9, position: 0);
      expect(indexChapterSpan([image], image), isNull);
      const lost = IndexEntry(
        key: 5,
        documentId: 'd',
        origin: IndexEntryOrigin.bookmark,
        level: 1,
        position: 0,
        title: 'Sin ubicar',
      );
      expect(indexChapterSpan([lost], lost), isNull);
    });
  });

  group('qué título es entre los iguales', () {
    test('cuenta los anteriores con el mismo título, sin mayúsculas ni '
        'acentos', () {
      expect(indexHeadingOccurrence(entries, entries[5]), 0);
      expect(indexHeadingOccurrence(entries, entries[6]), 1);
      final folded = [
        ...entries,
        indexChapters('d', [(1, 'REFERÉNCIAS:')], firstKey: 50).single,
      ];
      expect(indexHeadingOccurrence(folded, folded.last), 2);
    });

    test('las imágenes con el mismo título no cuentan', () {
      final withImage = [
        indexImage('d', 40, position: 0, title: 'Referencias'),
        ...entries,
      ];
      expect(indexHeadingOccurrence(withImage, entries[6]), 1);
    });
  });

  group('el pasaje para el chat', () {
    test('el tramo, en una sola línea', () {
      expect(
        indexChapterPassage('# Roma\n\nLa  república\ncayó.\n\n# Otro', 2, 27),
        'Roma La república cayó.',
      );
    });

    test('hasta el final si no tiene fin; vacío si ya no cae en el texto', () {
      expect(indexChapterPassage('abc def', 4, null), 'def');
      expect(indexChapterPassage('abc', 9, null), '');
      expect(indexChapterPassage('abc', -1, 2), '');
      expect(indexChapterPassage('abcdef', 2, 99), 'cdef');
    });

    test('lo largo se corta en una palabra entera, con «…»', () {
      final long = List.filled(600, 'palabra').join(' ');
      final passage = indexChapterPassage(long, 0, null);
      expect(passage.length, lessThanOrEqualTo(kIndexChapterPassageChars + 1));
      expect(passage, endsWith('palabra…'));
      expect(passage.length, greaterThan(kIndexChapterPassageChars * 0.8));
    });

    test('justo en el límite, entero y sin «…»', () {
      final exact = 'a' * kIndexChapterPassageChars;
      expect(indexChapterPassage(exact, 0, null), exact);
    });
  });
}
