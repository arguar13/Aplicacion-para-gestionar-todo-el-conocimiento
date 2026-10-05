import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';

/// Lo puro de «Crear con IA» (F30).
void main() {
  group('notebookTopicQuery', () {
    test('busca de qué trata, no para qué es', () {
      expect(notebookTopicQuery('mi tesis sobre Roma'), 'Roma');
      expect(
        notebookTopicQuery('Apuntes para el parcial de la Revolución Francesa'),
        'Revolución Francesa',
      );
    });

    test('si solo dice para qué es, busca eso: es lo único que hay', () {
      expect(notebookTopicQuery('mi tesis'), 'tesis');
    });

    test('sin palabras de contenido, nada', () {
      expect(notebookTopicQuery('de la'), isEmpty);
    });
  });

  group('notebookNameFrom', () {
    test('lo escrito, con mayúscula y sin espacios de más', () {
      expect(
        notebookNameFrom('  mi tesis   sobre Roma '),
        'Mi tesis sobre Roma',
      );
    });

    test('no pasa de 60 caracteres', () {
      final name = notebookNameFrom(List.filled(20, 'palabra').join(' '));
      expect(name.length, lessThanOrEqualTo(60));
      expect(name, endsWith('…'));
    });
  });

  group('fuseRankings', () {
    test('lo que encuentran las dos búsquedas sube', () {
      expect(
        fuseRankings([
          ['a', 'b', 'c'],
          ['c', 'd'],
        ]),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('a igual puntaje, el orden de la primera lista', () {
      expect(
        fuseRankings([
          ['a', 'b'],
          ['b', 'a'],
        ]),
        ['a', 'b'],
      );
    });

    test('una lista vacía no cambia la otra', () {
      expect(
        fuseRankings([
          ['a', 'b'],
          <String>[],
        ]),
        ['a', 'b'],
      );
    });
  });

  group('parseNotebookPicks', () {
    test('los números de la lista, desde 0, sin los que no estaban', () {
      expect(parseNotebookPicks('VAN: 1, 3, 9', count: 4), {0, 2});
    });

    test('«ninguno» es ninguno, no «no se pudo leer»', () {
      expect(parseNotebookPicks('VAN: ninguno', count: 4), isEmpty);
    });

    test('tolera Markdown y texto alrededor', () {
      expect(
        parseNotebookPicks('Estos son:\n**VAN:** 2 y 4\nListo.', count: 4),
        {1, 3},
      );
    });

    test('sin una línea VAN, no se pudo leer', () {
      expect(parseNotebookPicks('Creo que el 1 y el 2.', count: 4), isNull);
    });
  });

  test('se propone marcado si lo encontraron las palabras o se parece mucho '
      'por sentido', () {
    NotebookCandidate candidate({bool text = false, double? similarity}) =>
        NotebookCandidate(
          itemId: 'a',
          title: 'A',
          excerpt: '',
          kind: SourceKind.webPage,
          matchedText: text,
          similarity: similarity,
        );

    expect(candidate(text: true).likely, isTrue);
    expect(candidate(similarity: kNotebookStrongSimilarity).likely, isTrue);
    expect(candidate(similarity: kNotebookMinSimilarity).likely, isFalse);
    expect(candidate().likely, isFalse);
  });
}
