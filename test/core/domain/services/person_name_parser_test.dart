import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/services/person_name_parser.dart';

/// Leer nombres como los escribe BibTeX (F15): el apellido y el nombre
/// separados, con lo que sí se puede saber y sin adivinar lo demás.
void main() {
  PersonName name(String raw) => parseName(raw)!.name;

  group('con coma: no hay nada que deducir', () {
    test('«Apellido, Nombre»', () {
      final parsed = parseName('García Márquez, Gabriel')!;

      expect(parsed.name.family, 'García Márquez');
      expect(parsed.name.given, 'Gabriel');
      expect(parsed.orderInferred, isFalse);
    });

    test('la partícula queda con el apellido', () {
      expect(name('van Beethoven, Ludwig').family, 'van Beethoven');
      expect(name('de la Vega, Garcilaso').family, 'de la Vega');
      expect(name('de la Vega, Garcilaso').given, 'Garcilaso');
    });

    test('con sufijo, en las dos formas que se escriben', () {
      for (final raw in [
        'King, Jr., Martin Luther',
        'King, Martin Luther, Jr.',
      ]) {
        final king = name(raw);
        expect(king.family, 'King', reason: raw);
        expect(king.given, 'Martin Luther', reason: raw);
        expect(king.suffix, 'Jr.', reason: raw);
      }
    });

    test('sin apellido no hay nombre', () {
      expect(parseName(', Gabriel'), isNull);
      expect(parseName(','), isNull);
    });
  });

  group('sin coma: BibTeX toma la última palabra', () {
    test('«Nombre Apellido»', () {
      final parsed = parseName('Thomas Piketty')!;

      expect(parsed.name.family, 'Piketty');
      expect(parsed.name.given, 'Thomas');
      expect(parsed.orderInferred, isTrue);
    });

    test('con partícula: «Ludwig van Beethoven»', () {
      final beethoven = name('Ludwig van Beethoven');

      expect(beethoven.family, 'van Beethoven');
      expect(beethoven.given, 'Ludwig');
    });

    test('con una partícula y un apellido doble', () {
      final cervantes = name('Miguel de Cervantes Saavedra');

      expect(cervantes.family, 'de Cervantes Saavedra');
      expect(cervantes.given, 'Miguel');
    });

    test('solo la partícula y el apellido: no hay nombre', () {
      final vega = name('de la Vega');

      expect(vega.family, 'de la Vega');
      expect(vega.given, isEmpty);
    });

    test(
      'un nombre de una sola palabra es un apellido y no se deduce nada',
      () {
        final parsed = parseName('Tucídides')!;

        expect(parsed.name.family, 'Tucídides');
        expect(parsed.name.given, isEmpty);
        expect(parsed.orderInferred, isFalse);
      },
    );

    test('con sufijo', () {
      final king = name('Martin Luther King Jr.');

      expect(king.family, 'King');
      expect(king.given, 'Martin Luther');
      expect(king.suffix, 'Jr.');
    });

    test('lo que la deducción NO acierta queda dicho: dos apellidos '
        'españoles sin coma', () {
      // Es lo que hace BibTeX, y por eso el importador cuenta estos casos y
      // los avisa: con «García Márquez, Gabriel» no falla.
      final parsed = parseName('Gabriel García Márquez')!;

      expect(parsed.name.family, 'Márquez');
      expect(parsed.name.given, 'Gabriel García');
      expect(parsed.orderInferred, isTrue);
    });
  });

  group('las llaves protegen', () {
    test('un nombre entre llaves es una institución', () {
      final who = name('{Organización Mundial de la Salud}');

      expect(who.isInstitution, isTrue);
      expect(who.family, 'Organización Mundial de la Salud');
      expect(who.given, isEmpty);
    });

    test('las llaves dobles también', () {
      expect(
        name('{{World Health Organization}}').family,
        'World Health Organization',
      );
    });

    test(
      'un nombre que solo tiene un pedazo protegido no es una institución',
      () {
        final jean = name('Jean-Paul {Sartre Simone}');

        expect(jean.isInstitution, isFalse);
      },
    );

    test('el decodificador se aplica a cada parte, no a la estructura', () {
      String decode(String text) => text
          .replaceAll(r"{\'E}", 'É')
          .replaceAll('{', '')
          .replaceAll('}', '');

      final durkheim = parseName(r"{\'E}mile Durkheim", decode: decode)!.name;
      final comma = parseName(r"Durkheim, {\'E}mile", decode: decode)!.name;

      expect(durkheim.given, 'Émile');
      expect(durkheim.family, 'Durkheim');
      expect(comma.given, 'Émile');
    });
  });

  group('una lista de nombres', () {
    test('separados por «and»', () {
      final list = parseNameList(
        'García Márquez, Gabriel and Vargas Llosa, Mario',
      );

      expect(list.names.map((n) => n.name.label), [
        'García Márquez, Gabriel',
        'Vargas Llosa, Mario',
      ]);
      expect(list.hasOthers, isFalse);
    });

    test('un «and» dentro de llaves no separa', () {
      final list = parseNameList('{Barnes and Noble}');

      expect(list.names, hasLength(1));
      expect(list.names.single.name.isInstitution, isTrue);
      expect(list.names.single.name.family, 'Barnes and Noble');
    });

    test('un apellido que empieza con «and» no separa', () {
      final list = parseNameList('Anderson, Alexander and Andrews, Ana');

      expect(list.names, hasLength(2));
    });

    test('no distingue mayúsculas ni saltos de línea', () {
      final list = parseNameList('Piketty, Thomas\n   AND Saez, Emmanuel');

      expect(list.names.map((n) => n.name.family), ['Piketty', 'Saez']);
    });

    test('«and others» dice que había más', () {
      final list = parseNameList('Smith, John and others');

      expect(list.names, hasLength(1));
      expect(list.hasOthers, isTrue);
    });

    test('vacía no tiene nombres', () {
      expect(parseNameList('   ').names, isEmpty);
    });

    test('cuenta cuáles se dedujeron', () {
      final list = parseNameList('Piketty, Thomas and Emmanuel Saez');

      expect(list.names.map((n) => n.orderInferred), [false, true]);
    });
  });
}
