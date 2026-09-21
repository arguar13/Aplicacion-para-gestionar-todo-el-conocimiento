import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/citations/domain/services/styles/mla9_style.dart';

/// MLA 9.ª edición (F15). Los esquemas siguen el MLA Handbook: los ejemplos en
/// inglés se armaron con los datos de los que trae la guía —el libro de
/// Gilbert y Gubar, el artículo de Duvall, la traducción de la *Odisea*—,
/// escritos con las páginas completas; los demás, el mismo esquema en español.
void main() {
  const style = Mla9Style();

  Contributor person(
    String family,
    String given, {
    ContributorRole role = ContributorRole.author,
  }) => Contributor(
    name: PersonName(family: family, given: given),
    role: role,
  );

  Contributor institution(String name) =>
      Contributor(name: PersonName.institution(name));

  CitationSource source({
    String title = 'Un título',
    ReferenceType? type,
    List<Contributor> people = const [],
    String? publisher,
    String? container,
    String? edition,
    String? volume,
    String? issue,
    String? pages,
    String? doi,
    String? url,
    PublicationDate? date,
    String? authorName,
    SourceKind? kind,
    DateTime? accessedAt,
    DateTime? capturedAt,
  }) => CitationSource(
    title: title,
    reference: ReferenceData(
      type: type,
      contributors: people,
      publisher: publisher,
      containerTitle: container,
      edition: edition,
      volume: volume,
      issue: issue,
      pages: pages,
      doi: doi,
      accessedAt: accessedAt,
    ),
    date: date ?? PublicationDate.ofYear(2019),
    url: url,
    authorName: authorName,
    kind: kind,
    capturedAt: capturedAt,
  );

  Citation reference(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
  }) => style.format(
    CitationForm.reference,
    source,
    CitationContext(language: language),
  );

  String plain(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
  }) => reference(source, language: language).toPlainText();

  Citation inText(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    CitationLocator? locator,
  }) => style.format(
    CitationForm.inText,
    source,
    CitationContext(language: language, locator: locator),
  );

  const es = CitationLanguage.es;

  group('el estilo', () {
    test('se llama MLA 9 y está segundo en el registro', () {
      expect(style.id, 'mla9');
      expect(style.name, 'MLA 9');
      expect(kReferenceStyles.byId('mla9'), isA<Mla9Style>());
      expect(kReferenceStyles.styles[1].id, 'mla9');
    });

    test('tiene la referencia y la cita en el texto, no notas', () {
      expect(style.forms, {CitationForm.reference, CitationForm.inText});
      final s = source(type: ReferenceType.book, publisher: 'X');

      expect(
        style.format(CitationForm.note, s, const CitationContext()).isEmpty,
        isTrue,
      );
      expect(
        style
            .format(CitationForm.shortNote, s, const CitationContext())
            .isEmpty,
        isTrue,
      );
    });

    test('no numera sus entradas ni lleva el año detrás del autor', () {
      expect(style.isNumbered, isFalse);
      expect(style.isAuthorDate, isFalse);
    });

    test('titula su lista «Obras citadas» o «Works Cited»', () {
      expect(style.listTitle(CitationLanguage.es), 'Obras citadas');
      expect(style.listTitle(CitationLanguage.en), 'Works Cited');
    });

    test('la letra del año no le importa', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );
      const suffixed = CitationContext(yearSuffix: 'a');

      expect(
        style.format(CitationForm.reference, book, suffixed).toPlainText(),
        style
            .format(CitationForm.reference, book, const CitationContext())
            .toPlainText(),
      );
    });
  });

  group('los esquemas de la guía, en inglés', () {
    test('un libro de dos autoras, con su edición', () {
      final book = source(
        title:
            'The Madwoman in the Attic: The Woman Writer and the '
            'Nineteenth-Century Literary Imagination',
        type: ReferenceType.book,
        people: [person('Gilbert', 'Sandra M.'), person('Gubar', 'Susan')],
        publisher: 'Yale UP',
        edition: '2',
        date: PublicationDate.ofYear(2000),
      );

      expect(
        plain(book),
        'Gilbert, Sandra M., and Susan Gubar. The Madwoman in the Attic: The '
        'Woman Writer and the Nineteenth-Century Literary Imagination. 2nd '
        'ed., Yale UP, 2000.',
      );
      expect(
        reference(book).toMarkdown(),
        startsWith(
          'Gilbert, Sandra M., and Susan Gubar. *The Madwoman in the Attic: '
          'The Woman Writer and the Nineteenth-Century Literary '
          'Imagination*. 2nd ed.,',
        ),
      );
      expect(reference(book).hasGaps, isFalse);
    });

    test('una traducción: «Translated by» después del título', () {
      final book = source(
        title: 'The Odyssey',
        type: ReferenceType.book,
        people: [
          const Contributor(name: PersonName(family: 'Homer')),
          person('Fagles', 'Robert', role: ContributorRole.translator),
        ],
        publisher: 'Penguin Books',
        date: PublicationDate.ofYear(1996),
      );

      expect(
        plain(book),
        'Homer. The Odyssey. Translated by Robert Fagles, Penguin Books, 1996.',
      );
    });

    test('un artículo de revista', () {
      final article = source(
        title:
            'The (Super)Marketplace of Images: Television as Unmediated '
            'Mediation in DeLillo’s White Noise',
        type: ReferenceType.article,
        people: [person('Duvall', 'John N.')],
        container: 'Arizona Quarterly',
        volume: '50',
        issue: '3',
        pages: '127-153',
        date: PublicationDate.ofYear(1994),
      );

      expect(
        plain(article),
        'Duvall, John N. “The (Super)Marketplace of Images: Television as '
        'Unmediated Mediation in DeLillo’s White Noise.” Arizona Quarterly, '
        'vol. 50, no. 3, 1994, pp. 127-153.',
      );
      // La revista, en cursiva; el título del artículo, entre comillas.
      expect(
        reference(article).toMarkdown(),
        contains('Noise.” *Arizona Quarterly*, vol. 50'),
      );
    });

    test('un capítulo de un libro editado: «et al.» con muchos editores', () {
      final chapter = source(
        title: 'Encoding/Decoding',
        type: ReferenceType.chapter,
        people: [
          person('Hall', 'Stuart'),
          person('Hall', 'Stuart', role: ContributorRole.editor),
          person('Hobson', 'Dorothy', role: ContributorRole.editor),
          person('Lowe', 'Andrew', role: ContributorRole.editor),
          person('Willis', 'Paul', role: ContributorRole.editor),
        ],
        container: 'Culture, Media, Language',
        publisher: 'Hutchinson',
        pages: '128-138',
        date: PublicationDate.ofYear(1980),
      );

      expect(
        plain(chapter),
        'Hall, Stuart. “Encoding/Decoding.” Culture, Media, Language, edited '
        'by Stuart Hall et al., Hutchinson, 1980, pp. 128-138.',
      );
    });

    test('una página de un sitio, con su editorial y su fecha completa', () {
      final page = source(
        title: 'How to Make Vegetarian Chili',
        type: ReferenceType.website,
        people: [person('Lundman', 'Susan')],
        container: 'eHow',
        publisher: 'Demand Media',
        date: PublicationDate.ofDay(2010, 5, 20),
        url: 'https://www.ehow.com/how_10727_make-vegetarian-chili.html',
      );

      expect(
        plain(page),
        'Lundman, Susan. “How to Make Vegetarian Chili.” eHow, Demand Media, '
        '20 May 2010, www.ehow.com/how_10727_make-vegetarian-chili.html.',
      );
    });

    test('una película: por su director, con «director» después', () {
      final film = source(
        title: 'Dune',
        type: ReferenceType.documentary,
        people: [person('Villeneuve', 'Denis', role: ContributorRole.director)],
        publisher: 'Warner Bros.',
        date: PublicationDate.ofYear(2021),
      );

      expect(
        plain(film),
        'Villeneuve, Denis, director. Dune. Warner Bros., 2021.',
      );
    });

    test('un video de YouTube: el canal entero, el título entre comillas', () {
      final video = source(
        title: 'What is the tallest tower possible?',
        kind: SourceKind.youtube,
        authorName: 'Kurzgesagt – In a Nutshell',
        date: PublicationDate.ofDay(2020, 3, 5),
        url: 'https://www.youtube.com/watch?v=abc123',
      );

      expect(
        plain(video),
        'Kurzgesagt – In a Nutshell. “What is the tallest tower possible?” '
        'YouTube, 5 Mar. 2020, www.youtube.com/watch?v=abc123.',
      );
    });

    test('una tesis: el título entre comillas, el año y la universidad', () {
      final thesis = source(
        title: 'Instructional leadership perceptions',
        type: ReferenceType.thesis,
        people: [person('Harris', 'Lisa')],
        publisher: 'University of Virginia',
        date: PublicationDate.ofYear(2014),
      );

      // La guía dice «PhD dissertation»: esta versión no guarda el grado.
      expect(
        plain(thesis),
        'Harris, Lisa. “Instructional leadership perceptions.” 2014. '
        'University of Virginia, thesis.',
      );
    });
  });

  group('en español', () {
    test('un libro', () {
      final book = source(
        title: 'Cien años de soledad',
        type: ReferenceType.book,
        people: [person('García Márquez', 'Gabriel')],
        publisher: 'Sudamericana',
        edition: '2',
        date: PublicationDate.ofYear(1967),
      );

      expect(
        plain(book, language: es),
        'García Márquez, Gabriel. Cien años de soledad. 2.ª ed., Sudamericana, '
        '1967.',
      );
    });

    test('dos autores: «y», con la coma de la estructura de MLA', () {
      final book = source(
        title: 'El olor de la guayaba',
        type: ReferenceType.book,
        people: [
          person('García Márquez', 'Gabriel'),
          person('Mendoza', 'Plinio Apuleyo'),
        ],
        publisher: 'Oveja Negra',
        date: PublicationDate.ofYear(1982),
      );

      expect(
        plain(book, language: es),
        'García Márquez, Gabriel, y Plinio Apuleyo Mendoza. El olor de la '
        'guayaba. Oveja Negra, 1982.',
      );
    });

    test('«e» delante de un nombre que empieza con «i»', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Paz', 'Octavio'), person('López', 'Irene')],
        publisher: 'Editorial',
      );

      expect(
        plain(book, language: es),
        startsWith('Paz, Octavio, e Irene López. '),
      );
    });

    test('un capítulo: comillas angulares, el punto afuera y «edición de»', () {
      final chapter = source(
        title: 'La novela hispanoamericana',
        type: ReferenceType.chapter,
        people: [
          person('Fuentes', 'Carlos'),
          person('Franco', 'Jean', role: ContributorRole.editor),
        ],
        container: 'Historia de la literatura',
        pages: '120-145',
        publisher: 'Fondo de Cultura Económica',
        date: PublicationDate.ofYear(1969),
      );

      expect(
        plain(chapter, language: es),
        'Fuentes, Carlos. «La novela hispanoamericana». Historia de la '
        'literatura, edición de Jean Franco, Fondo de Cultura Económica, '
        '1969, pp. 120-145.',
      );
    });

    test('una traducción: «Traducción de», con mayúscula al empezar', () {
      final book = source(
        title: 'Ana Karenina',
        type: ReferenceType.book,
        people: [
          person('Tolstói', 'León'),
          person('Cansinos', 'Rafael', role: ContributorRole.translator),
        ],
        publisher: 'Aguilar',
        date: PublicationDate.ofYear(1961),
      );

      expect(
        plain(book, language: es),
        'Tolstói, León. Ana Karenina. Traducción de Rafael Cansinos, Aguilar, '
        '1961.',
      );
    });

    test('una tesis', () {
      final thesis = source(
        title: 'Redes de citación',
        type: ReferenceType.thesis,
        people: [person('Ruiz', 'Ana')],
        publisher: 'Universidad de Chile',
        date: PublicationDate.ofYear(2014),
      );

      expect(
        plain(thesis, language: es),
        'Ruiz, Ana. «Redes de citación». 2014. Universidad de Chile, tesis.',
      );
    });

    test('un documental: el director con «dir.» y dos con «dirs.»', () {
      final one = source(
        title: 'La ciudad fantasma',
        type: ReferenceType.documentary,
        people: [person('Ruiz', 'Ana', role: ContributorRole.director)],
        publisher: 'Producciones Sur',
        date: PublicationDate.ofYear(2015),
      );
      final two = source(
        title: 'La ciudad fantasma',
        type: ReferenceType.documentary,
        people: [
          person('Ruiz', 'Ana', role: ContributorRole.director),
          person('Soto', 'Luis', role: ContributorRole.director),
        ],
        date: PublicationDate.ofYear(2015),
      );

      expect(
        plain(one, language: es),
        'Ruiz, Ana, dir. La ciudad fantasma. Producciones Sur, 2015.',
      );
      expect(
        plain(two, language: es),
        'Ruiz, Ana, y Luis Soto, dirs. La ciudad fantasma. 2015.',
      );
    });

    test('una fuente primaria', () {
      final letter = source(
        title: 'Carta a Luis de Santángel',
        type: ReferenceType.primarySource,
        people: [person('Colón', 'Cristóbal')],
        publisher: 'Archivo General de Indias',
        date: PublicationDate.ofYear(1493),
      );

      expect(
        plain(letter, language: es),
        'Colón, Cristóbal. Carta a Luis de Santángel. Archivo General de '
        'Indias, 1493.',
      );
    });

    test('una publicación en red, con la fecha de consulta que cargaron', () {
      final post = source(
        title: 'Una entrada sobre citas',
        type: ReferenceType.onlinePublication,
        people: [person('Pérez', 'Juana')],
        container: 'Blog de Sinapsis',
        date: PublicationDate.ofDay(2020, 6, 1),
        url: 'https://blog.example.org/entrada',
        accessedAt: DateTime(2026, 9, 5),
      );

      expect(
        plain(post, language: es),
        'Pérez, Juana. «Una entrada sobre citas». Blog de Sinapsis, 1 jun. '
        '2020, blog.example.org/entrada. Consultado el 5 sept. 2026.',
      );
    });
  });

  group('lo que falta se marca, no se inventa ni se omite', () {
    test('un año que nadie cargó es un hueco; «sin fecha» es otra cosa', () {
      final unknown = reference(
        source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
          date: const PublicationDate.unknown(),
        ),
        language: es,
      );
      final undated = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        date: const PublicationDate.undated(),
      );

      expect(
        unknown.toPlainText(),
        'García, Ana. Un título. Editorial, [falta: año].',
      );
      expect(unknown.gaps, [CitationGap.year]);
      expect(
        plain(undated, language: es),
        'García, Ana. Un título. Editorial, s. f.',
      );
      expect(plain(undated), 'García, Ana. Un título. Editorial, n.d.');
    });

    test('sin autor', () {
      final citation = reference(
        source(type: ReferenceType.book, publisher: 'Editorial'),
        language: es,
      );

      expect(
        citation.toPlainText(),
        '[falta: autor]. Un título. Editorial, 2019.',
      );
      expect(citation.gaps, [CitationGap.author]);
    });

    test('sin título', () {
      final book = reference(
        source(
          title: '  ',
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
        language: es,
      );
      final chapter = reference(
        source(
          title: '',
          type: ReferenceType.chapter,
          people: [person('García', 'Ana')],
          container: 'Libro',
          publisher: 'Editorial',
        ),
        language: es,
      );

      expect(book.gaps, [CitationGap.title]);
      expect(
        book.toPlainText(),
        'García, Ana. [falta: título]. Editorial, 2019.',
      );
      expect(chapter.gaps, [CitationGap.title]);
      expect(
        chapter.toPlainText(),
        'García, Ana. [falta: título]. Libro, Editorial, 2019.',
      );
    });

    test('un libro sin editorial', () {
      final citation = reference(
        source(type: ReferenceType.book, people: [person('García', 'Ana')]),
        language: es,
      );

      expect(
        citation.toPlainText(),
        'García, Ana. Un título. [falta: editorial], 2019.',
      );
      expect(citation.gaps, [CitationGap.publisher]);
    });

    test('un capítulo sin el libro que lo contiene', () {
      final citation = reference(
        source(
          type: ReferenceType.chapter,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
        language: es,
      );

      expect(citation.gaps, [CitationGap.container]);
      expect(
        citation.toPlainText(),
        'García, Ana. «Un título». [falta: publicado en], Editorial, 2019.',
      );
    });

    test('un artículo sin revista; sin volumen no se marca nada', () {
      final citation = reference(
        source(type: ReferenceType.article, people: [person('García', 'Ana')]),
      );

      expect(citation.gaps, [CitationGap.container]);
      expect(
        citation.toPlainText(),
        'García, Ana. “Un título.” [missing: published in], 2019.',
      );
    });

    test('una tesis sin universidad', () {
      final citation = reference(
        source(type: ReferenceType.thesis, people: [person('García', 'Ana')]),
        language: es,
      );

      expect(citation.gaps, [CitationGap.publisher]);
      expect(
        citation.toPlainText(),
        'García, Ana. «Un título». 2019. [falta: editorial], tesis.',
      );
    });

    test('una página web sin enlace', () {
      final citation = reference(
        source(type: ReferenceType.website, people: [institution('OMS')]),
        language: es,
      );

      expect(citation.gaps, [CitationGap.link]);
      expect(citation.toPlainText(), 'OMS. Un título. 2019, [falta: enlace].');
    });

    test('sin tipo de obra: la forma general y el hueco', () {
      final citation = reference(
        source(people: [person('García', 'Ana')], publisher: 'Editorial'),
        language: es,
      );

      expect(citation.gaps, [CitationGap.type]);
      expect(
        citation.toPlainText(),
        'García, Ana. Un título [falta: tipo de obra]. Editorial, 2019.',
      );
    });

    test('un documento suelto no tiene tipo; una página web sí, sola', () {
      final page = source(
        people: [institution('OMS')],
        kind: SourceKind.webPage,
        url: 'https://oms.org/x',
      );
      final document = source(
        people: [institution('OMS')],
        kind: SourceKind.document,
      );

      expect(reference(page).gaps, isEmpty);
      expect(reference(document).gaps, [CitationGap.type]);
    });

    test('en inglés dicen lo mismo con sus palabras', () {
      final citation = reference(
        source(type: ReferenceType.book, date: const PublicationDate.unknown()),
      );

      expect(citation.gaps, [
        CitationGap.author,
        CitationGap.publisher,
        CitationGap.year,
      ]);
      expect(
        citation.toPlainText(),
        '[missing: author]. Un título. [missing: publisher], [missing: year].',
      );
    });

    test('lo opcional que falta no se marca: un libro sin volumen', () {
      final citation = reference(
        source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
      );

      expect(citation.hasGaps, isFalse);
    });
  });

  group('el enlace', () {
    test('el DOI gana sobre la dirección y se escribe como enlace', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        doi: '10.1000/xyz',
        url: 'https://otro.org',
      );

      expect(
        plain(book),
        'García, Ana. Un título. Editorial, 2019, '
        'https://doi.org/10.1000/xyz.',
      );
    });

    test('una dirección va sin «https://» ni «http://»', () {
      String linked(String url) => plain(
        source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
          url: url,
        ),
      );

      expect(
        linked('https://otro.org/libro'),
        endsWith('2019, otro.org/libro.'),
      );
      expect(
        linked('http://otro.org/libro'),
        endsWith('2019, otro.org/libro.'),
      );
      expect(
        linked('HTTPS://otro.org/libro'),
        endsWith('2019, otro.org/libro.'),
      );
    });

    test('la fecha de consulta que alguien cargó se escribe', () {
      final page = source(
        title: 'Un artículo',
        type: ReferenceType.website,
        people: [person('Pérez', 'Juana')],
        container: 'Sitio',
        date: PublicationDate.ofDay(2020, 3, 15),
        url: 'https://sitio.org/a',
        accessedAt: DateTime(2026, 9, 5),
      );

      expect(
        plain(page),
        'Pérez, Juana. “Un artículo.” Sitio, 15 Mar. 2020, sitio.org/a. '
        'Accessed 5 Sept. 2026.',
      );
    });

    test(
      'sin fecha de publicación, la de captura hace de fecha de consulta',
      () {
        final unknown = source(
          type: ReferenceType.website,
          people: [person('Pérez', 'Juana')],
          date: const PublicationDate.unknown(),
          url: 'https://sitio.org/a',
          capturedAt: DateTime(2026, 9, 5),
        );
        final undated = source(
          type: ReferenceType.website,
          people: [person('Pérez', 'Juana')],
          date: const PublicationDate.undated(),
          url: 'https://sitio.org/a',
          capturedAt: DateTime(2026, 9, 5),
        );

        expect(
          plain(unknown),
          endsWith('[missing: year], sitio.org/a. Accessed 5 Sept. 2026.'),
        );
        expect(
          plain(undated, language: es),
          endsWith('s. f., sitio.org/a. Consultado el 5 sept. 2026.'),
        );
      },
    );

    test('con fecha de publicación, la de captura no se escribe', () {
      final page = source(
        type: ReferenceType.website,
        people: [person('Pérez', 'Juana')],
        url: 'https://sitio.org/a',
        capturedAt: DateTime(2026, 9, 5),
      );

      expect(plain(page), isNot(contains('Accessed')));
      expect(plain(page), endsWith('2019, sitio.org/a.'));
    });

    test('un DOI no lleva fecha de consulta, ni siquiera cargada', () {
      final article = source(
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'Revista',
        doi: '10.1000/xyz',
        url: 'https://sitio.org/a',
        accessedAt: DateTime(2026, 9, 5),
      );

      expect(plain(article), isNot(contains('Accessed')));
    });

    test('sin dirección no hay fecha de consulta', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        accessedAt: DateTime(2026, 9, 5),
      );

      expect(plain(book), isNot(contains('Accessed')));
    });
  });

  group('la fecha', () {
    test('un libro cita solo el año, aunque se sepa el día', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        date: PublicationDate.ofDay(2019, 3, 15),
      );

      expect(plain(book), 'García, Ana. Un título. Editorial, 2019.');
    });

    test('una página web cita hasta donde se sabe, con el mes abreviado', () {
      String webDate(PublicationDate date, {CitationLanguage? language}) =>
          plain(
            source(
              type: ReferenceType.website,
              people: [institution('OMS')],
              date: date,
              url: 'https://x.org',
            ),
            language: language ?? CitationLanguage.en,
          );

      expect(webDate(PublicationDate.ofYear(2019)), contains(' 2019, x.org'));
      expect(
        webDate(PublicationDate.ofMonth(2019, 3)),
        contains(' Mar. 2019,'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 3, 15)),
        contains(' 15 Mar. 2019,'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 9, 5)),
        contains(' 5 Sept. 2019,'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 6, 5)),
        contains(' 5 June 2019,'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 9, 5), language: es),
        contains(' 5 sept. 2019,'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 5, 5), language: es),
        contains(' 5 mayo 2019,'),
      );
    });

    test('una revista con volumen cita el año; una sin volumen, la fecha', () {
      final journal = source(
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'Revista',
        volume: '8',
        date: PublicationDate.ofDay(2020, 3, 5),
      );
      final newspaper = source(
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'El Diario',
        date: PublicationDate.ofDay(2020, 3, 5),
      );

      expect(plain(journal), endsWith('vol. 8, 2020.'));
      expect(plain(newspaper), endsWith('El Diario, 5 Mar. 2020.'));
    });
  });

  group('los autores', () {
    test('una institución, un nombre de una palabra y un sufijo', () {
      final institutional = source(
        type: ReferenceType.website,
        people: [institution('World Health Organization')],
        url: 'https://x.org',
      );
      final suffixed = source(
        type: ReferenceType.book,
        people: [
          const Contributor(
            name: PersonName(
              family: 'King',
              given: 'Martin Luther',
              suffix: 'Jr.',
            ),
          ),
        ],
        publisher: 'Editorial',
      );

      expect(plain(institutional), startsWith('World Health Organization. '));
      expect(
        plain(suffixed),
        startsWith('King, Martin Luther, Jr. Un título.'),
      );
    });

    test('tres o más: el primero y «et al.»', () {
      final book = source(
        type: ReferenceType.book,
        people: [
          person('Vargas Llosa', 'Mario'),
          person('García Márquez', 'Gabriel'),
          person('Cortázar', 'Julio'),
        ],
        publisher: 'Editorial',
      );

      expect(plain(book), startsWith('Vargas Llosa, Mario, et al. Un título.'));
    });

    test('sin personas, el autor de la captura va entero', () {
      final page = source(
        type: ReferenceType.website,
        authorName: 'Ana García Pérez',
        url: 'https://x.org',
      );

      expect(plain(page), startsWith('Ana García Pérez. Un título.'));
    });

    test('un libro compilado se cita por sus editores', () {
      final one = source(
        title: 'Antología',
        type: ReferenceType.book,
        people: [person('Franco', 'Jean', role: ContributorRole.editor)],
        publisher: 'Editorial',
      );
      final two = source(
        title: 'Antología',
        type: ReferenceType.book,
        people: [
          person('Franco', 'Jean', role: ContributorRole.editor),
          person('Paz', 'Octavio', role: ContributorRole.editor),
        ],
        publisher: 'Editorial',
      );
      final many = source(
        title: 'Antología',
        type: ReferenceType.book,
        people: [
          person('Franco', 'Jean', role: ContributorRole.editor),
          person('Paz', 'Octavio', role: ContributorRole.editor),
          person('Fuentes', 'Carlos', role: ContributorRole.editor),
        ],
        publisher: 'Editorial',
      );

      expect(plain(one), 'Franco, Jean, editor. Antología. Editorial, 2019.');
      expect(
        plain(two),
        'Franco, Jean, and Octavio Paz, editors. Antología. Editorial, 2019.',
      );
      expect(
        plain(two, language: es),
        'Franco, Jean, y Octavio Paz, eds. Antología. Editorial, 2019.',
      );
      expect(
        plain(many),
        'Franco, Jean, et al., editors. Antología. Editorial, 2019.',
      );
    });

    test('los editores de un libro con autor no se repiten de autores', () {
      final book = source(
        type: ReferenceType.book,
        people: [
          person('Tolstói', 'León'),
          person('Garnett', 'Constance', role: ContributorRole.translator),
          person('Gibian', 'George', role: ContributorRole.editor),
        ],
        publisher: 'Norton',
      );

      expect(
        plain(book),
        'Tolstói, León. Un título. Translated by Constance Garnett, edited by '
        'George Gibian, Norton, 2019.',
      );
    });

    test('varias traductoras', () {
      final book = source(
        type: ReferenceType.book,
        people: [
          person('Tolstói', 'León'),
          person('Pevear', 'Richard', role: ContributorRole.translator),
          person('Volokhonsky', 'Larissa', role: ContributorRole.translator),
        ],
        publisher: 'Penguin',
      );

      expect(
        plain(book),
        'Tolstói, León. Un título. Translated by Richard Pevear and Larissa '
        'Volokhonsky, Penguin, 2019.',
      );
    });
  });

  group('la edición y las páginas', () {
    String edition(String? raw) => plain(
      source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        edition: raw,
      ),
    );

    test('un número se vuelve ordinal; un texto con «ed.» se deja', () {
      expect(edition('2'), contains('. 2nd ed., Editorial'));
      expect(edition('Rev. ed.'), contains('. Rev. ed., Editorial'));
      expect(edition('Revised'), contains('. Revised ed., Editorial'));
      expect(edition(null), 'García, Ana. Un título. Editorial, 2019.');
    });

    test('las páginas llevan guion, no raya, y una sola lleva «p.»', () {
      String pages(String value, {CitationLanguage? language}) => plain(
        source(
          type: ReferenceType.chapter,
          people: [person('García', 'Ana')],
          container: 'Libro',
          publisher: 'Editorial',
          pages: value,
        ),
        language: language ?? CitationLanguage.en,
      );

      expect(pages('45-67'), endsWith('2019, pp. 45-67.'));
      expect(pages('45–67'), endsWith('2019, pp. 45-67.'));
      expect(pages('12'), endsWith('2019, p. 12.'));
      expect(pages('12', language: es), endsWith('2019, p. 12.'));
    });

    test('el volumen y el número de una revista', () {
      final article = source(
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'Revista',
        volume: '8',
        issue: '3',
      );

      expect(plain(article), contains('Revista, vol. 8, no. 3, 2019.'));
      expect(
        plain(article, language: es),
        contains('Revista, vol. 8, núm. 3, 2019.'),
      );
    });
  });

  group('un título que termina en signo', () {
    test('«?» no lleva otro punto, ni en cursiva ni entre comillas', () {
      final book = source(
        title: '¿Qué es la literatura?',
        type: ReferenceType.book,
        people: [person('Sartre', 'Jean-Paul')],
        publisher: 'Losada',
        date: PublicationDate.ofYear(1948),
      );
      final article = source(
        title: 'Is literature dead?',
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'Revista',
      );

      expect(
        plain(book, language: es),
        'Sartre, Jean-Paul. ¿Qué es la literatura? Losada, 1948.',
      );
      expect(
        plain(article),
        'García, Ana. “Is literature dead?” Revista, 2019.',
      );
    });
  });

  group('la cita en el texto', () {
    test('un autor: el apellido, sin año ni coma', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
      );

      expect(inText(book).toPlainText(), '(Jackson)');
    });

    test('dos autores, con «and» en inglés y «y» en español', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Salas', 'Julia'), person('Ruiz', 'Carlos')],
      );

      expect(inText(book).toPlainText(), '(Salas and Ruiz)');
      expect(inText(book, language: es).toPlainText(), '(Salas y Ruiz)');
    });

    test('«e» delante de un apellido que empieza con «i»', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Paz', 'Octavio'), person('Iglesias', 'María')],
      );

      expect(inText(book, language: es).toPlainText(), '(Paz e Iglesias)');
    });

    test('tres o más, con «et al.»', () {
      final article = source(
        type: ReferenceType.article,
        people: [
          person('Grady', 'J.'),
          person('Her', 'M.'),
          person('Moreno', 'G.'),
        ],
      );

      expect(inText(article).toPlainText(), '(Grady et al.)');
    });

    test('una institución va entera', () {
      final page = source(
        type: ReferenceType.website,
        people: [institution('World Health Organization')],
      );

      expect(inText(page).toPlainText(), '(World Health Organization)');
    });

    test('con la página, el rango o el minuto: sin «p.» y con guion', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
      );

      expect(
        inText(book, locator: const CitationLocator.page('12')).toPlainText(),
        '(Jackson 12)',
      );
      expect(
        inText(
          book,
          locator: const CitationLocator.page('12-14'),
        ).toPlainText(),
        '(Jackson 12-14)',
      );
      expect(
        inText(
          book,
          locator: const CitationLocator.page('12–14'),
        ).toPlainText(),
        '(Jackson 12-14)',
      );
      expect(
        inText(
          book,
          locator: const CitationLocator.time('0:14:35'),
        ).toPlainText(),
        '(Jackson 0:14:35)',
      );
    });

    test('la fecha no entra: una obra sin fecha se cita igual', () {
      final undated = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
        date: const PublicationDate.unknown(),
      );

      expect(inText(undated).toPlainText(), '(Jackson)');
      expect(inText(undated).hasGaps, isFalse);
    });

    test('sin autor, el hueco', () {
      final citation = inText(
        source(type: ReferenceType.book),
        locator: const CitationLocator.page('3'),
      );

      expect(citation.toPlainText(), '([missing: author] 3)');
      expect(citation.gaps, [CitationGap.author]);
    });

    test('un documental se cita por su director', () {
      final documentary = source(
        type: ReferenceType.documentary,
        people: [person('Ruiz', 'Ana', role: ContributorRole.director)],
      );

      expect(inText(documentary).toPlainText(), '(Ruiz)');
    });
  });

  group('todos los tipos', () {
    test('cada uno da una cita con su título, sin fallar', () {
      for (final type in [...ReferenceType.values, null]) {
        for (final language in CitationLanguage.values) {
          final text = plain(
            source(
              type: type,
              people: [person('García', 'Ana')],
              publisher: 'Editorial',
              container: 'Contenedor',
              volume: '1',
              url: 'https://x.org/a',
            ),
            language: language,
          );
          final reason = '$type $language';

          expect(text, contains('Un título'), reason: reason);
          expect(text, startsWith('García, Ana. '), reason: reason);
          expect(text, endsWith('.'), reason: reason);
          expect(text, isNot(contains('..')), reason: reason);
          expect(text, isNot(contains('  ')), reason: reason);
          expect(text, isNot(contains('https://')), reason: reason);
        }
      }
    });

    test('una fuente completa de cada tipo no tiene huecos', () {
      final complete = <ReferenceType, CitationSource>{
        ReferenceType.book: source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
        ReferenceType.chapter: source(
          type: ReferenceType.chapter,
          people: [person('García', 'Ana')],
          container: 'Libro',
          publisher: 'Editorial',
        ),
        ReferenceType.article: source(
          type: ReferenceType.article,
          people: [person('García', 'Ana')],
          container: 'Revista',
        ),
        ReferenceType.thesis: source(
          type: ReferenceType.thesis,
          people: [person('García', 'Ana')],
          publisher: 'Universidad',
        ),
        ReferenceType.primarySource: source(
          type: ReferenceType.primarySource,
          people: [person('García', 'Ana')],
        ),
        ReferenceType.documentary: source(
          type: ReferenceType.documentary,
          people: [person('García', 'Ana', role: ContributorRole.director)],
        ),
        ReferenceType.website: source(
          type: ReferenceType.website,
          people: [person('García', 'Ana')],
          url: 'https://x.org',
        ),
        ReferenceType.onlinePublication: source(
          type: ReferenceType.onlinePublication,
          people: [person('García', 'Ana')],
          url: 'https://x.org',
        ),
        ReferenceType.other: source(
          type: ReferenceType.other,
          people: [person('García', 'Ana')],
        ),
      };

      expect(complete.keys, unorderedEquals(ReferenceType.values));
      for (final entry in complete.entries) {
        expect(reference(entry.value).hasGaps, isFalse, reason: entry.key.name);
      }
    });
  });
}
