import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

void main() {
  group('isEmpty', () {
    test('sin nada, vacio', () {
      expect(const ExtractedMetadata().isEmpty, isTrue);
    });

    test('con un titulo, no vacio', () {
      expect(const ExtractedMetadata(title: 'Algo').isEmpty, isFalse);
    });

    test('con un titulo en blanco, vacio', () {
      expect(const ExtractedMetadata(title: '   ').isEmpty, isTrue);
    });

    test('con una fecha, no vacio', () {
      expect(ExtractedMetadata(publishedAt: DateTime(2020)).isEmpty, isFalse);
    });

    test('con un dato de la referencia, no vacio', () {
      expect(
        const ExtractedMetadata(
          reference: ReferenceData(doi: '10.1000/xyz'),
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('mergeExtractedMetadata', () {
    test('el primero que trae cada dato gana, campo por campo', () {
      const first = ExtractedMetadata(
        title: 'Titulo del primero',
        reference: ReferenceData(doi: '10.1000/uno'),
      );
      const second = ExtractedMetadata(
        title: 'Titulo del segundo',
        reference: ReferenceData(doi: '10.1000/dos', isbn: '9780000000002'),
      );

      final merged = mergeExtractedMetadata([first, second]);

      expect(merged.title, 'Titulo del primero');
      expect(merged.reference.doi, '10.1000/uno');
      // El segundo aporta lo que el primero no traia.
      expect(merged.reference.isbn, '9780000000002');
    });

    test('las personas no se mezclan: gana la primera lista no vacia', () {
      const first = ExtractedMetadata(
        reference: ReferenceData(
          contributors: [Contributor(name: PersonName(family: 'Uno'))],
        ),
      );
      const second = ExtractedMetadata(
        reference: ReferenceData(
          contributors: [Contributor(name: PersonName(family: 'Dos'))],
        ),
      );

      final merged = mergeExtractedMetadata([first, second]);

      expect(merged.reference.contributors.single.name.family, 'Uno');
    });

    test('una fecha vacia en el primero deja pasar la del segundo', () {
      const first = ExtractedMetadata();
      final second = ExtractedMetadata(
        publishedAt: DateTime(2020, 5),
        publicationPrecision: PublicationPrecision.month,
      );

      final merged = mergeExtractedMetadata([first, second]);

      expect(merged.publishedAt, DateTime(2020, 5));
      expect(merged.publicationPrecision, PublicationPrecision.month);
    });

    test('lista vacia junta a nada', () {
      expect(mergeExtractedMetadata(const []).isEmpty, isTrue);
    });
  });
}
