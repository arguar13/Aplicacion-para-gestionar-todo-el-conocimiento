import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_parser.dart';

void main() {
  group('parseRis — un registro simple', () {
    test('lee tipo, título y año', () {
      final result = parseRis('''
TY  - BOOK
TI  - Computing Machinery and Intelligence
PY  - 1950///
ER  -
''');

      expect(result.entries, hasLength(1));
      final entry = result.entries.single;
      expect(entry.title, 'Computing Machinery and Intelligence');
      expect(entry.reference.type, ReferenceType.book);
      expect(entry.publishedAt, DateTime(1950));
      expect(entry.publicationPrecision, PublicationPrecision.year);
    });

    test('el espaciado antes del guion no importa', () {
      final result = parseRis('TY-BOOK\nTI-Sin espacios\nER-\n');

      expect(result.entries.single.title, 'Sin espacios');
    });

    test('una línea sin etiqueta suma a la del campo anterior', () {
      final result = parseRis('''
TY  - BOOK
TI  - Un título
      que sigue en la línea de abajo
ER  -
''');

      expect(
        result.entries.single.title,
        'Un título que sigue en la línea de abajo',
      );
    });

    test('varios registros, uno por cada TY...ER', () {
      final result = parseRis('''
TY  - BOOK
TI  - Primero
ER  -

TY  - JOUR
TI  - Segundo
ER  -
''');

      expect(result.entries, hasLength(2));
      expect(result.entries[0].title, 'Primero');
      expect(result.entries[1].title, 'Segundo');
    });

    test('sin ER al final del archivo, igual se toma lo que había', () {
      final result = parseRis('TY  - BOOK\nTI  - Sin cerrar\n');

      expect(result.entries.single.title, 'Sin cerrar');
    });
  });

  group('parseRis — nombres', () {
    test('varios autores, uno por línea AU', () {
      final result = parseRis('''
TY  - BOOK
AU  - García Márquez, Gabriel
AU  - Vargas Llosa, Mario
ER  -
''');

      final authors = result.entries.single.reference.contributors;
      expect(authors, hasLength(2));
      expect(authors[0].name.family, 'García Márquez');
      expect(authors[0].name.given, 'Gabriel');
      expect(authors[1].name.family, 'Vargas Llosa');
    });

    test('A2 es el editor, con su propio rol', () {
      final result = parseRis('''
TY  - CHAP
A2  - Editor, Alguna
ER  -
''');

      final editor = result.entries.single.reference.contributors.single;
      expect(editor.role, ContributorRole.editor);
      expect(editor.name.family, 'Editor');
    });

    test('un autor sin coma queda como apellido solo', () {
      final result = parseRis('TY  - BOOK\nAU  - Voltaire\nER  - \n');

      expect(
        result.entries.single.reference.contributors.single.name.family,
        'Voltaire',
      );
    });

    test('una coma final marca una institución', () {
      final result = parseRis('''
TY  - GEN
AU  - Organización Mundial de la Salud,
ER  -
''');

      final author = result.entries.single.reference.contributors.single;
      expect(author.name.isInstitution, isTrue);
      expect(author.name.family, 'Organización Mundial de la Salud');
    });
  });

  group('parseRis — tipos', () {
    test('CPAPER entra como artículo, con el contenedor del congreso', () {
      final result = parseRis('''
TY  - CPAPER
TI  - T
T2  - Actas del Congreso
ER  -
''');

      final entry = result.entries.single;
      expect(entry.reference.type, ReferenceType.article);
      expect(entry.reference.containerTitle, 'Actas del Congreso');
    });

    test('THES es una tesis', () {
      final result = parseRis('TY  - THES\nTI  - T\nER  - \n');

      expect(result.entries.single.reference.type, ReferenceType.thesis);
    });

    test('WEB es un sitio web', () {
      final result = parseRis('TY  - WEB\nUR  - https://ejemplo.org\nER  - \n');

      expect(result.entries.single.reference.type, ReferenceType.website);
      expect(result.entries.single.url, 'https://ejemplo.org');
    });

    test('un tipo que no está entre los nueve se salta y se informa', () {
      final result = parseRis('TY  - PAT\nTI  - Una patente\nER  - \n');

      expect(result.entries, isEmpty);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.type, 'PAT');
    });

    test('G1 distingue lo que GEN por sí solo no puede', () {
      final result = parseRis('''
TY  - GEN
TI  - T
G1  - documentary
ER  -
''');

      expect(result.entries.single.reference.type, ReferenceType.documentary);
    });

    test('G1 = none es una obra sin tipo, no "otro"', () {
      final result = parseRis('TY  - GEN\nTI  - T\nG1  - none\nER  - \n');

      expect(result.entries.single.reference.type, isNull);
    });
  });

  group('parseRis — páginas, identificadores y fecha de consulta', () {
    test('SP y EP se juntan en un solo rango', () {
      final result = parseRis('TY  - JOUR\nSP  - 45\nEP  - 67\nER  - \n');

      expect(result.entries.single.reference.pages, '45-67');
    });

    test('solo SP: una página suelta', () {
      final result = parseRis('TY  - JOUR\nSP  - e1234\nER  - \n');

      expect(result.entries.single.reference.pages, 'e1234');
    });

    test('SN se reconoce como ISBN si tiene esa forma', () {
      final result = parseRis('TY  - BOOK\nSN  - 0-306-40615-2\nER  - \n');

      expect(result.entries.single.reference.isbn, '9780306406157');
    });

    test('SN se reconoce como ISSN si tiene esa forma', () {
      final result = parseRis('TY  - JOUR\nSN  - 0378-5955\nER  - \n');

      expect(result.entries.single.reference.issn, '0378-5955');
    });

    test('DA llena la fecha de consulta, exigiendo los tres números', () {
      final result = parseRis('TY  - WEB\nDA  - 2021/01/15/\nER  - \n');

      expect(result.entries.single.reference.accessedAt, DateTime(2021, 1, 15));
    });

    test('un DA incompleto no llena la fecha de consulta', () {
      final result = parseRis('TY  - WEB\nDA  - 2021///\nER  - \n');

      expect(result.entries.single.reference.accessedAt, isNull);
    });
  });

  group('parseRis — fecha de publicación (PY)', () {
    test('solo el año', () {
      final result = parseRis('TY  - BOOK\nPY  - 2020///\nER  - \n');

      expect(result.entries.single.publishedAt, DateTime(2020));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.year,
      );
    });

    test('año y mes', () {
      final result = parseRis('TY  - BOOK\nPY  - 2020/03//\nER  - \n');

      expect(result.entries.single.publishedAt, DateTime(2020, 3));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.month,
      );
    });

    test('año, mes y día', () {
      final result = parseRis('TY  - BOOK\nPY  - 2020/05/14/\nER  - \n');

      expect(result.entries.single.publishedAt, DateTime(2020, 5, 14));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.day,
      );
    });

    test('G2 es sin fecha, no fecha desconocida', () {
      final result = parseRis('TY  - BOOK\nTI  - T\nG2  - true\nER  - \n');

      expect(result.entries.single.publishedAt, isNull);
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.undated,
      );
    });

    test('sin PY ni G2: fecha desconocida', () {
      final result = parseRis('TY  - BOOK\nTI  - T\nER  - \n');

      expect(result.entries.single.publishedAt, isNull);
      expect(result.entries.single.publicationPrecision, isNull);
    });
  });
}
