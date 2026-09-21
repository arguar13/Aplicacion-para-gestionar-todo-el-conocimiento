import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/reference_normalizer.dart';

/// La referencia tal como se guarda (F15): limpia, con sus identificadores
/// normalizados, y sin lo que no vale.
void main() {
  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');

  group('los textos', () {
    test('se recortan', () {
      final result = normalizeReference(
        const ReferenceData(
          publisher: '  Sudamericana ',
          publisherPlace: '\tBuenos Aires\n',
          pages: ' 45-67 ',
        ),
      );

      expect(result.publisher, 'Sudamericana');
      expect(result.publisherPlace, 'Buenos Aires');
      expect(result.pages, '45-67');
    });

    test('uno vacío o de espacios es «no dijeron nada»', () {
      final result = normalizeReference(
        const ReferenceData(
          containerTitle: '',
          edition: '   ',
          volume: '\n',
          issue: '3',
        ),
      );

      expect(result.containerTitle, isNull);
      expect(result.edition, isNull);
      expect(result.volume, isNull);
      expect(result.issue, '3');
    });

    test('lo que no es texto pasa igual', () {
      final accessed = DateTime(2026, 9, 21);
      final result = normalizeReference(
        ReferenceData(
          type: ReferenceType.thesis,
          accessedAt: accessed,
          publicationPrecision: PublicationPrecision.undated,
        ),
      );

      expect(result.type, ReferenceType.thesis);
      expect(result.accessedAt, accessed);
      expect(result.publicationPrecision, PublicationPrecision.undated);
    });
  });

  group('los identificadores', () {
    test('se guardan normalizados', () {
      final result = normalizeReference(
        const ReferenceData(
          doi: 'https://doi.org/10.1000/XYZ123',
          isbn: '0-306-40615-2',
          issn: '03785955',
        ),
      );

      expect(result.doi, '10.1000/xyz123');
      expect(result.isbn, '9780306406157');
      expect(result.issn, '0378-5955');
    });

    test('uno que no vale no se guarda', () {
      final result = normalizeReference(
        const ReferenceData(
          doi: 'no es un doi',
          isbn: '978-0-306-40615-8',
          issn: '0378-5954',
        ),
      );

      expect(result.doi, isNull);
      expect(result.isbn, isNull);
      expect(result.issn, isNull);
    });

    test('uno vacío queda vacío', () {
      final result = normalizeReference(
        const ReferenceData(doi: ' ', isbn: ''),
      );

      expect(result.doi, isNull);
      expect(result.isbn, isNull);
      expect(result.issn, isNull);
    });
  });

  group('las personas', () {
    test('se recortan sus partes y se conserva su orden', () {
      final result = normalizeReference(
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: ' García Márquez ', given: ' Gabriel '),
            ),
            Contributor(
              name: PersonName(family: 'Rabassa', given: 'Gregory'),
              role: ContributorRole.translator,
            ),
          ],
        ),
      );

      expect(result.contributors.map((c) => c.name.label), [
        'García Márquez, Gabriel',
        'Rabassa, Gregory',
      ]);
      expect(result.contributors.map((c) => c.role), [
        ContributorRole.author,
        ContributorRole.translator,
      ]);
    });

    test('una sin nombre ni identidad se descarta', () {
      final result = normalizeReference(
        const ReferenceData(
          contributors: [
            Contributor(name: PersonName(family: '  ')),
            Contributor(name: garcia),
          ],
        ),
      );

      expect(result.contributors, hasLength(1));
      expect(result.contributors.single.name, garcia);
    });

    test('una ya guardada se conserva aunque le falte el nombre', () {
      final result = normalizeReference(
        const ReferenceData(
          contributors: [
            Contributor(
              name: PersonName(family: ''),
              personId: 'v1',
            ),
          ],
        ),
      );

      expect(result.contributors.single.personId, 'v1');
    });

    test(
      'la misma persona con el mismo rol queda una vez, en su primer lugar',
      () {
        final result = normalizeReference(
          const ReferenceData(
            contributors: [
              Contributor(name: garcia),
              Contributor(
                name: PersonName(family: 'Otro', given: 'Autor'),
              ),
              Contributor(
                name: PersonName(family: 'GARCÍA MÁRQUEZ', given: 'GABRIEL'),
              ),
            ],
          ),
        );

        expect(result.contributors.map((c) => c.name.family), [
          'García Márquez',
          'Otro',
        ]);
      },
    );

    test('con otro rol es otra entrada: se puede traducir la propia obra', () {
      final result = normalizeReference(
        const ReferenceData(
          contributors: [
            Contributor(name: garcia),
            Contributor(name: garcia, role: ContributorRole.translator),
          ],
        ),
      );

      expect(result.contributors, hasLength(2));
    });

    test('la identidad guardada manda sobre el nombre', () {
      final result = normalizeReference(
        const ReferenceData(
          contributors: [
            Contributor(name: garcia, personId: 'v1'),
            Contributor(
              name: PersonName(family: 'Distinto'),
              personId: 'v1',
            ),
            Contributor(name: garcia, personId: 'v2'),
          ],
        ),
      );

      expect(result.contributors.map((c) => c.personId), ['v1', 'v2']);
    });
  });

  test('es idempotente: normalizar dos veces da lo mismo', () {
    final once = normalizeReference(
      const ReferenceData(
        doi: 'DOI: 10.1000/ABC',
        isbn: '0-306-40615-2',
        publisher: ' X ',
        contributors: [
          Contributor(name: garcia),
          Contributor(name: garcia),
        ],
      ),
    );

    expect(normalizeReference(once), once);
  });

  test('una referencia sin nada sigue vacía', () {
    expect(
      normalizeReference(const ReferenceData(pages: '  ')).isEmpty,
      isTrue,
    );
  });
}
