import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_parser.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_writer.dart';

void main() {
  group('ida y vuelta — cada tipo propio, escribir y releer', () {
    // Incluye `null` (sin tipo, «hueco»): ver el mismo caso en BibTeX.
    for (final type in [null, ...ReferenceType.values]) {
      test('${type?.name ?? "sin tipo"} vuelve igual', () {
        final original = ImportedReference(
          title: 'Una obra de prueba',
          url: 'https://ejemplo.org/obra',
          publishedAt: DateTime(1970, 6, 15),
          publicationPrecision: PublicationPrecision.day,
          reference: ReferenceData(
            type: type,
            citationKey: 'clave1970',
            contributors: const [
              Contributor(
                name: PersonName(family: 'García', given: 'Ana'),
              ),
              Contributor(
                name: PersonName(family: 'Editor', given: 'Un'),
                role: ContributorRole.editor,
              ),
            ],
            containerTitle: 'El contenedor',
            publisher: 'Una editorial',
            publisherPlace: 'Buenos Aires',
            edition: '2.ª ed.',
            volume: '3',
            issue: '4',
            pages: '10-20',
            // ISBN-13 válido, ya normalizado —ver bibtex_round_trip_test—.
            isbn: '9780306406157',
            doi: '10.1000/xyz123',
            accessedAt: DateTime(2021, 1, 15),
          ),
        );

        final reparsed = parseRis(writeRis([original])).entries.single;

        expect(reparsed, original);
      });
    }

    test('el ISSN vuelve igual (SN comparte el campo con el ISBN)', () {
      const original = ImportedReference(
        title: 'Un artículo de revista',
        reference: ReferenceData(
          citationKey: 'revista2020',
          // ISSN válido —ver bibtex_round_trip_test—.
          issn: '0378-5955',
        ),
      );

      final reparsed = parseRis(writeRis([original])).entries.single;

      expect(reparsed, original);
    });

    test('una obra sin fecha (undated) vuelve sin fecha', () {
      const original = ImportedReference(
        title: 'Sin fecha',
        publicationPrecision: PublicationPrecision.undated,
        reference: ReferenceData(citationKey: 'sinfecha'),
      );

      final reparsed = parseRis(writeRis([original])).entries.single;

      expect(reparsed, original);
    });

    test('una obra con fecha desconocida (nadie la cargó) vuelve igual', () {
      const original = ImportedReference(
        title: 'Sin cargar la fecha',
        reference: ReferenceData(citationKey: 'sinfecha2'),
      );

      final reparsed = parseRis(writeRis([original])).entries.single;

      expect(reparsed, original);
    });

    test('una institución como autor vuelve como institución', () {
      const original = ImportedReference(
        title: 'Un informe',
        reference: ReferenceData(
          citationKey: 'oms2020',
          contributors: [
            Contributor(
              name: PersonName.institution('Organización Mundial de la Salud'),
            ),
          ],
        ),
      );

      final reparsed = parseRis(writeRis([original])).entries.single;

      expect(reparsed, original);
    });

    test('una página suelta (sin rango) vuelve igual', () {
      const original = ImportedReference(
        title: 'T',
        reference: ReferenceData(citationKey: 'x', pages: 'e1234'),
      );

      final reparsed = parseRis(writeRis([original])).entries.single;

      expect(reparsed.reference.pages, 'e1234');
    });

    test('varias entradas conservan cada una su propio ID único', () {
      const first = ImportedReference(
        title: 'Primera',
        reference: ReferenceData(citationKey: 'mismo'),
      );
      const second = ImportedReference(
        title: 'Segunda',
        reference: ReferenceData(citationKey: 'mismo'),
      );

      final result = parseRis(writeRis([first, second]));

      expect(result.entries, hasLength(2));
      expect(result.entries[0].reference.citationKey, 'mismo');
      expect(result.entries[1].reference.citationKey, 'mismoa');
    });
  });

  group('ida y vuelta — un .ris externo, como lo escribiría otro programa', () {
    const external = '''
TY  - JOUR
ID  - turing1950computing
AU  - Turing, Alan M.
TI  - Computing Machinery and Intelligence
T2  - Mind
PY  - 1950///
SP  - 433
EP  - 460
ER  -

TY  - THES
ID  - fulanez2019
AU  - Fulánez, María José
TI  - Una tesis cualquiera
PB  - Universidad de Buenos Aires
PY  - 2019///
ER  -

TY  - PAT
TI  - No es de los nueve tipos
ER  -
''';

    test('lee las dos entradas reales y salta la patente', () {
      final result = parseRis(external);

      expect(result.entries, hasLength(2));
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.type, 'PAT');
    });

    test('junta las páginas de SP/EP y arma bien el año', () {
      final result = parseRis(external);
      final article = result.entries.firstWhere(
        (e) => e.reference.citationKey == 'turing1950computing',
      );

      expect(article.reference.pages, '433-460');
      expect(article.publishedAt, DateTime(1950));
    });

    test('escribirlo de nuevo y releerlo da lo mismo la segunda vez', () {
      final firstPass = parseRis(external).entries;
      final secondPass = parseRis(writeRis(firstPass)).entries;
      final thirdPass = parseRis(writeRis(secondPass)).entries;

      expect(secondPass, thirdPass);
    });
  });
}
