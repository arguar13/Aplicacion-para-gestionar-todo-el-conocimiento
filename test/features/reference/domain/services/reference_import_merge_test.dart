import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/reference_import_merge.dart';

void main() {
  group('mergeReferenceOnImport', () {
    test('lo que ya tenía gana: no pisa lo que el usuario tocó', () {
      const current = ReferenceData(publisher: 'Editorial del usuario');
      const incoming = ReferenceData(publisher: 'Editorial del archivo');

      final merged = mergeReferenceOnImport(current, incoming);

      expect(merged.publisher, 'Editorial del usuario');
    });

    test('completa SOLO lo que estaba vacío', () {
      const current = ReferenceData(publisher: 'Ya la tenía');
      const incoming = ReferenceData(
        publisher: 'Del archivo',
        doi: '10.1000/xyz',
      );

      final merged = mergeReferenceOnImport(current, incoming);

      expect(merged.publisher, 'Ya la tenía');
      expect(merged.doi, '10.1000/xyz');
    });

    test('«priorizar el archivo» invierte el orden', () {
      const current = ReferenceData(publisher: 'Ya la tenía');
      const incoming = ReferenceData(publisher: 'Del archivo');

      final merged = mergeReferenceOnImport(
        current,
        incoming,
        prioritizeIncoming: true,
      );

      expect(merged.publisher, 'Del archivo');
    });

    test('el tipo se trata como un solo dato', () {
      const current = ReferenceData(type: ReferenceType.book);
      const incoming = ReferenceData(type: ReferenceType.article);

      expect(
        mergeReferenceOnImport(current, incoming).type,
        ReferenceType.book,
      );
    });

    test(
      'las personas: la lista de quien va primero gana si no está vacía',
      () {
        const currentAuthor = Contributor(name: PersonName(family: 'García'));
        const incomingAuthor = Contributor(
          name: PersonName(family: 'Vargas Llosa'),
        );
        const current = ReferenceData(contributors: [currentAuthor]);
        const incoming = ReferenceData(contributors: [incomingAuthor]);

        final merged = mergeReferenceOnImport(current, incoming);

        expect(merged.contributors, [currentAuthor]);
      },
    );

    test('sin personas de quien va primero, se toman las del otro', () {
      const incomingAuthor = Contributor(name: PersonName(family: 'García'));
      const current = ReferenceData();
      const incoming = ReferenceData(contributors: [incomingAuthor]);

      final merged = mergeReferenceOnImport(current, incoming);

      expect(merged.contributors, [incomingAuthor]);
    });

    test('cubre los nueve campos, no solo los del ejemplo', () {
      const current = ReferenceData();
      const incoming = ReferenceData(
        containerTitle: 'Contenedor',
        publisherPlace: 'Buenos Aires',
        edition: '2.ª ed.',
        volume: '3',
        issue: '4',
        pages: '10-20',
        isbn: '9780306406157',
        issn: '0378-5955',
        citationKey: 'clave2020',
        publicationPrecision: PublicationPrecision.year,
      );

      final merged = mergeReferenceOnImport(current, incoming);

      expect(merged.containerTitle, 'Contenedor');
      expect(merged.publisherPlace, 'Buenos Aires');
      expect(merged.edition, '2.ª ed.');
      expect(merged.volume, '3');
      expect(merged.issue, '4');
      expect(merged.pages, '10-20');
      expect(merged.isbn, '9780306406157');
      expect(merged.issn, '0378-5955');
      expect(merged.citationKey, 'clave2020');
      expect(merged.publicationPrecision, PublicationPrecision.year);
    });

    test('sin nada en ninguno de los dos lados, queda vacía', () {
      const current = ReferenceData();
      const incoming = ReferenceData();

      expect(mergeReferenceOnImport(current, incoming).isEmpty, isTrue);
    });
  });
}
