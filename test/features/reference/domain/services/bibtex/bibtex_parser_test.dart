import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_parser.dart';

void main() {
  group('parseBibtex — una entrada simple', () {
    test('lee tipo, clave y campos entre llaves', () {
      final result = parseBibtex('''
@book{turing1950,
  title = {Computing Machinery and Intelligence},
  author = {Turing, Alan},
  year = {1950},
}
''');

      expect(result.entries, hasLength(1));
      final entry = result.entries.single;
      expect(entry.title, 'Computing Machinery and Intelligence');
      expect(entry.reference.type, ReferenceType.book);
      expect(entry.reference.citationKey, 'turing1950');
      expect(entry.reference.contributors.single.name.family, 'Turing');
      expect(entry.reference.contributors.single.name.given, 'Alan');
      expect(entry.publishedAt, DateTime(1950));
      expect(entry.publicationPrecision, PublicationPrecision.year);
    });

    test('los campos entre comillas valen igual que entre llaves', () {
      final result = parseBibtex('''
@misc{x,
  title = "Un título entre comillas",
}
''');

      expect(result.entries.single.title, 'Un título entre comillas');
    });

    test('el nombre y el tipo de la entrada no distinguen mayúsculas', () {
      final result = parseBibtex('@ARTICLE{x, Title = {Algo}}');

      expect(result.entries.single.title, 'Algo');
      expect(result.entries.single.reference.type, ReferenceType.article);
    });

    test('lo que hay fuera de una entrada es comentario, se ignora', () {
      final result = parseBibtex('''
Esto es un comentario suelto, como en BibTeX de verdad.
@misc{x, title = {Adentro}}
Y esto también.
''');

      expect(result.entries.single.title, 'Adentro');
    });

    test('@comment y @preamble se ignoran sin generar una entrada', () {
      final result = parseBibtex('''
@comment{lo que sea, con "comillas" y {llaves} adentro}
@preamble{"algo de LaTeX"}
@misc{x, title = {La única}}
''');

      expect(result.entries, hasLength(1));
      expect(result.entries.single.title, 'La única');
    });

    test('una coma dentro de un título entre llaves no corta el campo', () {
      final result = parseBibtex('@misc{x, title = {Antes, coma, y después}}');

      expect(result.entries.single.title, 'Antes, coma, y después');
    });
  });

  group('parseBibtex — macros (@string)', () {
    test('una macro definida se expande donde se usa, sin comillas', () {
      final result = parseBibtex('''
@string{acm = "Association for Computing Machinery"}
@misc{x, publisher = acm}
''');

      expect(
        result.entries.single.reference.publisher,
        'Association for Computing Machinery',
      );
    });

    test('la concatenación con # junta las partes', () {
      final result = parseBibtex('''
@string{acm = "ACM"}
@misc{x, title = "Publicado por " # acm # ", 1950"}
''');

      expect(result.entries.single.title, 'Publicado por ACM, 1950');
    });

    test('una macro puede referenciar otra ya definida', () {
      final result = parseBibtex('''
@string{first = "National"}
@string{full = first # " Science Foundation"}
@misc{x, publisher = full}
''');

      expect(
        result.entries.single.reference.publisher,
        'National Science Foundation',
      );
    });

    test('un identificador sin definir se conserva tal cual, sin romper', () {
      final result = parseBibtex('@misc{x, note = sinDefinir}');

      expect(result.entries, hasLength(1));
    });
  });

  group('parseBibtex — nombres', () {
    test('varios autores, separados por " and "', () {
      final result = parseBibtex(
        '@book{x, author = {García Márquez, Gabriel and Vargas Llosa, Mario}}',
      );

      final authors = result.entries.single.reference.contributors;
      expect(authors, hasLength(2));
      expect(authors[0].name.family, 'García Márquez');
      expect(authors[1].name.family, 'Vargas Llosa');
    });

    test('un nombre entre llaves dobles es una institución', () {
      final result = parseBibtex(
        '@misc{x, author = {{Organización Mundial de la Salud}}}',
      );

      final author = result.entries.single.reference.contributors.single;
      expect(author.name.isInstitution, isTrue);
      expect(author.name.family, 'Organización Mundial de la Salud');
    });

    test('las llaves protegen el "and" de un nombre compuesto', () {
      final result = parseBibtex('@book{x, author = {{Barnes and Noble}}}');

      final author = result.entries.single.reference.contributors.single;
      expect(author.name.family, 'Barnes and Noble');
    });

    test('el editor se lee con su propio rol', () {
      final result = parseBibtex('@incollection{x, editor = {Editor, Alguna}}');

      final editor = result.entries.single.reference.contributors.single;
      expect(editor.role, ContributorRole.editor);
      expect(editor.name.family, 'Editor');
    });

    test('los acentos de LaTeX de un nombre se decodifican', () {
      final result = parseBibtex(r"@book{x, author = {Gonz\'alez, Juan}}");

      expect(
        result.entries.single.reference.contributors.single.name.given,
        'Juan',
      );
      expect(
        result.entries.single.reference.contributors.single.name.family,
        'González',
      );
    });
  });

  group('parseBibtex — tipos', () {
    test(
      'inproceedings entra como artículo, con el contenedor del congreso',
      () {
        final result = parseBibtex(
          '@inproceedings{x, title = {T}, booktitle = {Actas del Congreso}}',
        );

        final entry = result.entries.single;
        expect(entry.reference.type, ReferenceType.article);
        expect(entry.reference.containerTitle, 'Actas del Congreso');
      },
    );

    test(
      'phdthesis y mastersthesis son tesis, con la universidad de school',
      () {
        final result = parseBibtex(
          '@phdthesis{x, title = {T}, school = {Universidad de Buenos Aires}}',
        );

        final entry = result.entries.single;
        expect(entry.reference.type, ReferenceType.thesis);
        expect(entry.reference.publisher, 'Universidad de Buenos Aires');
      },
    );

    test('online es un sitio web', () {
      final result = parseBibtex(
        '@online{x, title = {T}, url = {https://ejemplo.org}}',
      );

      expect(result.entries.single.reference.type, ReferenceType.website);
      expect(result.entries.single.url, 'https://ejemplo.org');
    });

    test('un tipo que no está entre los nueve se salta y se informa', () {
      final result = parseBibtex('@patent{x, title = {Una patente}}');

      expect(result.entries, isEmpty);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.key, 'x');
      expect(result.skipped.single.type, 'patent');
    });

    test(
      'un campo sinapsis-type distingue lo que @misc por sí solo no puede',
      () {
        final result = parseBibtex(
          '@misc{x, title = {T}, sinapsis-type = {documentary}}',
        );

        expect(result.entries.single.reference.type, ReferenceType.documentary);
      },
    );

    test('sinapsis-type = none es una obra sin tipo, no "otro"', () {
      final result = parseBibtex(
        '@misc{x, title = {T}, sinapsis-type = {none}}',
      );

      expect(result.entries.single.reference.type, isNull);
    });
  });

  group('parseBibtex — identificadores', () {
    test('un DOI válido se normaliza', () {
      final result = parseBibtex(
        '@misc{x, doi = {https://doi.org/10.1000/xyz123}}',
      );

      expect(result.entries.single.reference.doi, '10.1000/xyz123');
    });

    test('un DOI inválido no se guarda, sin hacer fallar la entrada', () {
      final result = parseBibtex('@misc{x, title = {T}, doi = {no es un doi}}');

      expect(result.entries.single.reference.doi, isNull);
      expect(result.entries.single.title, 'T');
    });

    test('un ISBN con guiones se normaliza a ISBN-13', () {
      final result = parseBibtex('@book{x, isbn = {0-306-40615-2}}');

      expect(result.entries.single.reference.isbn, isNotNull);
    });

    test('las páginas con doble guion se normalizan a uno solo', () {
      final result = parseBibtex('@article{x, pages = {45--67}}');

      expect(result.entries.single.reference.pages, '45-67');
    });
  });

  group('parseBibtex — el adjunto (F15, D14)', () {
    test('un nombre de archivo pelado', () {
      final result = parseBibtex('@misc{x, file = {articulo.pdf}}');

      expect(result.entries.single.attachmentFileName, 'articulo.pdf');
    });

    test('la forma de JabRef, con la ruta completa', () {
      final result = parseBibtex(
        r'@misc{x, file = {:C:\Users\ana\articulo.pdf:PDF}}',
      );

      expect(result.entries.single.attachmentFileName, 'articulo.pdf');
    });

    test('sin campo file: sin adjunto, sin romper', () {
      final result = parseBibtex('@misc{x, title = {T}}');

      expect(result.entries.single.attachmentFileName, isNull);
    });
  });

  group('parseBibtex — fecha', () {
    test('solo el año: precisión de año', () {
      final result = parseBibtex('@misc{x, year = {2020}}');

      expect(result.entries.single.publishedAt, DateTime(2020));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.year,
      );
    });

    test('año y mes con el nombre del mes: precisión de mes', () {
      final result = parseBibtex('@misc{x, year = {2020}, month = mar}');

      expect(result.entries.single.publishedAt, DateTime(2020, 3));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.month,
      );
    });

    test('el campo date con año-mes-día: precisión de día', () {
      final result = parseBibtex('@misc{x, date = {2020-05-14}}');

      expect(result.entries.single.publishedAt, DateTime(2020, 5, 14));
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.day,
      );
    });

    test('sinapsis-undated: sin fecha, no fecha desconocida', () {
      final result = parseBibtex(
        '@misc{x, title = {T}, sinapsis-undated = {true}}',
      );

      expect(result.entries.single.publishedAt, isNull);
      expect(
        result.entries.single.publicationPrecision,
        PublicationPrecision.undated,
      );
    });

    test('sin year ni date: fecha desconocida', () {
      final result = parseBibtex('@misc{x, title = {T}}');

      expect(result.entries.single.publishedAt, isNull);
      expect(result.entries.single.publicationPrecision, isNull);
    });

    test('urldate llena la fecha de consulta', () {
      final result = parseBibtex('@online{x, urldate = {2021-01-15}}');

      expect(result.entries.single.reference.accessedAt, DateTime(2021, 1, 15));
    });
  });
}
