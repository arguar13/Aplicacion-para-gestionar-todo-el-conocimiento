import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/bibtex_entry.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_parser.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_writer.dart';

void main() {
  group('ida y vuelta — cada tipo propio, escribir y releer', () {
    // Incluye `null` (sin tipo, «hueco»): `writeBibtex`/`parseBibtex` deben
    // distinguirlo de `ReferenceType.other`, no solo los nueve con nombre.
    for (final type in [null, ...ReferenceType.values]) {
      test('${type?.name ?? "sin tipo"} vuelve igual', () {
        final original = BibtexEntry(
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
            // ISBN-13 válido (dígito de control correcto), ya normalizado
            // —así el analizador no lo cambia al releerlo—.
            isbn: '9780306406157',
            issn: '0378-5955',
            doi: '10.1000/xyz123',
            accessedAt: DateTime(2021, 1, 15),
          ),
        );

        final reparsed = parseBibtex(writeBibtex([original])).entries.single;

        expect(reparsed, original);
      });
    }

    test('una obra sin fecha (undated) vuelve sin fecha', () {
      const original = BibtexEntry(
        title: 'Sin fecha',
        publicationPrecision: PublicationPrecision.undated,
        reference: ReferenceData(citationKey: 'sinfecha'),
      );

      final reparsed = parseBibtex(writeBibtex([original])).entries.single;

      expect(reparsed, original);
    });

    test('una obra con fecha desconocida (nadie la cargó) vuelve igual', () {
      const original = BibtexEntry(
        title: 'Sin cargar la fecha',
        reference: ReferenceData(citationKey: 'sinfecha2'),
      );

      final reparsed = parseBibtex(writeBibtex([original])).entries.single;

      expect(reparsed, original);
    });

    test('una institución como autor vuelve como institución', () {
      const original = BibtexEntry(
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

      final reparsed = parseBibtex(writeBibtex([original])).entries.single;

      expect(reparsed, original);
    });

    test('varias entradas conservan cada una su propia clave única', () {
      const first = BibtexEntry(
        title: 'Primera',
        reference: ReferenceData(citationKey: 'mismo'),
      );
      const second = BibtexEntry(
        title: 'Segunda',
        reference: ReferenceData(citationKey: 'mismo'),
      );

      final result = parseBibtex(writeBibtex([first, second]));

      expect(result.entries, hasLength(2));
      expect(result.entries[0].reference.citationKey, 'mismo');
      expect(result.entries[1].reference.citationKey, 'mismoa');
      expect(result.entries[0].title, 'Primera');
      expect(result.entries[1].title, 'Segunda');
    });
  });

  group('ida y vuelta — un .bib externo, como lo escribiría otro programa', () {
    const external = r'''
@string{acm = "Association for Computing Machinery"}

% Nada de esto es una entrada: es comentario, como en BibTeX de verdad.
@article{turing1950computing,
  author    = {Turing, Alan M.},
  title     = {Computing Machinery and Intelligence},
  journal   = {Mind},
  year      = {1950},
  month     = oct,
  pages     = {433--460},
  publisher = acm,
}

@phdthesis{fulanez2019,
  author = {Fulánez, Mar{\'\i}a Jos{\'e}},
  title  = {Una tesis con acentos escritos a mano},
  school = {Universidad de Buenos Aires},
  year   = {2019},
}

@patent{cualquiera2020, title = {No es de los nueve tipos}}
''';

    test('lee las tres entradas reales y salta la patente', () {
      final result = parseBibtex(external);

      expect(result.entries, hasLength(2));
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.key, 'cualquiera2020');
    });

    test(
      'decodifica los acentos de LaTeX en un nombre partido en dos líneas',
      () {
        final result = parseBibtex(external);
        final thesis = result.entries.firstWhere(
          (e) => e.reference.citationKey == 'fulanez2019',
        );

        expect(thesis.reference.contributors.single.name.family, 'Fulánez');
        expect(thesis.reference.contributors.single.name.given, 'María José');
      },
    );

    test('resuelve la macro @string usada como valor del publisher', () {
      final result = parseBibtex(external);
      final article = result.entries.firstWhere(
        (e) => e.reference.citationKey == 'turing1950computing',
      );

      expect(
        article.reference.publisher,
        'Association for Computing Machinery',
      );
      expect(article.reference.pages, '433-460');
      expect(article.publishedAt, DateTime(1950, 10));
    });

    test('escribirlo de nuevo y releerlo da lo mismo la segunda vez', () {
      final firstPass = parseBibtex(external).entries;
      final secondPass = parseBibtex(writeBibtex(firstPass)).entries;
      final thirdPass = parseBibtex(writeBibtex(secondPass)).entries;

      expect(secondPass, thirdPass);
    });
  });
}
