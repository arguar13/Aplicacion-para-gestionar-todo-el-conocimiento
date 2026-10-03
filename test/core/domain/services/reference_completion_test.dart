import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/services/reference_completion.dart';

void main() {
  const garcia = Contributor(
    name: PersonName(family: 'García', given: 'Ana'),
  );
  const perez = Contributor(
    name: PersonName(family: 'Pérez', given: 'Luis'),
  );

  test('solo completa lo vacío: un texto en blanco cuenta como vacío, y lo '
      'que la lectura no trae queda', () {
    final completed = completeEmptyReference(
      current: ReferenceData(
        publisher: 'Sudamericana',
        edition: '  ',
        citationKey: 'garcia1967',
        accessedAt: DateTime(2024),
      ),
      publishedAt: null,
      found: const ExtractedMetadata(
        reference: ReferenceData(publisher: 'Otra', edition: '2.ª ed.'),
      ),
    );

    expect(
      completed.reference,
      ReferenceData(
        publisher: 'Sudamericana',
        edition: '2.ª ed.',
        citationKey: 'garcia1967',
        accessedAt: DateTime(2024),
      ),
    );
    expect(completed.publishedAt, isNull);
  });

  test('las personas van enteras o no van', () {
    final kept = completeEmptyReference(
      current: const ReferenceData(contributors: [garcia]),
      publishedAt: null,
      found: const ExtractedMetadata(
        reference: ReferenceData(contributors: [perez, garcia]),
      ),
    );
    final filled = completeEmptyReference(
      current: const ReferenceData(),
      publishedAt: null,
      found: const ExtractedMetadata(
        reference: ReferenceData(contributors: [perez, garcia]),
      ),
    );

    expect(kept.reference.contributors, [garcia]);
    expect(filled.reference.contributors, [perez, garcia]);
  });

  group('la fecha', () {
    final found = ExtractedMetadata(
      publishedAt: DateTime(2021, 3),
      publicationPrecision: PublicationPrecision.month,
    );

    test('vacía, se completa con su exactitud', () {
      final completed = completeEmptyReference(
        current: const ReferenceData(),
        publishedAt: null,
        found: found,
      );

      expect(completed.publishedAt, DateTime(2021, 3));
      expect(
        completed.reference.publicationPrecision,
        PublicationPrecision.month,
      );
    });

    test('la que hay manda, con su exactitud', () {
      final completed = completeEmptyReference(
        current: const ReferenceData(
          publicationPrecision: PublicationPrecision.year,
        ),
        publishedAt: DateTime(1967),
        found: found,
      );

      expect(completed.publishedAt, DateTime(1967));
      expect(
        completed.reference.publicationPrecision,
        PublicationPrecision.year,
      );
    });

    test('«sin fecha» también es algo que dijo la persona', () {
      final completed = completeEmptyReference(
        current: const ReferenceData(
          publicationPrecision: PublicationPrecision.undated,
        ),
        publishedAt: null,
        found: found,
      );

      expect(completed.publishedAt, isNull);
      expect(
        completed.reference.publicationPrecision,
        PublicationPrecision.undated,
      );
    });
  });
}
