import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/domain/services/merge_candidates.dart';

VocabularyValueStat stat(
  String id,
  String label, {
  String definition = 'def',
  int usage = 1,
  bool isText = true,
}) => VocabularyValueStat(
  id: id,
  label: label,
  definitionId: definition,
  definitionName: definition,
  isText: isText,
  usage: usage,
  aliasCount: 0,
);

/// Los pares encontrados como `{id1|id2}` ordenados, para comparar sin
/// depender de cuál quedó primero.
Set<String> pairs(List<MergeCandidate> candidates) => {
  for (final c in candidates) ([c.first.id, c.second.id]..sort()).join('|'),
};

void main() {
  group('findMergeCandidates', () {
    test('el mismo texto con otro acento o mayúsculas', () {
      final result = findMergeCandidates([
        stat('a', 'Canción'),
        stat('b', 'cancion'),
        stat('c', 'Otra cosa'),
      ]);

      expect(pairs(result), {'a|b'});
      expect(result.single.reason, MergeCandidateReason.sameText);
    });

    test('un nombre que es otro con más palabras', () {
      final result = findMergeCandidates([
        stat('a', 'Roma'),
        stat('b', 'Roma antigua'),
        stat('c', 'Antigua Roma'),
        stat('d', 'Egipto'),
      ]);

      expect(pairs(result), {'a|b', 'a|c'});
      expect(
        result.every((c) => c.reason == MergeCandidateReason.contained),
        isTrue,
      );
    });

    test('por palabras enteras: "Arte" no está dentro de "Artesanía"', () {
      final result = findMergeCandidates([
        stat('a', 'Arte'),
        stat('b', 'Artesanía'),
      ]);

      expect(result, isEmpty);
    });

    test('una errata: una letra de menos, de más o cambiada', () {
      final result = findMergeCandidates([
        stat('a', 'Filosofía'),
        stat('b', 'Filosofa'), // una letra de menos
        stat('c', 'Historia'),
        stat('d', 'Historiaa'), // una de más
        stat('e', 'Politica'),
        stat('f', 'Politaca'), // una cambiada
      ]);

      expect(pairs(result), {'a|b', 'c|d', 'e|f'});
      expect(
        result.every((c) => c.reason == MergeCandidateReason.similarSpelling),
        isTrue,
      );
    });

    test('un cambio de orden de dos letras cuenta como un solo error', () {
      final result = findMergeCandidates([
        stat('a', 'Platon'),
        stat('b', 'Palton'),
      ]);

      expect(pairs(result), {'a|b'});
    });

    test('nombres largos toleran dos errores; cortos, uno', () {
      final largos = findMergeCandidates([
        stat('a', 'Renacimiento'),
        stat('b', 'Renasimiento'), // 1
        stat('c', 'Renasimientu'), // 2 respecto de a
      ]);
      expect(pairs(largos), containsAll({'a|b', 'a|c', 'b|c'}));

      final cortos = findMergeCandidates([
        stat('a', 'Grecia'),
        stat('b', 'Gracio'), // 2 errores en 6 letras: demasiado
      ]);
      expect(cortos, isEmpty);
    });

    test('con menos de 5 letras no hay errata: son nombres distintos', () {
      final result = findMergeCandidates([
        stat('a', 'Roma'),
        stat('b', 'Rome'),
        stat('c', 'IA'),
        stat('d', 'IB'),
      ]);

      expect(result, isEmpty);
    });

    test('los números no se toman por erratas: "Siglo 20" y "Siglo 21"', () {
      final result = findMergeCandidates([
        stat('a', 'Siglo 20'),
        stat('b', 'Siglo 21'),
      ]);

      expect(result, isEmpty);
    });

    test('solo compara dentro de una misma categoría', () {
      final result = findMergeCandidates([
        stat('a', 'Roma', definition: 'region'),
        stat('b', 'roma', definition: 'ciudad'),
      ]);

      expect(result, isEmpty);
    });

    test('una categoría que no es de texto no tiene candidatos', () {
      final result = findMergeCandidates([
        stat('a', '44 a.C.', isText: false),
        stat('b', '44 a c', isText: false),
      ]);

      expect(result, isEmpty);
    });

    test('un par que cumple más de una razón aparece una sola vez', () {
      // "Guerra" y "Guerras": una letra de más, y de paso mismo texto salvo
      // la ese. Es un solo par.
      final result = findMergeCandidates([
        stat('a', 'Guerra'),
        stat('b', 'Guerras'),
      ]);

      expect(result, hasLength(1));
    });

    test('ordenados por uso combinado, los que más limpian primero', () {
      final result = findMergeCandidates([
        stat('a', 'Filosofía'),
        stat('b', 'filosofia', usage: 2),
        stat('c', 'Historia', usage: 20),
        stat('d', 'historia', usage: 30),
        stat('e', 'Política', usage: 5),
        stat('f', 'politica', usage: 5),
      ]);

      expect(result.map((c) => c.combinedUsage), [50, 10, 3]);
    });

    test('el orden no depende del de entrada', () {
      final input = [
        stat('a', 'Filosofía', usage: 3),
        stat('b', 'filosofia', usage: 3),
        stat('c', 'Historia', usage: 3),
        stat('d', 'historia', usage: 3),
        stat('e', 'Roma'),
        stat('f', 'Roma antigua', usage: 2),
      ];

      final forward = findMergeCandidates(input);
      final backward = findMergeCandidates(input.reversed.toList());

      String key(MergeCandidate c) =>
          ([c.first.id, c.second.id]..sort()).join('|');
      expect(backward.map(key), forward.map(key));
    });

    test('sin valores no hay candidatos', () {
      expect(findMergeCandidates(const []), isEmpty);
    });

    test('el más usado es el que conviene conservar; a igual uso, el más '
        'corto', () {
      final byUsage = findMergeCandidates([
        stat('a', 'Roma'),
        stat('b', 'Roma antigua', usage: 9),
      ]).single;
      expect(byUsage.suggestedKeep.id, 'b');

      final byLength = findMergeCandidates([
        stat('a', 'Roma', usage: 2),
        stat('b', 'Roma antigua', usage: 2),
      ]).single;
      expect(byLength.suggestedKeep.id, 'a');
    });

    test('fuera del hilo de la interfaz da lo mismo', () async {
      final input = [
        stat('a', 'Canción', usage: 2),
        stat('b', 'cancion'),
        stat('c', 'Roma'),
        stat('d', 'Roma antigua'),
      ];

      final inline = findMergeCandidates(input);
      final offloaded = await findMergeCandidatesOffMainThread(input);

      String key(MergeCandidate c) =>
          '${c.first.id}|${c.second.id}|${c.reason.name}';
      expect(offloaded.map(key), inline.map(key));
    });
  });

  group('groupMergeCandidates', () {
    test('junta los valores conectados por algún par, aunque no todos se '
        'relacionen entre sí', () {
      // Roma~Róma (mismo texto), Roma~Roma antigua (contenido): Róma y
      // Roma antigua no se relacionan directamente.
      final groups = groupMergeCandidates(
        findMergeCandidates([
          stat('a', 'Roma', usage: 5),
          stat('b', 'Róma', usage: 2),
          stat('c', 'Roma antigua'),
        ]),
      );

      expect(groups, hasLength(1));
      expect(groups.single.values.map((v) => v.id), ['a', 'b', 'c']);
    });

    test('grupos distintos quedan separados y ordenados por uso combinado', () {
      final groups = groupMergeCandidates(
        findMergeCandidates([
          stat('a', 'Filosofía'),
          stat('b', 'filosofia'),
          stat('c', 'Historia', usage: 20),
          stat('d', 'historia', usage: 30),
        ]),
      );

      expect(groups.map((g) => g.combinedUsage), [50, 2]);
      expect(groups.first.values.map((v) => v.id), ['d', 'c']);
    });

    test(
      'el sugerido es el más usado, y a igual uso el de nombre más corto',
      () {
        final byUsage = groupMergeCandidates(
          findMergeCandidates([
            stat('a', 'Roma'),
            stat('b', 'Roma antigua', usage: 9),
          ]),
        ).single;
        expect(byUsage.suggestedKeep.id, 'b');

        final byLength = groupMergeCandidates(
          findMergeCandidates([
            stat('a', 'Roma', usage: 2),
            stat('b', 'Roma antigua', usage: 2),
          ]),
        ).single;
        expect(byLength.suggestedKeep.id, 'a');
      },
    );

    test('solo los casi seguro iguales se preseleccionan: los que solo '
        'comparten palabras no', () {
      final group = groupMergeCandidates(
        findMergeCandidates([
          stat('keep', 'Guerra', usage: 9),
          stat('acento', 'Guérra'), // mismo texto
          stat('plural', 'Guerras'), // casi igual
          stat('fria', 'Guerra fría'), // solo comparte palabras
        ]),
      ).single;

      expect(group.suggestedKeep.id, 'keep');
      expect(group.probableDuplicatesOf('keep'), {'acento', 'plural'});
    });

    test('las razones del grupo son las de sus pares', () {
      final group = groupMergeCandidates(
        findMergeCandidates([
          stat('a', 'Roma', usage: 5),
          stat('b', 'Róma'),
          stat('c', 'Roma antigua'),
        ]),
      ).single;

      expect(group.reasons, {
        MergeCandidateReason.sameText,
        MergeCandidateReason.contained,
      });
      expect(group.definitionName, 'def');
    });

    test('sin candidatos no hay grupos', () {
      expect(groupMergeCandidates(const []), isEmpty);
    });

    test('muchos nombres que comparten la primera palabra se agrupan rápido '
        'y en un solo grupo', () {
      // "Guerra aa", "Guerra ab"…: 1.000 nombres de largo realista que
      // empiezan igual. Es el caso caro del índice por palabra: cada uno
      // se compara contra todos los que comparten "guerra".
      String code(int n) =>
          String.fromCharCodes([0x61 + n ~/ 26 % 26, 0x61 + n % 26]);
      final input = [
        for (var i = 0; i < 1000; i++) stat('v$i', 'Guerra ${code(i)}'),
        stat('base', 'Guerra'),
      ];

      final watch = Stopwatch()..start();
      final groups = groupMergeCandidates(findMergeCandidates(input));
      watch.stop();

      // La medición es el punto de este test: se deja a la vista.
      // ignore: avoid_print
      print(
        'agrupar 1.001 nombres con la misma primera palabra: '
        '${watch.elapsedMilliseconds} ms',
      );
      expect(groups, hasLength(1));
      expect(groups.single.values, hasLength(1001));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('la salida está acotada: 1.000 nombres casi iguales entre sí no '
        'generan cientos de miles de pares', () {
      String code(int n) =>
          String.fromCharCodes([0x61 + n ~/ 26 % 26, 0x61 + n % 26]);
      final input = [
        for (var i = 0; i < 1000; i++) stat('v$i', 'Guerra ${code(i)}'),
      ];

      final pairs = findMergeCandidates(input);

      // Cada valor se enlaza con un puñado de parecidos, no con los 999
      // restantes: 1.000 x 6 pares como mucho, no medio millón.
      expect(pairs.length, lessThanOrEqualTo(1000 * 6));
      expect(pairs, isNotEmpty);
    });
  });

  group('rendimiento con 2.000 valores', () {
    /// Un vocabulario realista: palabras de sílabas, con variantes —plural,
    /// errata, acento, frase más larga— repartidas.
    List<VocabularyValueStat> realisticVocabulary() {
      final random = Random(42);
      const syllables = [
        'ma',
        're',
        'to',
        'fi',
        'lo',
        'so',
        'ci',
        'en',
        'ar',
        'te',
        'ga',
        'pe',
        'di',
        'na',
        'su',
        'li',
        'bo',
        'ru',
        'ha',
        'ke',
      ];
      String word() {
        final count = 2 + random.nextInt(3);
        return [
          for (var i = 0; i < count; i++) syllables[random.nextInt(20)],
        ].join();
      }

      final stats = <VocabularyValueStat>[];
      var n = 0;
      String next() => 'v${n++}';
      while (stats.length < 2000) {
        final base = word();
        final label = base[0].toUpperCase() + base.substring(1);
        stats.add(stat(next(), label, usage: random.nextInt(20)));
        switch (random.nextInt(5)) {
          case 0:
            stats.add(stat(next(), '${label}s', usage: random.nextInt(5)));
          case 1:
            stats.add(stat(next(), '$label antiguo', usage: random.nextInt(5)));
          case 2:
            stats.add(stat(next(), label.replaceFirst('a', 'á')));
          default:
            break;
        }
      }
      return stats.take(2000).toList();
    }

    /// El peor caso para los bloques por primera letra: TODOS empiezan igual
    /// y tienen el mismo largo.
    List<VocabularyValueStat> adversarialVocabulary() {
      final random = Random(7);
      const letters = 'abcdefghijklmnopqrstuvwxyz';
      return [
        for (var i = 0; i < 2000; i++)
          stat(
            'v$i',
            'a${List.generate(7, (_) => letters[random.nextInt(26)]).join()}',
          ),
      ];
    }

    test('un vocabulario realista tarda menos de un segundo', () {
      final input = realisticVocabulary();
      expect(input, hasLength(2000));

      final watch = Stopwatch()..start();
      final result = findMergeCandidates(input);
      watch.stop();

      // La medición es el punto de este test: se deja a la vista.
      // ignore: avoid_print
      print(
        'candidatos con 2.000 valores realistas: '
        '${watch.elapsedMilliseconds} ms (${result.length} pares)',
      );
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(result, isNotEmpty);
    });

    test(
      'el peor caso —todos con la misma letra y el mismo largo— también',
      () {
        final input = adversarialVocabulary();

        final watch = Stopwatch()..start();
        findMergeCandidates(input);
        watch.stop();

        // La medición es el punto de este test: se deja a la vista.
        // ignore: avoid_print
        print(
          'candidatos con 2.000 valores adversariales: '
          '${watch.elapsedMilliseconds} ms',
        );
        expect(watch.elapsedMilliseconds, lessThan(1000));
      },
    );
  });
}
