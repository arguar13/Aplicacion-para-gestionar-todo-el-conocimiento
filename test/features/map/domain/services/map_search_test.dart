import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/map_search_builder.dart';

import 'insights_fixtures.dart';

/// Buscar en el mapa (F44): los temas y los documentos con su comunidad y su
/// tema, para volar hasta ellos sin preguntarle a la base.
void main() {
  MapSearchIndex indexOf(TopicGraphInput input, Map<String, int> of) {
    final map = mapOf(input, of);
    return buildMapSearchIndex(
      graph: map.graph,
      detection: map.detection,
      input: input,
    );
  }

  List<String> idsOf(List<MapSearchEntry> hits) => [
    for (final hit in hits) hit.id,
  ];

  group('el lugar de cada cosa', () {
    test('un tema está en su comunidad y en sí mismo', () {
      final index = indexOf(
        inputOf(
          ['roma', 'grecia'],
          [
            ['roma'],
            ['roma'],
            ['grecia'],
          ],
        ),
        {'roma': 4, 'grecia': 7},
      );

      final roma = index.topic('roma')!;
      expect(roma.kind, MapSearchKind.topic);
      expect(roma.communityId, 4);
      expect(roma.topicValueId, 'roma');
      expect(roma.size, 2);
      expect(index.topic('grecia')!.communityId, 7);
      expect(index.topic('nada'), isNull);
    });

    test('un documento está en la comunidad de la mayoría de sus temas, y '
        'dentro de ella en el más específico: el de menos documentos', () {
      final index = indexOf(
        inputOf(
          ['general', 'chico', 'otro'],
          [
            ['general', 'chico', 'otro'],
            ...repeat(5, ['general']),
            ...repeat(2, ['otro']),
          ],
        ),
        {'general': 1, 'chico': 1, 'otro': 2},
      );

      final document = index.document('i0')!;
      expect(document.kind, MapSearchKind.document);
      expect(document.communityId, 1);
      expect(document.topicValueId, 'chico');
      expect(document.valueIds, ['general', 'chico', 'otro']);
      expect(document.isUnthemed, isFalse);
    });

    test('a igual cantidad de temas, la comunidad más grande; a igual '
        'tamaño, la de menor identidad', () {
      final index = indexOf(
        inputOf(
          ['a', 'b1', 'b2', 'c'],
          [
            ['a', 'b1'],
            ['b1', 'b2'],
            ['a', 'c'],
          ],
        ),
        {'a': 5, 'b1': 3, 'b2': 3, 'c': 1},
      );

      // i0: a (5, un tema) contra b1 (3, dos temas): gana la más grande.
      expect(index.document('i0')!.communityId, 3);
      // i2: a (5) contra c (1), del mismo tamaño: gana la de menor identidad.
      expect(index.document('i2')!.communityId, 1);
      expect(index.document('i2')!.topicValueId, 'c');
    });

    test('un documento sin tema no tiene comunidad ni tema: vive en la '
        'burbuja «Sin tema»', () {
      final index = indexOf(
        inputOf(
          ['roma'],
          [
            ['roma'],
          ],
          unassigned: [
            TopicItem(
              id: 'suelto',
              valueIds: const [],
              title: 'Un suelto',
              isNote: true,
              createdAt: DateTime(2026, 10, 2),
            ),
          ],
        ),
        {'roma': 1},
      );

      final suelto = index.document('suelto')!;
      expect(suelto.isUnthemed, isTrue);
      expect(suelto.communityId, isNull);
      expect(suelto.topicValueId, isNull);
      expect(suelto.isNote, isTrue);
      expect(suelto.createdAt, DateTime(2026, 10, 2));
      expect(idsOf(index.search('suelto')), ['suelto']);
    });
  });

  group('buscar', () {
    /// Temas y documentos con nombres que se parecen.
    MapSearchIndex vault() => indexOf(
      TopicGraphInput(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: inputOf(
          ['aquino', 'tomismo', 'santo', 'roma'],
          const [],
          labels: {
            'aquino': 'Tomás de Aquino',
            'tomismo': 'Tomismo',
            'santo': 'Santo Tomás',
            'roma': 'Roma',
          },
        ).values,
        items: [
          const TopicItem(id: 'd-tomas', valueIds: ['aquino'], title: 'tomás'),
          TopicItem(
            id: 'd-viejo',
            valueIds: const ['roma'],
            title: 'Cartas de Tomás Moro',
            createdAt: DateTime(2026),
          ),
          TopicItem(
            id: 'd-nuevo',
            valueIds: const ['roma'],
            title: 'Sermones de Tomás',
            createdAt: DateTime(2026, 6),
          ),
          const TopicItem(
            id: 'd-orden',
            valueIds: ['roma'],
            title: 'De Aquino, la suma de Tomás',
          ),
        ],
        relations: const [],
      ),
      {'aquino': 1, 'tomismo': 1, 'santo': 1, 'roma': 2},
    );

    test('sin acentos ni mayúsculas, y lo que mejor coincide primero: igual, '
        'empieza así, una palabra empieza así, lo contiene', () {
      final hits = vault().search('TOMAS');

      expect(idsOf(hits), [
        // Igual.
        'd-tomas',
        // Empieza así: «Tomás de Aquino».
        'aquino',
        // Una palabra empieza así: los temas antes que los documentos, y de
        // los documentos el más nuevo primero; los que no tienen fecha, al
        // final.
        'santo',
        'd-nuevo',
        'd-viejo',
        'd-orden',
      ]);
      // «Tomismo» no tiene «tomas».
      expect(idsOf(hits), isNot(contains('tomismo')));
    });

    test('con varias palabras, también lo que las tiene todas en cualquier '
        'orden, después de lo que las tiene juntas', () {
      // Las dos palabras, en cualquier orden: el tema antes que el documento.
      final hits = vault().search('aquino tomás');
      expect(idsOf(hits), ['aquino', 'd-orden']);

      // Juntas: lo que empieza así antes de lo que tiene una palabra así.
      expect(idsOf(vault().search('de aquino')), ['d-orden', 'aquino']);
    });

    test('lo que contiene sin empezar una palabra también sale, al final', () {
      final hits = vault().search('mism');

      expect(idsOf(hits), ['tomismo']);
    });

    test('nada que buscar no da nada, y hay un tope', () {
      final index = vault();

      expect(index.search('   '), isEmpty);
      expect(index.search('o', limit: 3), hasLength(3));
      expect(index.search('zzz'), isEmpty);
    });
  });

  test('el índice tiene cada tema y cada documento una vez: los temas por '
      'nombre y después los documentos por título', () {
    final index = indexOf(
      inputOf(
        ['b', 'a'],
        [
          ['a'],
          ['b'],
        ],
        unassigned: const [
          TopicItem(id: 'suelto', valueIds: [], title: 'Zeta'),
        ],
      ),
      {'a': 1, 'b': 2},
    );

    expect(idsOf(index.entries), ['a', 'b', 'i0', 'i1', 'suelto']);
    expect(index.document('i1')!.topicValueId, 'b');
  });
}
