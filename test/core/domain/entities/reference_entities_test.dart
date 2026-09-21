import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Los datos de una referencia (F15): un nombre partido, una fecha con la
/// exactitud con que se sabe, y lo demás que una cita necesita.
void main() {
  group('PersonName', () {
    const garcia = PersonName(family: 'García Márquez', given: 'Gabriel José');

    test('la etiqueta canónica es «Apellido, Nombre»', () {
      expect(garcia.label, 'García Márquez, Gabriel José');
      expect(
        const PersonName(
          family: 'King',
          given: 'Martin Luther',
          suffix: 'Jr.',
        ).label,
        'King, Martin Luther Jr.',
      );
    });

    test('una sola palabra o una institución no llevan coma', () {
      expect(const PersonName(family: 'Tucídides').label, 'Tucídides');
      expect(
        const PersonName.institution('Real Academia Española').label,
        'Real Academia Española',
      );
    });

    test('el nombre para una nota va en el orden natural', () {
      expect(garcia.displayName, 'Gabriel José García Márquez');
      expect(
        const PersonName(
          family: 'King',
          given: 'Martin Luther',
          suffix: 'Jr.',
        ).displayName,
        'Martin Luther King Jr.',
      );
      expect(const PersonName(family: 'Platón').displayName, 'Platón');
    });

    test('las iniciales', () {
      expect(garcia.initials, 'G. J.');
      expect(
        const PersonName(family: 'Sartre', given: 'Jean-Paul').initials,
        'J.-P.',
      );
      expect(
        const PersonName(family: 'Tolkien', given: 'J.R.R.').initials,
        'J. R. R.',
      );
      expect(const PersonName(family: 'Tucídides').initials, isEmpty);
      expect(const PersonName.institution('OMS').initials, isEmpty);
      // Un nombre de pila que empieza en minúscula o con una comilla.
      expect(const PersonName(family: 'X', given: "d'Artagnan").initials, 'D.');
    });

    test('es un valor: dos con lo mismo son iguales', () {
      expect(
        const PersonName(family: 'A', given: 'B'),
        const PersonName(family: 'A', given: 'B'),
      );
      expect(
        const PersonName(family: 'A', given: 'B'),
        isNot(const PersonName(family: 'A', given: 'C')),
      );
      expect(
        const PersonName(family: 'OMS'),
        isNot(const PersonName.institution('OMS')),
      );
    });

    test('está vacío si no tiene ni apellido ni nombre', () {
      expect(const PersonName(family: ' ').isEmpty, isTrue);
      expect(garcia.isEmpty, isFalse);
    });
  });

  group('PublicationDate', () {
    test('una fecha desconocida no es una obra sin fecha', () {
      const unknown = PublicationDate.unknown();
      const undated = PublicationDate.undated();

      expect(unknown.isUnknown, isTrue);
      expect(unknown.isUndated, isFalse);
      expect(undated.isUnknown, isFalse);
      expect(undated.isUndated, isTrue);
      expect(unknown, isNot(undated));
    });

    test('solo el año: no inventa mes ni día', () {
      final date = PublicationDate.ofYear(1967);

      expect(date.year, 1967);
      expect(date.month, isNull);
      expect(date.day, isNull);
      expect(date.isUnknown, isFalse);
    });

    test('con mes, y con día', () {
      final month = PublicationDate.ofMonth(1967, 5);
      final day = PublicationDate.ofDay(1967, 5, 30);

      expect((month.year, month.month, month.day), (1967, 5, null));
      expect((day.year, day.month, day.day), (1967, 5, 30));
    });

    test(
      'desde lo que se guarda: una fecha sin precisión es un día completo',
      () {
        final captured = PublicationDate.fromStored(
          DateTime(2019, 3, 15),
          null,
        );

        expect(captured.precision, PublicationPrecision.day);
        expect(captured.day, 15);
      },
    );

    test('desde lo que se guarda: la precisión limita lo que se ve', () {
      final year = PublicationDate.fromStored(
        DateTime(1967),
        PublicationPrecision.year,
      );

      expect(year.year, 1967);
      expect(year.month, isNull);
    });

    test(
      '«sin fecha» gana sobre una fecha guardada, y sin nada es desconocida',
      () {
        expect(
          PublicationDate.fromStored(
            DateTime(2019),
            PublicationPrecision.undated,
          ).isUndated,
          isTrue,
        );
        expect(PublicationDate.fromStored(null, null).isUnknown, isTrue);
        expect(
          PublicationDate.fromStored(null, PublicationPrecision.year).isUnknown,
          isTrue,
        );
      },
    );

    test('es un valor', () {
      expect(PublicationDate.ofYear(1967), PublicationDate.ofYear(1967));
      expect(PublicationDate.ofYear(1967), isNot(PublicationDate.ofYear(1968)));
      expect(
        PublicationDate.ofYear(1967),
        isNot(PublicationDate.ofMonth(1967, 1)),
      );
    });
  });

  group('ReferenceData', () {
    const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');
    const rabassa = PersonName(family: 'Rabassa', given: 'Gregory');
    const authorGarcia = Contributor(name: garcia);
    const translatorRabassa = Contributor(
      name: rabassa,
      role: ContributorRole.translator,
    );

    test('sin ningún dato está vacía', () {
      expect(const ReferenceData().isEmpty, isTrue);
      expect(const ReferenceData(pages: '12').isEmpty, isFalse);
      expect(const ReferenceData(type: ReferenceType.book).isEmpty, isFalse);
      expect(
        const ReferenceData(contributors: [authorGarcia]).isEmpty,
        isFalse,
      );
    });

    test('las personas se piden por rol, en su orden', () {
      const reference = ReferenceData(
        contributors: [
          authorGarcia,
          translatorRabassa,
          Contributor(
            name: PersonName(family: 'Otro', given: 'Autor'),
          ),
        ],
      );

      expect(
        reference.byRole(ContributorRole.author).map((c) => c.name.family),
        ['García Márquez', 'Otro'],
      );
      expect(reference.byRole(ContributorRole.translator), [translatorRabassa]);
      expect(reference.byRole(ContributorRole.editor), isEmpty);
    });

    test('copyWith cambia lo que se pide y deja lo demás', () {
      const original = ReferenceData(
        type: ReferenceType.book,
        publisher: 'Sudamericana',
        contributors: [authorGarcia],
      );

      final changed = original.copyWith(publisherPlace: 'Buenos Aires');

      expect(changed.publisher, 'Sudamericana');
      expect(changed.publisherPlace, 'Buenos Aires');
      expect(changed.type, ReferenceType.book);
      expect(changed.contributors, [authorGarcia]);
    });

    test('es un valor: incluye a las personas y su orden', () {
      const a = ReferenceData(contributors: [authorGarcia, translatorRabassa]);
      const same = ReferenceData(
        contributors: [authorGarcia, translatorRabassa],
      );
      const reordered = ReferenceData(
        contributors: [translatorRabassa, authorGarcia],
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(reordered));
    });

    test('una persona ya guardada se distingue de un nombre suelto', () {
      const saved = Contributor(name: garcia, personId: 'v1');

      expect(saved, isNot(authorGarcia));
      expect(saved.copyWith(role: ContributorRole.editor).personId, 'v1');
    });
  });
}
