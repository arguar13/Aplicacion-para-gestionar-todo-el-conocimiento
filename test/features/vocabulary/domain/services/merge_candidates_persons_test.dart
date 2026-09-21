import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/domain/services/hierarchy_suggestions.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';

/// Los candidatos a fusionar entre PERSONAS (F15): además de lo que ya se
/// detecta en un texto, el mismo nombre en otro orden y el mismo apellido con
/// el nombre de pila abreviado.
void main() {
  /// Una persona con su nombre partido, en la categoría de autores.
  VocabularyValueStat person(
    String id,
    String family, {
    String given = '',
    bool institution = false,
    int usage = 1,
    String definition = 'autor',
  }) {
    final name = PersonName(
      family: family,
      given: given,
      isInstitution: institution,
    );
    return VocabularyValueStat(
      id: id,
      label: name.label,
      definitionId: definition,
      definitionName: 'Autor',
      isText: false,
      usage: usage,
      aliasCount: 0,
      person: name,
    );
  }

  /// Una persona que nadie partió: viene entera como apellido.
  VocabularyValueStat unsplit(String id, String label) => VocabularyValueStat(
    id: id,
    label: label,
    definitionId: 'autor',
    definitionName: 'Autor',
    isText: false,
    usage: 1,
    aliasCount: 0,
    person: PersonName(family: label),
  );

  Set<String> pairs(List<MergeCandidate> candidates) => {
    for (final c in candidates) ([c.first.id, c.second.id]..sort()).join('|'),
  };

  MergeCandidateReason reasonOf(List<MergeCandidate> candidates, String pair) =>
      candidates
          .singleWhere(
            (c) => ([c.first.id, c.second.id]..sort()).join('|') == pair,
          )
          .reason;

  group('lo que ya se detecta en un texto', () {
    test('el mismo nombre con otro acento u otras mayúsculas', () {
      final result = findMergeCandidates([
        person('a', 'García Márquez', given: 'Gabriel'),
        person('b', 'GARCIA MARQUEZ', given: 'gabriel'),
        person('c', 'Borges', given: 'Jorge Luis'),
      ]);

      expect(pairs(result), {'a|b'});
      expect(reasonOf(result, 'a|b'), MergeCandidateReason.sameText);
    });

    test('una errata en el nombre', () {
      final result = findMergeCandidates([
        person('a', 'Cortázar', given: 'Julio'),
        person('b', 'Cortazar', given: 'Julo'),
      ]);

      expect(pairs(result), {'a|b'});
    });
  });

  group('el mismo nombre en otro orden', () {
    test(
      'sin partir: «Gabriel García Márquez» y «García Márquez, Gabriel»',
      () {
        final result = findMergeCandidates([
          unsplit('a', 'Gabriel García Márquez'),
          person('b', 'García Márquez', given: 'Gabriel'),
        ]);

        expect(pairs(result), {'a|b'});
        expect(reasonOf(result, 'a|b'), MergeCandidateReason.sameText);
      },
    );

    test('con otro acento y otro orden a la vez', () {
      final result = findMergeCandidates([
        unsplit('a', 'gabriel garcia marquez'),
        person('b', 'García Márquez', given: 'Gabriel'),
      ]);

      expect(pairs(result), {'a|b'});
    });

    test('un nombre de una sola palabra no se compara por orden', () {
      final result = findMergeCandidates([
        unsplit('a', 'Platón'),
        person('b', 'Platón'),
      ]);

      // Es el mismo texto, no otro orden.
      expect(reasonOf(result, 'a|b'), MergeCandidateReason.sameText);
    });
  });

  group('el mismo apellido, con el nombre abreviado', () {
    test('«G.» es una forma de «Gabriel»', () {
      final result = findMergeCandidates([
        person('a', 'García Márquez', given: 'G.'),
        person('b', 'García Márquez', given: 'Gabriel'),
      ]);

      expect(pairs(result), {'a|b'});
      expect(reasonOf(result, 'a|b'), MergeCandidateReason.nameVariant);
    });

    test('con varias iniciales', () {
      final result = findMergeCandidates([
        person('a', 'Tolkien', given: 'J. R. R.'),
        person('b', 'Tolkien', given: 'John Ronald Reuel'),
      ]);

      expect(reasonOf(result, 'a|b'), MergeCandidateReason.nameVariant);
    });

    test('las iniciales pegadas también: «J.R.R.»', () {
      final result = findMergeCandidates([
        person('a', 'Tolkien', given: 'J.R.R.'),
        person('b', 'Tolkien', given: 'John Ronald Reuel'),
      ]);

      expect(reasonOf(result, 'a|b'), MergeCandidateReason.nameVariant);
    });

    test('un nombre más corto: «Gabriel» y «Gabriel José»', () {
      final result = findMergeCandidates([
        person('a', 'García Márquez', given: 'Gabriel'),
        person('b', 'García Márquez', given: 'Gabriel José'),
      ]);

      expect(reasonOf(result, 'a|b'), MergeCandidateReason.nameVariant);
    });

    test('solo una inicial se abrevia: «Gabriel» no es «Gabriela»', () {
      final result = findMergeCandidates([
        person('a', 'García', given: 'Gabriel'),
        person('b', 'García', given: 'Gabriela'),
      ]);

      // Puede salir por su parecido de ortografía, pero no como abreviatura.
      expect(
        result.where((c) => c.reason == MergeCandidateReason.nameVariant),
        isEmpty,
      );
    });

    test('dos nombres distintos con el mismo apellido no son candidatos', () {
      final result = findMergeCandidates([
        person('a', 'García', given: 'Juan'),
        person('b', 'García', given: 'Pedro'),
      ]);

      expect(result, isEmpty);
    });

    test('una inicial que encaja con varias es una pista, no una sospecha', () {
      final result = findMergeCandidates([
        person('a', 'García', given: 'J.'),
        person('b', 'García', given: 'Juan'),
        person('c', 'García', given: 'Julia'),
      ]);

      expect(pairs(result), {'a|b', 'a|c'});
      // «uno contiene al otro»: no se da por seguro.
      expect(reasonOf(result, 'a|b'), MergeCandidateReason.contained);
      expect(reasonOf(result, 'a|c'), MergeCandidateReason.contained);
    });

    test('con y sin nombre de pila: «Borges» y «Borges, Jorge Luis»', () {
      final result = findMergeCandidates([
        person('a', 'Borges'),
        person('b', 'Borges', given: 'Jorge Luis'),
      ]);

      expect(pairs(result), {'a|b'});
      expect(reasonOf(result, 'a|b'), MergeCandidateReason.contained);
    });

    test('una institución no se abrevia', () {
      final result = findMergeCandidates([
        person('a', 'Naciones Unidas', institution: true),
        person('b', 'Naciones Unidas', given: 'N.'),
      ]);

      expect(
        result.where((c) => c.reason == MergeCandidateReason.nameVariant),
        isEmpty,
      );
    });
  });

  group('lo que no mezcla', () {
    test('las personas de dos categorías distintas', () {
      final result = findMergeCandidates([
        person('a', 'García Márquez', given: 'Gabriel'),
        person(
          'b',
          'García Márquez',
          given: 'Gabriel',
          definition: 'otra-categoria',
        ),
      ]);

      expect(result, isEmpty);
    });

    test(
      'un valor que no es texto ni persona —una fecha— no tiene candidatos',
      () {
        const date = VocabularyValueStat(
          id: 'x',
          label: '44 a.C.',
          definitionId: 'fecha',
          definitionName: 'Fecha del hecho',
          isText: false,
          usage: 1,
          aliasCount: 0,
        );
        const other = VocabularyValueStat(
          id: 'y',
          label: '44 a.C',
          definitionId: 'fecha',
          definitionName: 'Fecha del hecho',
          isText: false,
          usage: 1,
          aliasCount: 0,
        );

        expect(findMergeCandidates([date, other]), isEmpty);
      },
    );
  });

  group('agrupar', () {
    test('las variantes de una misma persona quedan en un grupo', () {
      final candidates = findMergeCandidates([
        unsplit('a', 'Gabriel García Márquez'),
        person('b', 'García Márquez', given: 'Gabriel', usage: 5),
        person('c', 'García Márquez', given: 'G.'),
      ]);

      final groups = groupMergeCandidates(candidates);

      expect(groups, hasLength(1));
      expect({for (final v in groups.single.values) v.id}, {'a', 'b', 'c'});
      // Se sugiere conservar la más usada.
      expect(groups.single.suggestedKeep.id, 'b');
    });

    test('una abreviatura es una probable copia; «contiene» no lo es', () {
      final candidates = findMergeCandidates([
        person('a', 'García Márquez', given: 'Gabriel'),
        person('b', 'García Márquez', given: 'G.'),
        person('c', 'García Márquez'),
      ]);

      final group = groupMergeCandidates(candidates).single;

      expect(group.probableDuplicatesOf('a'), contains('b'));
      expect(group.probableDuplicatesOf('a'), isNot(contains('c')));
    });
  });

  group('las personas no tienen jerarquía', () {
    test('«Borges» no se ofrece bajo «Borges, Jorge Luis»', () {
      final candidates = findMergeCandidates([
        person('a', 'Borges'),
        person('b', 'Borges', given: 'Jorge Luis'),
      ]);
      final group = groupMergeCandidates(candidates).single;

      expect(hierarchySuggestionsFor(group), isEmpty);
    });

    test('un texto sí: «Roma» bajo «Roma antigua»', () {
      const roma = VocabularyValueStat(
        id: 'r',
        label: 'Roma',
        definitionId: 'tema',
        definitionName: 'Tema',
        isText: true,
        usage: 1,
        aliasCount: 0,
      );
      const antigua = VocabularyValueStat(
        id: 'ra',
        label: 'Roma antigua',
        definitionId: 'tema',
        definitionName: 'Tema',
        isText: true,
        usage: 1,
        aliasCount: 0,
      );
      final group = groupMergeCandidates(
        findMergeCandidates([roma, antigua]),
      ).single;

      expect(hierarchySuggestionsFor(group), hasLength(1));
    });
  });
}
