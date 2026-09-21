import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';

/// La referencia como texto (F15): lo que guarda un conflicto de fusión de la
/// versión que no quedó en vivo, para poder ponerla de nuevo.
void main() {
  final full = ReferenceData(
    type: ReferenceType.chapter,
    contributors: const [
      Contributor(
        name: PersonName(family: 'García Márquez', given: 'Gabriel'),
      ),
      Contributor(
        name: PersonName(family: 'Rabassa', given: 'Gregory'),
        role: ContributorRole.translator,
      ),
      Contributor(
        name: PersonName.institution('Real Academia Española'),
        role: ContributorRole.editor,
      ),
      Contributor(
        name: PersonName(family: 'King', given: 'Martin Luther', suffix: 'Jr.'),
      ),
    ],
    containerTitle: 'Historia de Roma',
    publisher: 'Sudamericana',
    publisherPlace: 'Buenos Aires',
    edition: '2.ª ed.',
    volume: '3',
    issue: '4',
    pages: '45-67',
    isbn: '9780306406157',
    issn: '0378-5955',
    doi: '10.1000/xyz123',
    accessedAt: DateTime.fromMillisecondsSinceEpoch(1789000000 * 1000),
    citationKey: 'garcia1967',
    publicationPrecision: PublicationPrecision.month,
  );

  group('ida y vuelta', () {
    test('con todos los datos', () {
      expect(decodeReference(encodeReference(full)), full);
    });

    test('una referencia sin nada es solo la versión', () {
      expect(encodeReference(const ReferenceData()), '{"v":1}');
      expect(
        decodeReference(encodeReference(const ReferenceData())),
        const ReferenceData(),
      );
    });

    test('las personas van por su nombre, con rol, sufijo e institución', () {
      final people = decodeReference(encodeReference(full))!.contributors;

      expect(people.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.translator,
        ContributorRole.editor,
        ContributorRole.author,
      ]);
      expect(people[2].name.isInstitution, isTrue);
      expect(people[3].name.suffix, 'Jr.');
      expect(people[3].name.label, 'King, Martin Luther Jr.');
    });

    test('el identificador del vocabulario NO viaja: cambia de bóveda a '
        'bóveda', () {
      const reference = ReferenceData(
        contributors: [
          Contributor(
            name: PersonName(family: 'Borges', given: 'Jorge Luis'),
            personId: 'valor-de-esta-boveda',
          ),
        ],
      );

      final text = encodeReference(reference);

      expect(text, isNot(contains('valor-de-esta-boveda')));
      expect(decodeReference(text)!.contributors.single.personId, isNull);
    });

    test('la fecha de consulta se guarda en segundos', () {
      final reference = ReferenceData(
        accessedAt: DateTime.fromMillisecondsSinceEpoch(
          1789000000 * 1000 + 999,
        ),
      );

      final back = decodeReference(encodeReference(reference))!;

      expect(back.accessedAt!.millisecondsSinceEpoch, 1789000000 * 1000);
    });
  });

  group('el texto es canónico', () {
    test('la misma referencia da siempre el mismo texto', () {
      expect(encodeReference(full), encodeReference(full));
    });

    test('es de una sola línea y JSON válido', () {
      final text = encodeReference(full);

      expect(text, isNot(contains('\n')));
      expect(jsonDecode(text), isA<Map<String, Object?>>());
    });

    test('solo lleva lo que tiene un valor', () {
      const reference = ReferenceData(publisher: 'X', volume: '2');

      expect(
        encodeReference(reference),
        '{"v":1,"publisher":"X","volume":"2"}',
      );
    });
  });

  group('al leerlo, tolerante', () {
    test(
      'un tipo o una exactitud que no conoce se ignoran, no rechazan todo',
      () {
        final back = decodeReference(
          '{"v":9,"type":"holograma","precision":"siglo","publisher":"X"}',
        )!;

        expect(back.type, isNull);
        expect(back.publicationPrecision, isNull);
        expect(back.publisher, 'X');
      },
    );

    test('una persona sin apellido se salta, y sin rol es autora', () {
      final back = decodeReference(
        jsonEncode({
          'v': 1,
          'people': [
            {'given': 'Sin apellido'},
            {'family': 'Platón'},
            'basura',
            {'family': 'Ed', 'role': 'inventado'},
          ],
        }),
      )!;

      expect(back.contributors.map((c) => c.name.family), ['Platón', 'Ed']);
      expect(back.contributors.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.author,
      ]);
    });

    test('una clave que no conoce no molesta', () {
      final back = decodeReference('{"v":2,"futuro":true,"pages":"1"}')!;

      expect(back.pages, '1');
    });

    test('un valor de otro tipo se ignora', () {
      final back = decodeReference(
        '{"v":1,"pages":12,"accessed":"ayer","publisher":""}',
      )!;

      expect(back.pages, isNull);
      expect(back.accessedAt, isNull);
      expect(back.publisher, isNull);
    });

    test('lo que no es un objeto JSON no es nada', () {
      for (final text in ['', 'no es json', '[1,2]', '"x"', '12', 'null']) {
        expect(decodeReference(text), isNull, reason: text);
      }
    });
  });
}
