import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/reference_draft.dart';

/// Lo que el formulario de la referencia tiene escrito (F15): qué se pide de
/// cada tipo de obra, cómo se lee una fecha a medias y qué no se puede guardar.
void main() {
  ReferenceDraft draft({
    ReferenceType? type,
    List<PersonDraft> people = const [],
    Map<ReferenceField, String> fields = const {},
    String year = '',
    String month = '',
    String day = '',
    bool undated = false,
  }) => ReferenceDraft(
    type: type,
    people: people,
    fields: fields,
    year: year,
    month: month,
    day: day,
    undated: undated,
  );

  group('qué se pide de cada tipo', () {
    test('cada tipo pide lo suyo, y la clave de cita siempre', () {
      expect(fieldsFor(ReferenceType.book), contains(ReferenceField.isbn));
      expect(
        fieldsFor(ReferenceType.book),
        isNot(contains(ReferenceField.issue)),
      );
      expect(
        fieldsFor(ReferenceType.article),
        containsAll([
          ReferenceField.container,
          ReferenceField.volume,
          ReferenceField.issue,
          ReferenceField.pages,
          ReferenceField.issn,
        ]),
      );
      expect(
        fieldsFor(ReferenceType.website),
        containsAll([ReferenceField.container, ReferenceField.accessed]),
      );
      expect(
        fieldsFor(ReferenceType.thesis),
        isNot(contains(ReferenceField.container)),
      );
      for (final type in ReferenceType.values) {
        expect(fieldsFor(type), contains(ReferenceField.citationKey));
      }
    });

    test('una obra sin tipo, o de otro, pide todo', () {
      expect(fieldsFor(null), ReferenceField.values);
      expect(fieldsFor(ReferenceType.other), ReferenceField.values);
    });

    test('lo que se ve sin desplegar es lo que el estilo pide', () {
      expect(primaryFieldsFor(ReferenceType.book), [ReferenceField.publisher]);
      expect(primaryFieldsFor(ReferenceType.chapter), [
        ReferenceField.container,
        ReferenceField.publisher,
      ]);
      expect(primaryFieldsFor(ReferenceType.article), [
        ReferenceField.container,
        ReferenceField.volume,
      ]);
      expect(primaryFieldsFor(ReferenceType.website), [
        ReferenceField.container,
      ]);
      expect(primaryFieldsFor(null), [ReferenceField.publisher]);
    });

    test('lo que se ve sin desplegar es parte de lo que el tipo pide', () {
      for (final type in [...ReferenceType.values, null]) {
        expect(
          fieldsFor(type),
          containsAll(primaryFieldsFor(type)),
          reason: '$type',
        );
      }
    });

    test('las personas que se piden de cada tipo', () {
      expect(rolesFor(ReferenceType.article), [ContributorRole.author]);
      expect(rolesFor(ReferenceType.chapter), [
        ContributorRole.author,
        ContributorRole.editor,
        ContributorRole.translator,
      ]);
      expect(rolesFor(ReferenceType.documentary), [
        ContributorRole.director,
        ContributorRole.author,
      ]);
      expect(rolesFor(null), ContributorRole.values);
    });
  });

  group('desde lo guardado', () {
    final reference = ReferenceData(
      type: ReferenceType.chapter,
      contributors: const [
        Contributor(
          name: PersonName(family: 'García Márquez', given: 'Gabriel'),
        ),
        Contributor(
          name: PersonName.institution('Real Academia Española'),
          role: ContributorRole.editor,
        ),
      ],
      containerTitle: 'Historia',
      publisher: 'Editorial',
      publisherPlace: 'Lima',
      edition: '2',
      volume: '3',
      issue: '4',
      pages: '12-20',
      isbn: '9780306406157',
      issn: '1234-5679',
      doi: '10.1000/xyz',
      accessedAt: DateTime(2026, 9, 5),
      citationKey: 'garcia1967',
      publicationPrecision: PublicationPrecision.month,
    );

    test('cada dato aparece escrito', () {
      final result = ReferenceDraft.of(reference, DateTime(2020, 3));

      expect(result.type, ReferenceType.chapter);
      expect(result.fields[ReferenceField.container], 'Historia');
      expect(result.fields[ReferenceField.publisher], 'Editorial');
      expect(result.fields[ReferenceField.place], 'Lima');
      expect(result.fields[ReferenceField.pages], '12-20');
      expect(result.fields[ReferenceField.doi], '10.1000/xyz');
      expect(result.fields[ReferenceField.accessed], '2026-09-05');
      expect(result.fields[ReferenceField.citationKey], 'garcia1967');
      expect(result.people.map((p) => p.text), [
        'García Márquez, Gabriel',
        'Real Academia Española',
      ]);
      expect(result.people.last.isInstitution, isTrue);
      expect(result.people.last.role, ContributorRole.editor);
    });

    test('la fecha se escribe hasta donde se sabe', () {
      final month = ReferenceDraft.of(reference, DateTime(2020, 3));
      final day = ReferenceDraft.of(
        const ReferenceData(),
        DateTime(2020, 3, 15),
      );
      final none = ReferenceDraft.of(const ReferenceData(), null);

      expect([month.year, month.month, month.day], ['2020', '3', '']);
      expect([day.year, day.month, day.day], ['2020', '3', '15']);
      expect([none.year, none.month, none.day], ['', '', '']);
      expect(none.undated, isFalse);
    });

    test('«sin fecha» se marca', () {
      final result = ReferenceDraft.of(
        const ReferenceData(publicationPrecision: PublicationPrecision.undated),
        null,
      );

      expect(result.undated, isTrue);
    });

    test('guardar sin tocar nada devuelve lo mismo', () {
      final result = ReferenceDraft.of(reference, DateTime(2020, 3));
      final built = result.build();

      expect(result.validate(), isEmpty);
      expect(built.type, reference.type);
      expect(built.containerTitle, reference.containerTitle);
      expect(built.publisher, reference.publisher);
      expect(built.publisherPlace, reference.publisherPlace);
      expect(built.edition, reference.edition);
      expect(built.volume, reference.volume);
      expect(built.issue, reference.issue);
      expect(built.pages, reference.pages);
      expect(built.isbn, reference.isbn);
      expect(built.issn, reference.issn);
      expect(built.doi, reference.doi);
      expect(built.accessedAt, reference.accessedAt);
      expect(built.citationKey, reference.citationKey);
      expect(built.publicationPrecision, PublicationPrecision.month);
      expect(built.contributors.map((c) => c.name), [
        for (final c in reference.contributors) c.name,
      ]);
      expect(built.contributors.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.editor,
      ]);
      expect(result.publishedAt, DateTime(2020, 3));
    });
  });

  group('las personas', () {
    test('«Apellido, Nombre» se parte, en su orden y con su rol', () {
      final built = draft(
        people: const [
          PersonDraft(role: ContributorRole.author, text: 'Borges, Jorge Luis'),
          PersonDraft(role: ContributorRole.translator, text: 'Fagles, Robert'),
          PersonDraft(role: ContributorRole.author, text: 'Paz, Octavio'),
        ],
      ).build();

      expect(
        [for (final c in built.contributors) '${c.role.name}: ${c.name.label}'],
        [
          'author: Borges, Jorge Luis',
          'translator: Fagles, Robert',
          'author: Paz, Octavio',
        ],
      );
      expect(built.contributors.first.name.family, 'Borges');
      expect(built.contributors.first.name.given, 'Jorge Luis');
    });

    test('una institución no se parte', () {
      final built = draft(
        people: const [
          PersonDraft(
            role: ContributorRole.author,
            text: 'Organización Mundial de la Salud',
            isInstitution: true,
          ),
        ],
      ).build();

      expect(built.contributors.single.name.isInstitution, isTrue);
      expect(
        built.contributors.single.name.family,
        'Organización Mundial de la Salud',
      );
    });

    test('lo que está vacío no es una persona', () {
      final built = draft(
        people: const [
          PersonDraft(role: ContributorRole.author, text: '   '),
          PersonDraft(role: ContributorRole.author, text: 'Platón'),
          PersonDraft(role: ContributorRole.author, text: ''),
        ],
      ).build();

      expect(built.contributors, hasLength(1));
      expect(built.contributors.single.name.family, 'Platón');
    });
  });

  group('los datos de texto', () {
    test('lo vacío o de espacios es nada, y lo demás se recorta', () {
      final built = draft(
        fields: {
          ReferenceField.publisher: '  Editorial  ',
          ReferenceField.edition: '   ',
          ReferenceField.pages: '',
        },
      ).build();

      expect(built.publisher, 'Editorial');
      expect(built.edition, isNull);
      expect(built.pages, isNull);
      expect(built.volume, isNull);
    });
  });

  group('la fecha de publicación', () {
    test('sin nada escrito es una fecha que nadie cargó', () {
      final result = draft();

      expect(result.validate(), isEmpty);
      expect(result.publishedAt, isNull);
      expect(result.build().publicationPrecision, isNull);
    });

    test('solo el año, el año y el mes, el día completo', () {
      final year = draft(year: '1967');
      final month = draft(year: '1967', month: '6');
      final day = draft(year: '1967', month: '6', day: '5');

      expect(year.publishedAt, DateTime(1967));
      expect(year.build().publicationPrecision, PublicationPrecision.year);
      expect(month.publishedAt, DateTime(1967, 6));
      expect(month.build().publicationPrecision, PublicationPrecision.month);
      expect(day.publishedAt, DateTime(1967, 6, 5));
      expect(day.build().publicationPrecision, PublicationPrecision.day);
      for (final d in [year, month, day]) {
        expect(d.validate(), isEmpty);
      }
    });

    test('sin fecha: no se guarda ninguna y se dice que no la tiene', () {
      final result = draft(year: '1967', undated: true);

      expect(result.validate(), isEmpty);
      expect(result.publishedAt, isNull);
      expect(result.build().publicationPrecision, PublicationPrecision.undated);
    });

    test('lo que no es una fecha se marca', () {
      final invalid = [
        draft(month: '6'),
        draft(day: '5'),
        draft(year: '1967', day: '5'),
        draft(year: 'mil'),
        draft(year: '0'),
        draft(year: '10000'),
        draft(year: '1967', month: '13'),
        draft(year: '1967', month: '0'),
        draft(year: '1967', month: 'junio'),
        draft(year: '1967', month: '2', day: '30'),
        draft(year: '1967', month: '6', day: '0'),
        draft(year: '1967', month: '6', day: '31'),
      ];

      for (final d in invalid) {
        expect(
          d.validate(),
          contains(ReferenceDraftError.date),
          reason: '${d.year}/${d.month}/${d.day}',
        );
      }
    });

    test('el 29 de febrero, solo en un año bisiesto', () {
      expect(draft(year: '2024', month: '2', day: '29').validate(), isEmpty);
      expect(
        draft(year: '2023', month: '2', day: '29').validate(),
        contains(ReferenceDraftError.date),
      );
    });

    test('con «sin fecha», lo escrito en la fecha no se mira', () {
      expect(draft(year: 'mil', undated: true).validate(), isEmpty);
    });
  });

  group('lo que no se puede guardar', () {
    test('un DOI, un ISBN o un ISSN que no valen', () {
      final result = draft(
        fields: {
          ReferenceField.doi: 'no es un doi',
          ReferenceField.isbn: '123',
          ReferenceField.issn: '12',
        },
      ).validate();

      expect(result, {
        ReferenceDraftError.doi,
        ReferenceDraftError.isbn,
        ReferenceDraftError.issn,
      });
    });

    test('los que valen, con la forma en que suelen escribirse', () {
      final result = draft(
        fields: {
          ReferenceField.doi: 'https://doi.org/10.1000/XYZ',
          ReferenceField.isbn: '978-0-306-40615-7',
          ReferenceField.issn: '1234-5679',
        },
      ).validate();

      expect(result, isEmpty);
    });

    test('vacíos no son un error', () {
      expect(
        draft(
          fields: {
            ReferenceField.doi: '',
            ReferenceField.isbn: '  ',
            ReferenceField.accessed: '',
          },
        ).validate(),
        isEmpty,
      );
    });

    test('la fecha de consulta es «AAAA-MM-DD» y existe', () {
      DateTime? accessed(String text) =>
          draft(fields: {ReferenceField.accessed: text}).build().accessedAt;
      Set<ReferenceDraftError> errors(String text) =>
          draft(fields: {ReferenceField.accessed: text}).validate();

      expect(accessed('2026-09-05'), DateTime(2026, 9, 5));
      expect(accessed('2026-9-5'), DateTime(2026, 9, 5));
      expect(errors('2026-09-05'), isEmpty);
      for (final bad in ['05/09/2026', '2026-02-30', 'ayer', '2026-13-01']) {
        expect(errors(bad), {ReferenceDraftError.accessed}, reason: bad);
      }
    });

    test('todo junto, cada error por separado', () {
      final result = draft(
        year: 'mil',
        fields: {ReferenceField.doi: 'x', ReferenceField.accessed: 'ayer'},
      ).validate();

      expect(result, {
        ReferenceDraftError.doi,
        ReferenceDraftError.accessed,
        ReferenceDraftError.date,
      });
    });
  });
}
