import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_chapter.dart';

import '../../../support/fake_index_repository.dart';
import '../../../support/wikipedia_fixtures.dart';

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
    // Un texto que no es Markdown —un PDF— va tal cual, en un renglón.
    test('el tramo, en una sola línea', () {
      expect(
        indexChapterPassage(
          '# Roma\n\nLa  república\ncayó.\n\n# Otro',
          2,
          27,
          markdown: false,
        ),
        'Roma La república cayó.',
      );
    });

    test('hasta el final si no tiene fin; vacío si ya no cae en el texto', () {
      expect(indexChapterPassage('abc def', 4, null, markdown: false), 'def');
      expect(indexChapterPassage('abc', 9, null, markdown: true), '');
      expect(indexChapterPassage('abc', -1, 2, markdown: true), '');
      expect(indexChapterPassage('abcdef', 2, 99, markdown: false), 'cdef');
    });

    test('lo largo se corta en una palabra entera, con «…»', () {
      final long = List.filled(600, 'palabra').join(' ');
      final passage = indexChapterPassage(long, 0, null, markdown: true);
      expect(passage.length, lessThanOrEqualTo(kIndexChapterPassageChars + 1));
      expect(passage, endsWith('palabra…'));
      expect(passage.length, greaterThan(kIndexChapterPassageChars * 0.8));
    });

    test('justo en el límite, entero y sin «…»', () {
      final exact = 'a' * kIndexChapterPassageChars;
      expect(indexChapterPassage(exact, 0, null, markdown: false), exact);
    });
  });

  group('el pasaje como se lee (F46, paso 5e)', () {
    // Visto en el emulador: el de «Siglo XX» de Fotosíntesis llegaba al chat
    // como «Siglo XX En 1905, [Frederick Frost Blackman](https://…) …».
    final markdown = wikipediaFotosintesis();
    // Wikipedia une «Siglo» y «XX» con un espacio que no se corta.
    final start = markdown.indexOf(RegExp(r'### Siglo\sXX'));
    final end = markdown.indexOf('## El cloroplasto');

    test('el de «Siglo XX» empieza con su texto, sin el título ni el '
        'Markdown', () {
      final passage = indexChapterPassage(
        markdown,
        start,
        end,
        markdown: true,
        title: 'Siglo XX',
      );

      expect(passage, startsWith('En 1905, Frederick Frost Blackman midió'));
      for (final raw in ['](', 'http', '![', '#', '**', '\n']) {
        expect(passage, isNot(contains(raw)), reason: raw);
      }
      expect(passage.length, lessThanOrEqualTo(kIndexChapterPassageChars + 1));
      // El recorte trae los dos párrafos del capítulo: entran enteros.
      expect(
        passage,
        endsWith('eran la intensidad lumínica y la temperatura.'),
      );
    });

    test('el de «Historia del estudio», más largo que el tope, lleva 2.000 '
        'letras que se leen y no direcciones', () {
      final from = markdown.indexOf('## Historia del estudio');
      final passage = indexChapterPassage(
        markdown,
        from,
        end,
        markdown: true,
        title: 'Historia del estudio de la fotosíntesis',
      );

      expect(passage, startsWith('Ya en la Antigua Grecia, el filósofo'));
      expect(passage, isNot(contains('http')));
      expect(passage, endsWith('…'));
      expect(passage.length, greaterThan(kIndexChapterPassageChars * 0.9));
      expect(passage.length, lessThanOrEqualTo(kIndexChapterPassageChars + 1));
    });

    test('con las fotos y las notas al pie de la página real, el tope cuenta '
        'solo lo que se lee', () {
      const photo =
          '[![](//upload.wikimedia.org/wikipedia/commons/thumb/a/a1/'
          'Hoja_verde_al_sol_con_un_nombre_largo.jpg/'
          '250px-Hoja_verde_al_sol_con_un_nombre_largo.jpg)]'
          '(https://es.wikipedia.org/wiki/Archivo:Hoja.jpg)';
      const sentence =
          'la síntesis de [glucosa](https://es.wikipedia.org/wiki/Glucosa) '
          'procedía de la luz.<sup>[[3]](#cite_note-3)</sup>';
      final text = [
        '### Siglo XX',
        '',
        photo,
        '',
        for (var i = 0; i < 60; i++) sentence,
      ].join('\n');

      final passage = indexChapterPassage(
        text,
        0,
        null,
        markdown: true,
        title: 'Siglo XX',
      );

      expect(passage, startsWith('la síntesis de glucosa procedía de la luz.'));
      expect(passage, isNot(contains('[3]')));
      expect(passage, isNot(contains('upload')));
      // 2.000 letras legibles: casi todo el tope es texto.
      expect(passage.length, greaterThan(kIndexChapterPassageChars * 0.8));
      expect(passage.length, lessThanOrEqualTo(kIndexChapterPassageChars + 1));
    });

    test('un subtítulo de adentro queda separado como una oración', () {
      const text =
          '## Historia\n\nUn comienzo.\n\n### Siglo XX\n\nEn 1905, midió.';
      expect(
        indexChapterPassage(text, 0, null, markdown: true, title: 'Historia'),
        'Un comienzo. Siglo XX. En 1905, midió.',
      );
    });

    test('el título se reconoce con su número delante, sin mayúsculas ni '
        'acentos', () {
      expect(
        indexChapterPassage(
          '## 3. SIGLO XX\nEn 1905.',
          0,
          null,
          markdown: true,
          title: 'Siglo XX',
        ),
        'En 1905.',
      );
      expect(
        indexChapterPassage(
          '1.2 Desarrollo\nEl texto',
          0,
          null,
          markdown: false,
          title: 'Desarrollo',
        ),
        'El texto',
      );
    });

    test('el renglón del título se compara como se lee: un título que es un '
        'enlace también es el título', () {
      expect(
        indexChapterPassage(
          '## [Siglo XX](https://es.wikipedia.org/wiki/Siglo_XX)\nEn 1905.',
          0,
          null,
          markdown: true,
          title: 'Siglo XX',
        ),
        'En 1905.',
      );
    });

    test('si el tramo no empieza con su título, no se saca nada', () {
      // El título de la IA de un PDF no es un renglón del texto.
      expect(
        indexChapterPassage(
          'La fotosíntesis es antigua.\nY sigue.',
          0,
          null,
          markdown: false,
          title: 'Orígenes',
        ),
        'La fotosíntesis es antigua. Y sigue.',
      );
      // Ni uno que termina con el título sin ser un número delante.
      expect(
        indexChapterPassage(
          'Todo el siglo XX\nTexto.',
          0,
          null,
          markdown: false,
          title: 'Siglo XX',
        ),
        'Todo el siglo XX Texto.',
      );
      // Ni un renglón que dice más que el título.
      expect(
        indexChapterPassage(
          'Siglo XX y más\nTexto.',
          0,
          null,
          markdown: true,
          title: 'Siglo XX',
        ),
        'Siglo XX y más Texto.',
      );
    });

    test('un capítulo que es solo su título no tiene nada para el chat', () {
      expect(
        indexChapterPassage(
          '## Siglo XX\n',
          0,
          null,
          markdown: true,
          title: 'Siglo XX',
        ),
        '',
      );
      expect(
        indexChapterPassage(
          '## Siglo XX',
          0,
          null,
          markdown: true,
          title: 'Siglo XX',
        ),
        '',
      );
    });
  });
}
