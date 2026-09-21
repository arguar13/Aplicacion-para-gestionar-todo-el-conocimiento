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
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';

/// APA 7.ª edición (F15). Los ejemplos en inglés son los del Manual de
/// Publicaciones de la APA —libro, capítulo de un libro editado, artículo de
/// revista, tesis, página web, video—; los demás, el mismo esquema en español.
void main() {
  const style = Apa7Style();

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

  group('el estilo', () {
    test('se llama APA 7 y está primero en el registro', () {
      expect(style.id, 'apa7');
      expect(style.name, 'APA 7');
      expect(kReferenceStyles.defaultStyle.id, 'apa7');
      expect(kReferenceStyles.byId('apa7'), isA<Apa7Style>());
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

    test('no numera sus entradas', () {
      expect(style.isNumbered, isFalse);
    });

    test('un estilo que no existe cae en el predeterminado', () {
      expect(kReferenceStyles.byId('chicago99'), isNull);
      expect(kReferenceStyles.resolve('chicago99').id, 'apa7');
      expect(kReferenceStyles.resolve(null).id, 'apa7');
    });
  });

  group('los ejemplos de la guía, en inglés', () {
    test('un libro, con su edición y su DOI', () {
      final book = source(
        title: 'The psychology of prejudice: From attitudes to social action',
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
        publisher: 'American Psychological Association',
        edition: '2',
        doi: '10.1037/0000168-000',
      );

      expect(
        plain(book),
        'Jackson, L. M. (2019). The psychology of prejudice: From attitudes to '
        'social action (2nd ed.). American Psychological Association. '
        'https://doi.org/10.1037/0000168-000',
      );
      expect(
        reference(book).toMarkdown(),
        'Jackson, L. M. (2019). *The psychology of prejudice: From attitudes '
        'to social action* (2nd ed.). American Psychological Association. '
        'https://doi.org/10.1037/0000168-000',
      );
      expect(reference(book).hasGaps, isFalse);
    });

    test('un capítulo de un libro editado', () {
      final chapter = source(
        title: 'Culinary arts: Talent and their development',
        type: ReferenceType.chapter,
        people: [
          person('Aron', 'Lisa'),
          person('Botella', 'Marion'),
          person('Lubart', 'Todd'),
          person('Subotnik', 'Rena F.', role: ContributorRole.editor),
          person('Olszewski-Kubilius', 'Paula', role: ContributorRole.editor),
          person('Worrell', 'Frank C.', role: ContributorRole.editor),
        ],
        container:
            'The psychology of high performance: Developing human potential '
            'into domain-specific talent',
        pages: '345-359',
        publisher: 'American Psychological Association',
        doi: '10.1037/0000120-016',
      );

      expect(
        plain(chapter),
        'Aron, L., Botella, M., & Lubart, T. (2019). Culinary arts: Talent and '
        'their development. In R. F. Subotnik, P. Olszewski-Kubilius, & F. C. '
        'Worrell (Eds.), The psychology of high performance: Developing human '
        'potential into domain-specific talent (pp. 345–359). American '
        'Psychological Association. https://doi.org/10.1037/0000120-016',
      );
    });

    test('un artículo de revista: el volumen en cursiva, el número no', () {
      final article = source(
        title:
            'Emotions in storybooks: A comparison of storybooks that represent '
            'ethnic and racial groups in the United States',
        type: ReferenceType.article,
        people: [
          person('Grady', 'Jonathan S.'),
          person('Her', 'Mai'),
          person('Moreno', 'Gabriela'),
          person('Perez', 'Christopher'),
          person('Yelinek', 'Julie'),
        ],
        container: 'Psychology of Popular Media Culture',
        volume: '8',
        issue: '3',
        pages: '207-217',
        doi: '10.1037/ppm0000185',
      );

      expect(
        plain(article),
        'Grady, J. S., Her, M., Moreno, G., Perez, C., & Yelinek, J. (2019). '
        'Emotions in storybooks: A comparison of storybooks that represent '
        'ethnic and racial groups in the United States. Psychology of Popular '
        'Media Culture, 8(3), 207–217. https://doi.org/10.1037/ppm0000185',
      );
      // El nombre de la revista, la coma y el volumen son UNA cursiva.
      expect(
        reference(article).toMarkdown(),
        contains('*Psychology of Popular Media Culture, 8*(3), 207–217.'),
      );
    });

    test('una tesis', () {
      final thesis = source(
        title:
            'Instructional leadership perceptions and practices of elementary '
            'school leaders',
        type: ReferenceType.thesis,
        people: [person('Harris', 'Lisa')],
        publisher: 'University of Virginia',
        date: PublicationDate.ofYear(2014),
      );

      // La guía escribe «Doctoral dissertation»: esta versión no guarda el
      // grado, y dice «Thesis» a secas.
      expect(
        plain(thesis),
        'Harris, L. (2014). Instructional leadership perceptions and '
        'practices of elementary school leaders [Thesis, University of '
        'Virginia].',
      );
    });

    test('una página web de una organización: sin repetir el sitio', () {
      final page = source(
        title: 'Ageing and health',
        type: ReferenceType.website,
        people: [institution('World Health Organization')],
        container: 'World Health Organization',
        date: PublicationDate.ofDay(2018, 5, 24),
        url:
            'https://www.who.int/news-room/fact-sheets/detail/ageing-and-health',
      );

      expect(
        plain(page),
        'World Health Organization. (2018, May 24). Ageing and health. '
        'https://www.who.int/news-room/fact-sheets/detail/ageing-and-health',
      );
    });

    test(
      'un video de YouTube: el canal entero, con «[Video]» y la plataforma',
      () {
        final video = source(
          title: 'What is the tallest tower possible?',
          kind: SourceKind.youtube,
          authorName: 'Kurzgesagt – In a Nutshell',
          date: PublicationDate.ofDay(2020, 3, 5),
          url: 'https://www.youtube.com/watch?v=abc123',
        );

        expect(
          plain(video),
          'Kurzgesagt – In a Nutshell. (2020, March 5). What is the tallest '
          'tower possible? [Video]. YouTube. https://www.youtube.com/watch?v=abc123',
        );
      },
    );
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
        plain(book, language: CitationLanguage.es),
        'García Márquez, G. (1967). Cien años de soledad (2.ª ed.). '
        'Sudamericana.',
      );
    });

    test('dos autores se unen con «y», sin coma', () {
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
        plain(book, language: CitationLanguage.es),
        'García Márquez, G. y Mendoza, P. A. (1982). El olor de la guayaba. '
        'Oveja Negra.',
      );
    });

    test('tres autores: comas y «y» al final', () {
      final book = source(
        type: ReferenceType.book,
        people: [
          person('Vargas Llosa', 'Mario'),
          person('García Márquez', 'Gabriel'),
          person('Cortázar', 'Julio'),
        ],
        publisher: 'Editorial',
      );

      expect(
        plain(book, language: CitationLanguage.es),
        startsWith(
          'Vargas Llosa, M., García Márquez, G. y Cortázar, J. (2019).',
        ),
      );
    });

    test('«e» delante de un apellido que empieza con «i»', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Paz', 'Octavio'), person('Iglesias', 'María')],
        publisher: 'Editorial',
      );

      expect(
        plain(book, language: CitationLanguage.es),
        startsWith('Paz, O. e Iglesias, M. (2019).'),
      );
    });

    test(
      'un capítulo: «En», los editores con «Ed.» y las páginas con «pp.»',
      () {
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
          plain(chapter, language: CitationLanguage.es),
          'Fuentes, C. (1969). La novela hispanoamericana. En J. Franco (Ed.), '
          'Historia de la literatura (pp. 120–145). Fondo de Cultura '
          'Económica.',
        );
      },
    );

    test('una sola página lleva «p.»', () {
      final chapter = source(
        type: ReferenceType.chapter,
        people: [person('Fuentes', 'Carlos')],
        container: 'Libro',
        pages: '12',
        publisher: 'Editorial',
      );

      expect(
        plain(chapter, language: CitationLanguage.es),
        contains('(p. 12)'),
      );
    });

    test('la edición y las páginas de un capítulo van juntas', () {
      final chapter = source(
        type: ReferenceType.chapter,
        people: [person('Fuentes', 'Carlos')],
        container: 'Libro',
        edition: '3',
        pages: '12-20',
        publisher: 'Editorial',
      );

      expect(
        plain(chapter, language: CitationLanguage.es),
        contains('*Libro* (3.ª ed., pp. 12–20)'.replaceAll('*', '')),
      );
    });

    test('un documental: el director con «(Dir.)»', () {
      final documentary = source(
        title: 'La ciudad fantasma',
        type: ReferenceType.documentary,
        people: [person('Ruiz', 'Ana', role: ContributorRole.director)],
        publisher: 'Producciones Sur',
        date: PublicationDate.ofYear(2015),
      );

      expect(
        plain(documentary, language: CitationLanguage.es),
        'Ruiz, A. (Dir.). (2015). La ciudad fantasma [Documental]. '
        'Producciones Sur.',
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
        plain(letter, language: CitationLanguage.es),
        'Colón, C. (1493). Carta a Luis de Santángel. Archivo General de '
        'Indias.',
      );
    });

    test('una publicación en red: el título sin cursiva y el sitio', () {
      final post = source(
        title: 'Una entrada sobre citas',
        type: ReferenceType.onlinePublication,
        people: [person('Pérez', 'Juana')],
        container: 'Blog de Sinapsis',
        date: PublicationDate.ofDay(2020, 6, 1),
        url: 'https://blog.example.org/entrada',
      );

      final citation = reference(post, language: CitationLanguage.es);

      expect(
        citation.toPlainText(),
        'Pérez, J. (2020, 1 de junio). Una entrada sobre citas. Blog de '
        'Sinapsis. https://blog.example.org/entrada',
      );
      expect(citation.runs.whereType<ItalicRun>(), isEmpty);
    });

    test('«s. f.» cuando la obra no tiene fecha', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Anónimo', 'X')],
        publisher: 'Editorial',
        date: const PublicationDate.undated(),
      );

      expect(plain(book, language: CitationLanguage.es), contains('(s. f.).'));
      expect(plain(book), contains('(n.d.).'));
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
        language: CitationLanguage.es,
      );

      expect(
        unknown.toPlainText(),
        'García, A. ([falta: año]). Un título. Editorial.',
      );
      expect(unknown.gaps, [CitationGap.year]);
    });

    test('sin autor', () {
      final citation = reference(
        source(type: ReferenceType.book, publisher: 'Editorial'),
        language: CitationLanguage.es,
      );

      expect(
        citation.toPlainText(),
        '[falta: autor]. (2019). Un título. Editorial.',
      );
      expect(citation.gaps, [CitationGap.author]);
    });

    test('sin título', () {
      final citation = reference(
        source(
          title: '  ',
          type: ReferenceType.book,
          people: [person('García', 'Ana')],
          publisher: 'Editorial',
        ),
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.title]);
      expect(
        citation.toPlainText(),
        'García, A. (2019). [falta: título]. Editorial.',
      );
    });

    test('un libro sin editorial', () {
      final citation = reference(
        source(type: ReferenceType.book, people: [person('García', 'Ana')]),
        language: CitationLanguage.es,
      );

      expect(
        citation.toPlainText(),
        'García, A. (2019). Un título. [falta: editorial].',
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
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.container]);
      expect(citation.toPlainText(), contains('En [falta: publicado en]'));
    });

    test('un artículo sin revista ni volumen', () {
      final citation = reference(
        source(type: ReferenceType.article, people: [person('García', 'Ana')]),
      );

      expect(citation.gaps, [CitationGap.container, CitationGap.volume]);
      expect(
        citation.toPlainText(),
        'García, A. (2019). Un título. [missing: published in], '
        '[missing: volume].',
      );
    });

    test('un artículo sin volumen', () {
      final citation = reference(
        source(
          type: ReferenceType.article,
          people: [person('García', 'Ana')],
          container: 'Revista',
        ),
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.volume]);
      expect(
        citation.toPlainText(),
        'García, A. (2019). Un título. Revista, [falta: volumen].',
      );
    });

    test('una tesis sin universidad', () {
      final citation = reference(
        source(type: ReferenceType.thesis, people: [person('García', 'Ana')]),
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.publisher]);
      expect(
        citation.toPlainText(),
        'García, A. (2019). Un título [Tesis, [falta: editorial]].',
      );
    });

    test('una página web sin enlace', () {
      final citation = reference(
        source(type: ReferenceType.website, people: [institution('OMS')]),
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.link]);
      expect(citation.toPlainText(), endsWith('[falta: enlace]'));
    });

    test('sin tipo de obra: la forma general y el hueco', () {
      final citation = reference(
        source(people: [person('García', 'Ana')], publisher: 'Editorial'),
        language: CitationLanguage.es,
      );

      expect(citation.gaps, [CitationGap.type]);
      expect(
        citation.toPlainText(),
        'García, A. (2019). Un título [falta: tipo de obra]. Editorial.',
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

      expect(page.type, ReferenceType.website);
      expect(reference(page).gaps, isEmpty);
      expect(document.type, isNull);
      expect(reference(document).gaps, [CitationGap.type]);
    });

    test('en inglés dicen lo mismo con sus palabras', () {
      final citation = reference(
        source(type: ReferenceType.book, date: const PublicationDate.unknown()),
      );

      expect(citation.gaps, [
        CitationGap.author,
        CitationGap.year,
        CitationGap.publisher,
      ]);
      expect(
        citation.toPlainText(),
        '[missing: author]. ([missing: year]). Un título. '
        '[missing: publisher].',
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
    test('el DOI gana sobre el enlace y se escribe como enlace', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        doi: '10.1000/xyz',
        url: 'https://otro.org',
      );

      expect(plain(book), endsWith('https://doi.org/10.1000/xyz'));
      expect(plain(book), isNot(contains('otro.org')));
    });

    test('sin DOI, el enlace, sin punto final', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        url: 'https://otro.org/libro',
      );

      expect(plain(book), endsWith('Editorial. https://otro.org/libro'));
    });

    test('la fecha de consulta de una página web, si alguien la cargó', () {
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
        plain(page, language: CitationLanguage.es),
        'Pérez, J. (2020, 15 de marzo). Un artículo. Sitio. Recuperado el 5 de '
        'septiembre de 2026, de https://sitio.org/a',
      );
      expect(
        plain(page),
        endsWith('Retrieved September 5, 2026, from https://sitio.org/a'),
      );
    });

    test('sin fecha de consulta no se inventa una: no es la de captura', () {
      final page = source(
        type: ReferenceType.website,
        people: [person('Pérez', 'Juana')],
        url: 'https://sitio.org/a',
      );

      expect(plain(page), isNot(contains('Retrieved')));
      expect(plain(page), endsWith('https://sitio.org/a'));
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

      expect(plain(book), contains('(2019).'));
    });

    test('una página web cita hasta donde se sabe', () {
      String webDate(PublicationDate date) => plain(
        source(
          type: ReferenceType.website,
          people: [institution('OMS')],
          date: date,
          url: 'https://x.org',
        ),
      );

      expect(webDate(PublicationDate.ofYear(2019)), contains('(2019).'));
      expect(
        webDate(PublicationDate.ofMonth(2019, 3)),
        contains('(2019, March).'),
      );
      expect(
        webDate(PublicationDate.ofDay(2019, 3, 15)),
        contains('(2019, March 15).'),
      );
    });
  });

  group('los autores', () {
    test('sin personas, el autor de la captura va entero', () {
      final page = source(
        type: ReferenceType.website,
        authorName: 'Ana García Pérez',
        url: 'https://x.org',
      );

      expect(plain(page), startsWith('Ana García Pérez. (2019).'));
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

      expect(plain(one), 'Franco, J. (Ed.). (2019). Antología. Editorial.');
      expect(
        plain(two, language: CitationLanguage.es),
        'Franco, J. y Paz, O. (Eds.). (2019). Antología. Editorial.',
      );
    });

    test('el traductor va entre paréntesis, con «Trans.» o «Trad.»', () {
      Contributor translator(String family, String given) =>
          person(family, given, role: ContributorRole.translator);

      final one = source(
        title: 'Anna Karenina',
        type: ReferenceType.book,
        people: [person('Tolstoy', 'Leo'), translator('Pevear', 'Richard')],
        publisher: 'Penguin',
        date: PublicationDate.ofYear(2002),
      );
      final two = source(
        title: 'Anna Karenina',
        type: ReferenceType.book,
        people: [
          person('Tolstoy', 'Leo'),
          translator('Pevear', 'Richard'),
          translator('Volokhonsky', 'Larissa'),
        ],
        publisher: 'Penguin',
        edition: '2',
        date: PublicationDate.ofYear(2002),
      );

      expect(
        plain(one),
        'Tolstoy, L. (2002). Anna Karenina (R. Pevear, Trans.). Penguin.',
      );
      expect(
        plain(two),
        'Tolstoy, L. (2002). Anna Karenina (2nd ed., R. Pevear & L. '
        'Volokhonsky, Trans.). Penguin.',
      );
      expect(
        plain(two, language: CitationLanguage.es),
        'Tolstoy, L. (2002). Anna Karenina (2.ª ed., R. Pevear y L. '
        'Volokhonsky, Trads.). Penguin.',
      );
    });

    test('dos editores de un capítulo: sin coma antes de «&»', () {
      final chapter = source(
        title: 'La novela hispanoamericana',
        type: ReferenceType.chapter,
        people: [
          person('Fuentes', 'Carlos'),
          person('Franco', 'Jean', role: ContributorRole.editor),
          person('Paz', 'Octavio', role: ContributorRole.editor),
        ],
        container: 'Historia de la literatura',
        publisher: 'Editorial',
      );

      expect(
        plain(chapter),
        contains('In J. Franco & O. Paz (Eds.), Historia de la literatura'),
      );
      expect(
        plain(chapter, language: CitationLanguage.es),
        contains('En J. Franco y O. Paz (Eds.), Historia de la literatura'),
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

      expect(plain(book), startsWith('Tolstói, L. (2019).'));
    });

    test('con sufijo', () {
      final book = source(
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

      expect(plain(book), startsWith('King, M. L., Jr. (2019).'));
    });

    test('más de veinte: los diecinueve primeros, tres puntos y el último', () {
      final people = [
        for (var i = 1; i <= 21; i++) person('Autor$i', 'Nombre'),
      ];
      final citation = plain(
        source(
          type: ReferenceType.book,
          people: people,
          publisher: 'Editorial',
        ),
      );

      expect(citation, contains('Autor19, N., . . . Autor21, N. (2019).'));
      expect(citation, isNot(contains('Autor20')));
      expect(citation, startsWith('Autor1, N., Autor2, N.'));
    });
  });

  group('la letra del año', () {
    Citation withSuffix(CitationSource source, CitationForm form) =>
        style.format(
          form,
          source,
          const CitationContext(language: CitationLanguage.en, yearSuffix: 'a'),
        );

    test('va pegada al año, en la entrada y en la cita en el texto', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(
        withSuffix(book, CitationForm.reference).toPlainText(),
        'García, A. (2019a). Un título. Editorial.',
      );
      expect(
        withSuffix(book, CitationForm.inText).toPlainText(),
        '(García, 2019a)',
      );
    });

    test('también con la fecha entera de una página web', () {
      final page = source(
        type: ReferenceType.website,
        people: [institution('OMS')],
        date: PublicationDate.ofDay(2019, 3, 15),
        url: 'https://x.org',
      );

      expect(
        withSuffix(page, CitationForm.reference).toPlainText(),
        startsWith('OMS. (2019a, March 15). '),
      );
    });

    test('«s. f.» y un año desconocido no la llevan', () {
      final undated = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        date: const PublicationDate.undated(),
      );
      final unknown = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        date: const PublicationDate.unknown(),
      );

      expect(
        withSuffix(undated, CitationForm.reference).toPlainText(),
        contains('(n.d.)'),
      );
      expect(
        withSuffix(unknown, CitationForm.reference).toPlainText(),
        contains('([missing: year])'),
      );
    });
  });

  group('la edición', () {
    String edition(String? raw) => plain(
      source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        edition: raw,
      ),
    );

    test('un número se vuelve ordinal', () {
      expect(edition('2'), contains('(2nd ed.)'));
      expect(edition('3'), contains('(3rd ed.)'));
    });

    test('un texto que ya dice «ed.» se deja', () {
      expect(edition('Rev. ed.'), contains('(Rev. ed.)'));
      expect(edition('2nd edition'), contains('(2nd edition)'));
    });

    test('otro texto se completa', () {
      expect(edition('Revised'), contains('(Revised ed.)'));
    });

    test('sin edición no se escribe ninguna', () {
      expect(edition(null), isNot(contains('ed.')));
      expect(edition(null), 'García, A. (2019). Un título. Editorial.');
    });
  });

  group('un título que termina en signo', () {
    test('«?» no lleva otro punto', () {
      final book = source(
        title: '¿Qué es la literatura?',
        type: ReferenceType.book,
        people: [person('Sartre', 'Jean-Paul')],
        publisher: 'Losada',
      );

      expect(
        plain(book, language: CitationLanguage.es),
        'Sartre, J.-P. (2019). ¿Qué es la literatura? Losada.',
      );
    });
  });

  group('la cita en el texto', () {
    test('un autor', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
      );

      expect(inText(book).toPlainText(), '(Jackson, 2019)');
    });

    test('dos autores, con «&» en inglés y «y» en español', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Salas', 'Julia'), person('Ruiz', 'Carlos')],
      );

      expect(inText(book).toPlainText(), '(Salas & Ruiz, 2019)');
      expect(
        inText(book, language: CitationLanguage.es).toPlainText(),
        '(Salas y Ruiz, 2019)',
      );
    });

    test('«e» delante de un apellido que empieza con «i»', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Paz', 'Octavio'), person('Iglesias', 'María')],
      );

      expect(
        inText(book, language: CitationLanguage.es).toPlainText(),
        '(Paz e Iglesias, 2019)',
      );
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

      expect(inText(article).toPlainText(), '(Grady et al., 2019)');
    });

    test('una institución va entera', () {
      final page = source(
        type: ReferenceType.website,
        people: [institution('World Health Organization')],
        date: PublicationDate.ofYear(2018),
      );

      expect(inText(page).toPlainText(), '(World Health Organization, 2018)');
    });

    test('con la página, el rango o el minuto', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
      );

      expect(
        inText(book, locator: const CitationLocator.page('12')).toPlainText(),
        '(Jackson, 2019, p. 12)',
      );
      expect(
        inText(
          book,
          locator: const CitationLocator.page('12-14'),
        ).toPlainText(),
        '(Jackson, 2019, pp. 12–14)',
      );
      expect(
        inText(
          book,
          locator: const CitationLocator.time('0:14:35'),
        ).toPlainText(),
        '(Jackson, 2019, 0:14:35)',
      );
    });

    test('sin fecha y con la fecha desconocida', () {
      final undated = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
        date: const PublicationDate.undated(),
      );
      final unknown = source(
        type: ReferenceType.book,
        people: [person('Jackson', 'Lee M.')],
        date: const PublicationDate.unknown(),
      );

      expect(inText(undated).toPlainText(), '(Jackson, n.d.)');
      expect(
        inText(undated, language: CitationLanguage.es).toPlainText(),
        '(Jackson, s. f.)',
      );
      expect(inText(unknown).toPlainText(), '(Jackson, [missing: year])');
      expect(inText(unknown).gaps, [CitationGap.year]);
    });

    test('sin autor, el hueco', () {
      final citation = inText(source(type: ReferenceType.book));

      expect(citation.toPlainText(), '([missing: author], 2019)');
      expect(citation.gaps, [CitationGap.author]);
    });

    test('un documental se cita por su director', () {
      final documentary = source(
        type: ReferenceType.documentary,
        people: [person('Ruiz', 'Ana', role: ContributorRole.director)],
        date: PublicationDate.ofYear(2015),
      );

      expect(inText(documentary).toPlainText(), '(Ruiz, 2015)');
    });
  });

  group('todos los tipos', () {
    test('cada uno da una cita con su título, sin fallar', () {
      for (final type in [...ReferenceType.values, null]) {
        final citation = reference(
          source(
            type: type,
            people: [person('García', 'Ana')],
            publisher: 'Editorial',
            container: 'Contenedor',
            volume: '1',
            url: 'https://x.org/a',
          ),
        );

        expect(citation.toPlainText(), contains('Un título'), reason: '$type');
        expect(citation.toPlainText(), startsWith('García, A. (2019).'));
        expect(citation.toPlainText(), isNot(contains('..')), reason: '$type');
        expect(citation.toPlainText(), isNot(contains('  ')), reason: '$type');
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
          volume: '1',
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
