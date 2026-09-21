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
import 'package:sinapsis/features/citations/domain/services/styles/ieee_style.dart';

/// IEEE (F15). Los ejemplos en inglés son los de la guía de referencias de
/// IEEE —el libro de Klaus y Horn, el capítulo de Stein, el artículo de
/// Duncombe, la página de CNN—; los demás, el mismo esquema en español.
void main() {
  const style = IeeeStyle();

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
    String? place,
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
      publisherPlace: place,
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
    int? number,
  }) => style.format(
    CitationForm.reference,
    source,
    CitationContext(language: language, number: number),
  );

  String plain(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    int? number,
  }) => reference(source, language: language, number: number).toPlainText();

  Citation inText({
    CitationLanguage language = CitationLanguage.en,
    CitationLocator? locator,
    int? number,
  }) => style.format(
    CitationForm.inText,
    source(),
    CitationContext(language: language, locator: locator, number: number),
  );

  const es = CitationLanguage.es;

  group('el estilo', () {
    test('se llama IEEE y numera sus entradas', () {
      expect(style.id, 'ieee');
      expect(style.name, 'IEEE');
      expect(style.isNumbered, isTrue);
      expect(style.isAuthorDate, isFalse);
      expect(style.listTitle(CitationLanguage.es), 'Referencias');
      expect(style.listTitle(CitationLanguage.en), 'References');
      expect(kReferenceStyles.byId('ieee'), isA<IeeeStyle>());
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

    test('la entrada lleva su número solo si se lo dan', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(plain(book), startsWith('A. García, '));
      expect(plain(book, number: 3), startsWith('[3] A. García, '));
      expect(plain(book, number: 12), startsWith('[12] A. García, '));
    });
  });

  group('los ejemplos de la guía, en inglés', () {
    test('un libro de dos autores, con su ciudad', () {
      final book = source(
        title: 'Robot Vision',
        type: ReferenceType.book,
        people: [person('Klaus', 'B.'), person('Horn', 'P.')],
        publisher: 'MIT Press',
        place: 'Cambridge, MA, USA',
        date: PublicationDate.ofYear(1986),
      );

      expect(
        plain(book, number: 1),
        '[1] B. Klaus and P. Horn, Robot Vision. Cambridge, MA, USA: MIT '
        'Press, 1986.',
      );
      expect(
        reference(book).toMarkdown(),
        startsWith('B. Klaus and P. Horn, *Robot Vision*. Cambridge'),
      );
      expect(reference(book).hasGaps, isFalse);
    });

    test('un capítulo de un libro editado', () {
      final chapter = source(
        title: 'Random patterns',
        type: ReferenceType.chapter,
        people: [
          person('Stein', 'L.'),
          person('Brake', 'J. S.', role: ContributorRole.editor),
        ],
        container: 'Computers and You',
        publisher: 'Wiley',
        place: 'New York, NY, USA',
        pages: '55-70',
        date: PublicationDate.ofYear(1994),
      );

      expect(
        plain(chapter, number: 2),
        '[2] L. Stein, “Random patterns,” in Computers and You, J. S. Brake, '
        'Ed. New York, NY, USA: Wiley, 1994, pp. 55–70.',
      );
      expect(
        reference(chapter).toMarkdown(),
        contains('in *Computers and You*, J. S. Brake, Ed.'),
      );
    });

    test('varios autores, dos editores, el volumen y las páginas', () {
      final chapter = source(
        title: 'Optical properties of carbon nanotubes and nanographene',
        type: ReferenceType.chapter,
        people: [
          person('Saito', 'R.'),
          person('Jorio', 'A.'),
          person('Jiang', 'J.'),
          person('Sasaki', 'K.'),
          person('Dresselhaus', 'G.'),
          person('Dresselhaus', 'M. S.'),
          person('Narlikar', 'A. V.', role: ContributorRole.editor),
          person('Fu', 'Y. Y.', role: ContributorRole.editor),
        ],
        container: 'The Oxford Handbook of Nanoscience and Technology',
        volume: '2',
        publisher: 'Oxford Univ. Press',
        place: 'Oxford, U.K.',
        pages: '1-30',
        date: PublicationDate.ofYear(2010),
      );

      // La guía agrega el título del volumen —«vol. 2, Materials»—: esta
      // versión guarda solo su número.
      expect(
        plain(chapter),
        'R. Saito, A. Jorio, J. Jiang, K. Sasaki, G. Dresselhaus, and M. S. '
        'Dresselhaus, “Optical properties of carbon nanotubes and '
        'nanographene,” in The Oxford Handbook of Nanoscience and Technology, '
        'vol. 2, A. V. Narlikar and Y. Y. Fu, Eds. Oxford, U.K.: Oxford '
        'Univ. Press, 2010, pp. 1–30.',
      );
    });

    test('un artículo: volumen, número, páginas, mes y DOI', () {
      final article = source(
        title: 'Infrared navigation—Part I: An assessment of feasibility',
        type: ReferenceType.article,
        people: [person('Duncombe', 'J. U.')],
        container: 'IEEE Trans. Electron Devices',
        volume: 'ED-11',
        issue: '1',
        pages: '34-39',
        doi: '10.1109/TED.2016.2628402',
        date: PublicationDate.ofMonth(1959, 1),
      );

      expect(
        plain(article, number: 3),
        '[3] J. U. Duncombe, “Infrared navigation—Part I: An assessment of '
        'feasibility,” IEEE Trans. Electron Devices, vol. ED-11, no. 1, pp. '
        '34–39, Jan. 1959, doi: 10.1109/TED.2016.2628402.',
      );
      expect(
        reference(article).toMarkdown(),
        contains('feasibility,” *IEEE Trans. Electron Devices*, vol.'),
      );
    });

    test('una página web: sin fecha de publicación, con la de consulta', () {
      final page = source(
        title: 'Obama inaugurated as President',
        type: ReferenceType.website,
        people: [person('Smith', 'J.')],
        container: 'CNN.com',
        url: 'http://www.cnn.com/POLITICS/01/21/obama_inaugurated/index.html',
        accessedAt: DateTime(2009, 2),
      );

      expect(
        plain(page, number: 4),
        '[4] J. Smith. “Obama inaugurated as President.” CNN.com. Accessed: '
        'Feb. 1, 2009. [Online]. Available: '
        'http://www.cnn.com/POLITICS/01/21/obama_inaugurated/index.html',
      );
    });

    test('una tesis', () {
      final thesis = source(
        title: 'Narrow-band analyzer',
        type: ReferenceType.thesis,
        people: [person('Williams', 'J. O.')],
        publisher: 'Harvard Univ.',
        date: PublicationDate.ofYear(1993),
      );

      // La guía escribe «Ph.D. dissertation, Dept. Elect. Eng., Harvard Univ.,
      // Cambridge, MA, USA»: esta versión no guarda el grado ni el
      // departamento.
      expect(
        plain(thesis),
        'J. O. Williams, “Narrow-band analyzer,” Thesis, Harvard Univ., 1993.',
      );
    });

    test('un video de YouTube, como una página web', () {
      final video = source(
        title: 'What is the tallest tower possible?',
        kind: SourceKind.youtube,
        authorName: 'Kurzgesagt – In a Nutshell',
        date: PublicationDate.ofDay(2020, 3, 5),
        url: 'https://www.youtube.com/watch?v=abc123',
        capturedAt: DateTime(2026, 9, 5),
      );

      expect(
        plain(video),
        'Kurzgesagt – In a Nutshell. “What is the tallest tower possible?” '
        'YouTube. Accessed: Sep. 5, 2026. [Online]. Available: '
        'https://www.youtube.com/watch?v=abc123',
      );
    });

    test('una película: por su director, como un libro', () {
      final film = source(
        title: 'Dune',
        type: ReferenceType.documentary,
        people: [person('Villeneuve', 'D.', role: ContributorRole.director)],
        publisher: 'Warner Bros.',
        place: 'Burbank, CA, USA',
        date: PublicationDate.ofYear(2021),
      );

      expect(
        plain(film),
        'D. Villeneuve, Director, Dune. Burbank, CA, USA: Warner Bros., 2021.',
      );
    });
  });

  group('en español', () {
    test('un libro', () {
      final book = source(
        title: 'Cien años de soledad',
        type: ReferenceType.book,
        people: [person('García Márquez', 'Gabriel José')],
        publisher: 'Sudamericana',
        place: 'Buenos Aires, Argentina',
        edition: '2',
        date: PublicationDate.ofYear(1967),
      );

      expect(
        plain(book, language: es, number: 1),
        '[1] G. J. García Márquez, Cien años de soledad, 2.ª ed. Buenos Aires, '
        'Argentina: Sudamericana, 1967.',
      );
    });

    test('dos autores con «y»; tres con coma y «y», sin coma antes', () {
      final two = source(
        type: ReferenceType.book,
        people: [person('Salas', 'Julia'), person('Ruiz', 'Carlos')],
        publisher: 'Editorial',
      );
      final three = source(
        type: ReferenceType.book,
        people: [
          person('Vargas Llosa', 'Mario'),
          person('García Márquez', 'Gabriel'),
          person('Cortázar', 'Julio'),
        ],
        publisher: 'Editorial',
      );

      expect(plain(two, language: es), startsWith('J. Salas y C. Ruiz, '));
      expect(
        plain(three, language: es),
        startsWith('M. Vargas Llosa, G. García Márquez y J. Cortázar, '),
      );
    });

    test('un capítulo: comillas angulares, la coma afuera y «en»', () {
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
        place: 'México',
        date: PublicationDate.ofYear(1969),
      );

      expect(
        plain(chapter, language: es),
        'C. Fuentes, «La novela hispanoamericana», en Historia de la '
        'literatura, J. Franco, Ed. México: Fondo de Cultura Económica, 1969, '
        'pp. 120–145.',
      );
    });

    test('un artículo: «núm.» y el mes abreviado', () {
      final article = source(
        title: 'Redes de citación',
        type: ReferenceType.article,
        people: [person('Ruiz', 'Ana')],
        container: 'Revista de Datos',
        volume: '8',
        issue: '3',
        pages: '207-217',
        date: PublicationDate.ofMonth(2020, 9),
      );

      expect(
        plain(article, language: es),
        'A. Ruiz, «Redes de citación», Revista de Datos, vol. 8, núm. 3, pp. '
        '207–217, sept. 2020.',
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
        'A. Ruiz, «Redes de citación», Tesis, Universidad de Chile, 2014.',
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
        'C. Colón, «Carta a Luis de Santángel», Archivo General de Indias, '
        '1493.',
      );
    });

    test('una publicación en red: «Consultado» y «[En línea]»', () {
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
        'J. Pérez. «Una entrada sobre citas». Blog de Sinapsis. Consultado: 5 '
        'sept. 2026. [En línea]. Disponible en: '
        'https://blog.example.org/entrada',
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
        'A. García, Un título. Editorial, [falta: año].',
      );
      expect(unknown.gaps, [CitationGap.year]);
      expect(
        plain(undated, language: es),
        'A. García, Un título. Editorial, s. f.',
      );
      expect(plain(undated), 'A. García, Un título. Editorial, n.d.');
    });

    test('sin autor', () {
      final citation = reference(
        source(type: ReferenceType.book, publisher: 'Editorial'),
        language: es,
      );

      expect(
        citation.toPlainText(),
        '[falta: autor], Un título. Editorial, 2019.',
      );
      expect(citation.gaps, [CitationGap.author]);
    });

    test('sin título', () {
      final article = reference(
        source(
          title: '  ',
          type: ReferenceType.article,
          people: [person('García', 'Ana')],
          container: 'Revista',
        ),
        language: es,
      );
      final book = reference(
        source(
          title: '',
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
        language: es,
      );

      expect(article.gaps, [CitationGap.title]);
      expect(
        article.toPlainText(),
        'A. García, [falta: título], Revista, 2019.',
      );
      expect(book.gaps, [CitationGap.title]);
      expect(
        book.toPlainText(),
        'A. García, [falta: título]. Editorial, 2019.',
      );
    });

    test('un libro sin editorial', () {
      final citation = reference(
        source(type: ReferenceType.book, people: [person('García', 'Ana')]),
        language: es,
      );

      expect(
        citation.toPlainText(),
        'A. García, Un título. [falta: editorial], 2019.',
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
        'A. García, «Un título», en [falta: publicado en]. Editorial, 2019.',
      );
    });

    test('un artículo sin revista; sin volumen no se marca nada', () {
      final citation = reference(
        source(type: ReferenceType.article, people: [person('García', 'Ana')]),
      );

      expect(citation.gaps, [CitationGap.container]);
      expect(
        citation.toPlainText(),
        'A. García, “Un título,” [missing: published in], 2019.',
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
        'A. García, «Un título», Tesis, [falta: editorial], 2019.',
      );
    });

    test('una página web sin enlace ni fecha de consulta', () {
      final citation = reference(
        source(type: ReferenceType.website, people: [institution('OMS')]),
        language: es,
      );

      expect(citation.gaps, [CitationGap.accessed, CitationGap.link]);
      expect(
        citation.toPlainText(),
        'OMS. «Un título». [falta: fecha de consulta]. [En línea]. Disponible '
        'en: [falta: enlace]',
      );
    });

    test('sin tipo de obra: la forma general y el hueco', () {
      final citation = reference(
        source(people: [person('García', 'Ana')], publisher: 'Editorial'),
        language: es,
      );

      expect(citation.gaps, [CitationGap.type]);
      expect(
        citation.toPlainText(),
        'A. García, Un título [falta: tipo de obra]. Editorial, 2019.',
      );
    });

    test('un documento suelto no tiene tipo; una página web sí, sola', () {
      final page = source(
        people: [institution('OMS')],
        kind: SourceKind.webPage,
        url: 'https://oms.org/x',
        capturedAt: DateTime(2026, 9, 5),
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
        '[missing: author], Un título. [missing: publisher], [missing: year].',
      );
    });

    test('lo opcional que falta no se marca: la ciudad y el volumen', () {
      final book = reference(
        source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
      );
      final article = reference(
        source(
          type: ReferenceType.article,
          people: [person('García', 'Ana')],
          container: 'Revista',
        ),
      );

      expect(book.hasGaps, isFalse);
      expect(article.hasGaps, isFalse);
      expect(book.toPlainText(), 'A. García, Un título. Editorial, 2019.');
    });
  });

  group('el enlace', () {
    test('el DOI gana sobre la dirección, con «doi:» y un punto final', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        doi: '10.1000/xyz',
        url: 'https://otro.org',
      );

      expect(
        plain(book),
        'A. García, Un título. Editorial, 2019, doi: 10.1000/xyz.',
      );
    });

    test('una dirección, con «[Online]. Available:» y sin punto final', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        url: 'https://otro.org/libro',
      );

      expect(
        plain(book),
        'A. García, Un título. Editorial, 2019. [Online]. Available: '
        'https://otro.org/libro',
      );
      expect(
        plain(book, language: es),
        endsWith('2019. [En línea]. Disponible en: https://otro.org/libro'),
      );
    });

    test(
      'en una obra que no es de la web, la fecha de consulta, si la cargaron',
      () {
        final book = source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
          url: 'https://otro.org/libro',
          accessedAt: DateTime(2026, 9, 5),
          capturedAt: DateTime(2026, 9),
        );
        final captured = source(
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
          url: 'https://otro.org/libro',
          capturedAt: DateTime(2026, 9),
        );

        expect(
          plain(book),
          endsWith(
            '2019. Accessed: Sep. 5, 2026. [Online]. Available: '
            'https://otro.org/libro',
          ),
        );
        // La de captura no reemplaza a la de consulta fuera de la web.
        expect(plain(captured), isNot(contains('Accessed')));
      },
    );

    test('una página web sin fecha de consulta usa la de captura', () {
      final page = source(
        type: ReferenceType.website,
        people: [person('Pérez', 'Juana')],
        url: 'https://sitio.org/a',
        capturedAt: DateTime(2026, 9, 5),
      );

      expect(
        plain(page),
        'J. Pérez. “Un título.” Accessed: Sep. 5, 2026. [Online]. Available: '
        'https://sitio.org/a',
      );
      expect(reference(page).gaps, isEmpty);
    });

    test('el sitio es el contenedor o, si no hay, la editorial', () {
      String site({String? container, String? publisher}) => plain(
        source(
          type: ReferenceType.website,
          people: [person('Pérez', 'Juana')],
          container: container,
          publisher: publisher,
          url: 'https://sitio.org/a',
          capturedAt: DateTime(2026, 9, 5),
        ),
      );

      expect(
        site(container: 'Sitio', publisher: 'Otra'),
        contains('“Un título.” Sitio. Accessed'),
      );
      expect(site(publisher: 'Otra'), contains('“Un título.” Otra. Accessed'));
      expect(site(), contains('“Un título.” Accessed'));
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

      expect(plain(book), contains('Editorial, 2019.'));
    });

    test('un artículo cita el mes abreviado, sin el día', () {
      String articleDate(PublicationDate date, {CitationLanguage? language}) =>
          plain(
            source(
              type: ReferenceType.article,
              people: [person('García', 'Ana')],
              container: 'Revista',
              date: date,
            ),
            language: language ?? CitationLanguage.en,
          );

      expect(articleDate(PublicationDate.ofYear(2019)), endsWith(', 2019.'));
      expect(
        articleDate(PublicationDate.ofMonth(2019, 3)),
        endsWith('Mar. 2019.'),
      );
      expect(
        articleDate(PublicationDate.ofMonth(2019, 9)),
        endsWith('Sep. 2019.'),
      );
      expect(
        articleDate(PublicationDate.ofDay(2019, 6, 5)),
        endsWith('Jun. 2019.'),
      );
      expect(
        articleDate(PublicationDate.ofMonth(2019, 9), language: es),
        endsWith('sept. 2019.'),
      );
    });

    test(
      'la fecha de consulta: el mes antes en inglés, el día antes en español',
      () {
        final page = source(
          type: ReferenceType.website,
          people: [person('Pérez', 'Juana')],
          url: 'https://sitio.org/a',
          accessedAt: DateTime(2026, 3, 15),
        );

        expect(plain(page), contains('Accessed: Mar. 15, 2026.'));
        expect(
          plain(page, language: es),
          contains('Consultado: 15 mar. 2026.'),
        );
      },
    );
  });

  group('los autores', () {
    test(
      'hasta seis se escriben todos; desde siete, el primero y «et al.»',
      () {
        List<Contributor> authors(int count) => [
          for (var i = 1; i <= count; i++) person('Autor$i', 'Nombre'),
        ];

        final six = plain(
          source(
            type: ReferenceType.book,
            people: authors(6),
            publisher: 'Editorial',
          ),
        );
        final seven = plain(
          source(
            type: ReferenceType.book,
            people: authors(7),
            publisher: 'Editorial',
          ),
        );

        expect(six, contains('N. Autor5, and N. Autor6, Un título.'));
        expect(seven, startsWith('N. Autor1 et al., Un título.'));
        expect(seven, isNot(contains('Autor2')));
      },
    );

    test('dos autores sin coma; tres con coma antes de «and»', () {
      final two = source(
        type: ReferenceType.book,
        people: [person('Salas', 'Julia'), person('Ruiz', 'Carlos')],
        publisher: 'Editorial',
      );
      final three = source(
        type: ReferenceType.book,
        people: [
          person('Salas', 'Julia'),
          person('Ruiz', 'Carlos'),
          person('Paz', 'Octavio'),
        ],
        publisher: 'Editorial',
      );

      expect(plain(two), startsWith('J. Salas and C. Ruiz, '));
      expect(plain(three), startsWith('J. Salas, C. Ruiz, and O. Paz, '));
    });

    test('una institución va entera; un sufijo, después del apellido', () {
      final institutional = source(
        type: ReferenceType.website,
        people: [institution('World Health Organization')],
        url: 'https://x.org',
        capturedAt: DateTime(2026, 9, 5),
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
      expect(plain(suffixed), startsWith('M. L. King, Jr., Un título.'));
    });

    test('sin personas, el autor de la captura va entero', () {
      final page = source(
        type: ReferenceType.website,
        authorName: 'Ana García Pérez',
        url: 'https://x.org',
        capturedAt: DateTime(2026, 9, 5),
      );

      expect(plain(page), startsWith('Ana García Pérez. “Un título.”'));
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

      expect(plain(one), 'J. Franco, Ed., Antología. Editorial, 2019.');
      expect(
        plain(two),
        'J. Franco and O. Paz, Eds., Antología. Editorial, 2019.',
      );
    });

    test('el traductor no figura de autor', () {
      final book = source(
        type: ReferenceType.book,
        people: [
          person('Tolstói', 'León'),
          person('Rabassa', 'Gregory', role: ContributorRole.translator),
        ],
        publisher: 'Editorial',
      );

      expect(plain(book), startsWith('L. Tolstói, Un título.'));
    });
  });

  group('la edición y las páginas', () {
    test('la edición y el volumen de un libro, antes de la editorial', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        place: 'Lima',
        edition: '3',
        volume: '2',
      );

      expect(
        plain(book),
        'A. García, Un título, 3rd ed., vol. 2. Lima: Editorial, 2019.',
      );
    });

    test('una sola página lleva «p.»; un rango, «pp.» con raya', () {
      String pages(String value) => plain(
        source(
          type: ReferenceType.chapter,
          people: [person('García', 'Ana')],
          container: 'Libro',
          publisher: 'Editorial',
          pages: value,
        ),
      );

      expect(pages('45-67'), endsWith('2019, pp. 45–67.'));
      expect(pages('12'), endsWith('2019, p. 12.'));
    });
  });

  group('un título que termina en signo', () {
    test('«?» entre comillas no lleva la coma adentro', () {
      final article = source(
        title: 'Is literature dead?',
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        container: 'Revista',
      );

      expect(plain(article), 'A. García, “Is literature dead?” Revista, 2019.');
    });

    test('«?» en cursiva no lleva otro punto', () {
      final book = source(
        title: '¿Qué es la literatura?',
        type: ReferenceType.book,
        people: [person('Sartre', 'Jean-Paul')],
        publisher: 'Losada',
        date: PublicationDate.ofYear(1948),
      );

      expect(
        plain(book, language: es),
        'J.-P. Sartre, ¿Qué es la literatura? Losada, 1948.',
      );
    });
  });

  group('la cita en el texto', () {
    test('el número entre corchetes', () {
      expect(inText(number: 3).toPlainText(), '[3]');
      expect(inText(number: 12).toPlainText(), '[12]');
    });

    test('sin número, una fuente citada sola es la primera', () {
      expect(inText().toPlainText(), '[1]');
    });

    test('con la página, el rango o el minuto', () {
      expect(
        inText(
          number: 3,
          locator: const CitationLocator.page('12'),
        ).toPlainText(),
        '[3, p. 12]',
      );
      expect(
        inText(
          number: 3,
          locator: const CitationLocator.page('12-14'),
        ).toPlainText(),
        '[3, pp. 12–14]',
      );
      expect(
        inText(
          number: 3,
          language: es,
          locator: const CitationLocator.page('12'),
        ).toPlainText(),
        '[3, p. 12]',
      );
      expect(
        inText(
          number: 3,
          locator: const CitationLocator.time('0:14:35'),
        ).toPlainText(),
        '[3, 0:14:35]',
      );
    });

    test('no depende de la fuente: ni autor ni fecha entran', () {
      final citation = style.format(
        CitationForm.inText,
        const CitationSource(title: ''),
        const CitationContext(number: 7),
      );

      expect(citation.toPlainText(), '[7]');
      expect(citation.hasGaps, isFalse);
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
              capturedAt: DateTime(2026, 9, 5),
            ),
            language: language,
            number: 5,
          );
          final reason = '$type $language';

          expect(text, contains('Un título'), reason: reason);
          expect(text, startsWith('[5] '), reason: reason);
          expect(text, contains('García'), reason: reason);
          expect(text, isNot(contains('..')), reason: reason);
          expect(text, isNot(contains('  ')), reason: reason);
          expect(text, contains('https://x.org/a'), reason: reason);
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
          capturedAt: DateTime(2026, 9, 5),
        ),
        ReferenceType.onlinePublication: source(
          type: ReferenceType.onlinePublication,
          people: [person('García', 'Ana')],
          url: 'https://x.org',
          capturedAt: DateTime(2026, 9, 5),
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
