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
import 'package:sinapsis/features/citations/domain/services/styles/chicago_style.dart';

/// Chicago 17.ª edición, en notas y bibliografía y en autor-fecha (F15). Los
/// ejemplos en inglés son los del Manual de Estilo de Chicago —*Swing Time*,
/// *A Curious Mind*, el capítulo de Kelly, el artículo de Weinstein, la página
/// de Google—; los demás, el mismo esquema en español.
void main() {
  const notes = ChicagoStyle.notes();
  const authorDate = ChicagoStyle.authorDate();

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

  Citation make(
    ChicagoStyle style,
    CitationForm form,
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    CitationLocator? locator,
  }) => style.format(
    form,
    source,
    CitationContext(language: language, locator: locator),
  );

  String bibliography(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
  }) => make(
    notes,
    CitationForm.reference,
    source,
    language: language,
  ).toPlainText();

  String list(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
  }) => make(
    authorDate,
    CitationForm.reference,
    source,
    language: language,
  ).toPlainText();

  String note(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    String? page,
  }) => make(
    notes,
    CitationForm.note,
    source,
    language: language,
    locator: page == null ? null : CitationLocator.page(page),
  ).toPlainText();

  String shortNote(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    String? page,
  }) => make(
    notes,
    CitationForm.shortNote,
    source,
    language: language,
    locator: page == null ? null : CitationLocator.page(page),
  ).toPlainText();

  String inText(
    CitationSource source, {
    CitationLanguage language = CitationLanguage.en,
    CitationLocator? locator,
  }) => make(
    authorDate,
    CitationForm.inText,
    source,
    language: language,
    locator: locator,
  ).toPlainText();

  const es = CitationLanguage.es;

  // Los libros y artículos de los ejemplos del manual.
  final swingTime = source(
    title: 'Swing Time',
    type: ReferenceType.book,
    people: [person('Smith', 'Zadie')],
    publisher: 'Penguin Press',
    place: 'New York',
    date: PublicationDate.ofYear(2016),
  );
  final curiousMind = source(
    title: 'A Curious Mind: The Secret to a Bigger Life',
    type: ReferenceType.book,
    people: [person('Grazer', 'Brian'), person('Fishman', 'Charles')],
    publisher: 'Simon & Schuster',
    place: 'New York',
    date: PublicationDate.ofYear(2015),
  );
  final kelly = source(
    title:
        'Seeing Red: Mao Fetishism, Pax Americana, and the Moral Economy of '
        'War',
    type: ReferenceType.chapter,
    people: [
      person('Kelly', 'John D.'),
      person('Kelly', 'John D.', role: ContributorRole.editor),
      person('Jauregui', 'Beatrice', role: ContributorRole.editor),
      person('Mitchell', 'Sean T.', role: ContributorRole.editor),
      person('Walton', 'Jeremy', role: ContributorRole.editor),
    ],
    container: 'Anthropology and Global Counterinsurgency',
    publisher: 'University of Chicago Press',
    place: 'Chicago',
    pages: '67-83',
    date: PublicationDate.ofYear(2010),
  );
  final weinstein = source(
    title: 'The Market in Plato’s Republic',
    type: ReferenceType.article,
    people: [person('Weinstein', 'Joshua I.')],
    container: 'Classical Philology',
    volume: '104',
    pages: '439-58',
    doi: '10.1086/650405',
    date: PublicationDate.ofYear(2009),
  );
  final google = source(
    title: 'Privacy Policy',
    type: ReferenceType.website,
    people: [institution('Google')],
    container: 'Privacy & Terms',
    date: PublicationDate.ofDay(2018, 5, 25),
    url: 'https://policies.google.com/privacy',
  );

  group('los estilos', () {
    test('son dos, con nombres neutros', () {
      expect(notes.id, 'chicago17nb');
      expect(notes.name, 'Chicago 17 NB');
      expect(notes.system, ChicagoSystem.notesBibliography);
      expect(authorDate.id, 'chicago17ad');
      expect(authorDate.name, 'Chicago 17 AD');
      expect(authorDate.system, ChicagoSystem.authorDate);
    });

    test(
      'notas y bibliografía: la entrada y las dos notas, sin cita en el texto',
      () {
        expect(notes.forms, {
          CitationForm.reference,
          CitationForm.note,
          CitationForm.shortNote,
        });
        expect(make(notes, CitationForm.inText, swingTime).isEmpty, isTrue);
      },
    );

    test('autor-fecha: la entrada y la cita en el texto, sin notas', () {
      expect(authorDate.forms, {CitationForm.reference, CitationForm.inText});
      expect(make(authorDate, CitationForm.note, swingTime).isEmpty, isTrue);
      expect(
        make(authorDate, CitationForm.shortNote, swingTime).isEmpty,
        isTrue,
      );
    });

    test('no numeran sus entradas', () {
      expect(notes.isNumbered, isFalse);
      expect(authorDate.isNumbered, isFalse);
    });

    test('están en el registro', () {
      expect(kReferenceStyles.byId('chicago17nb'), isA<ChicagoStyle>());
      expect(kReferenceStyles.byId('chicago17ad'), isA<ChicagoStyle>());
    });
  });

  group('los ejemplos del manual, en notas y bibliografía', () {
    test('un libro: la entrada, la nota y la nota corta', () {
      expect(
        bibliography(swingTime),
        'Smith, Zadie. Swing Time. New York: Penguin Press, 2016.',
      );
      expect(
        note(swingTime, page: '315-16'),
        'Zadie Smith, Swing Time (New York: Penguin Press, 2016), 315–16.',
      );
      expect(shortNote(swingTime, page: '320'), 'Smith, Swing Time, 320.');
      expect(
        make(notes, CitationForm.reference, swingTime).toMarkdown(),
        'Smith, Zadie. *Swing Time*. New York: Penguin Press, 2016.',
      );
      expect(
        make(
          notes,
          CitationForm.note,
          swingTime,
          locator: const CitationLocator.page('315'),
        ).toMarkdown(),
        'Zadie Smith, *Swing Time* (New York: Penguin Press, 2016), 315.',
      );
    });

    test('dos autores: el primero invertido, y sin «A» en la nota corta', () {
      expect(
        bibliography(curiousMind),
        'Grazer, Brian, and Charles Fishman. A Curious Mind: The Secret to a '
        'Bigger Life. New York: Simon & Schuster, 2015.',
      );
      expect(
        note(curiousMind, page: '12'),
        'Brian Grazer and Charles Fishman, A Curious Mind: The Secret to a '
        'Bigger Life (New York: Simon & Schuster, 2015), 12.',
      );
      expect(
        shortNote(curiousMind, page: '12'),
        'Grazer and Fishman, Curious Mind, 12.',
      );
    });

    test('un capítulo de un libro editado', () {
      expect(
        bibliography(kelly),
        'Kelly, John D. “Seeing Red: Mao Fetishism, Pax Americana, and the '
        'Moral Economy of War.” In Anthropology and Global Counterinsurgency, '
        'edited by John D. Kelly, Beatrice Jauregui, Sean T. Mitchell, and '
        'Jeremy Walton, 67–83. Chicago: University of Chicago Press, 2010.',
      );
      expect(
        note(kelly, page: '77'),
        'John D. Kelly, “Seeing Red: Mao Fetishism, Pax Americana, and the '
        'Moral Economy of War,” in Anthropology and Global Counterinsurgency, '
        'ed. John D. Kelly et al. (Chicago: University of Chicago Press, '
        '2010), 77.',
      );
      expect(shortNote(kelly, page: '81'), 'Kelly, “Seeing Red,” 81.');
    });

    test('un artículo: la entrada, la nota y la nota corta', () {
      expect(
        bibliography(weinstein),
        'Weinstein, Joshua I. “The Market in Plato’s Republic.” Classical '
        'Philology 104 (2009): 439–58. https://doi.org/10.1086/650405.',
      );
      expect(
        note(weinstein, page: '440'),
        'Joshua I. Weinstein, “The Market in Plato’s Republic,” Classical '
        'Philology 104 (2009): 440, https://doi.org/10.1086/650405.',
      );
      expect(
        shortNote(weinstein, page: '441'),
        'Weinstein, “Market in Plato’s Republic,” 441.',
      );
      // La revista, en cursiva; el título del artículo, entre comillas.
      expect(
        make(notes, CitationForm.reference, weinstein).toMarkdown(),
        contains('Republic.” *Classical Philology* 104'),
      );
    });

    test(
      'una página web: el sitio sin formato, la fecha entera y la dirección',
      () {
        expect(
          bibliography(google),
          'Google. “Privacy Policy.” Privacy & Terms. May 25, 2018. '
          'https://policies.google.com/privacy.',
        );
        expect(
          note(google),
          'Google, “Privacy Policy,” Privacy & Terms, May 25, 2018, '
          'https://policies.google.com/privacy.',
        );
        expect(
          make(notes, CitationForm.reference, google).toMarkdown(),
          contains('“Privacy Policy.” Privacy & Terms.'),
        );
      },
    );
  });

  group('los ejemplos del manual, en autor-fecha', () {
    test('un libro: la entrada y la cita en el texto', () {
      expect(
        list(swingTime),
        'Smith, Zadie. 2016. Swing Time. New York: Penguin Press.',
      );
      expect(inText(swingTime), '(Smith 2016)');
      expect(
        inText(swingTime, locator: const CitationLocator.page('315-16')),
        '(Smith 2016, 315–16)',
      );
    });

    test('dos autores: con «and» en el texto', () {
      expect(
        list(curiousMind),
        'Grazer, Brian, and Charles Fishman. 2015. A Curious Mind: The Secret '
        'to a Bigger Life. New York: Simon & Schuster.',
      );
      expect(inText(curiousMind), '(Grazer and Fishman 2015)');
    });

    test('un capítulo de un libro editado', () {
      expect(
        list(kelly),
        'Kelly, John D. 2010. “Seeing Red: Mao Fetishism, Pax Americana, and '
        'the Moral Economy of War.” In Anthropology and Global '
        'Counterinsurgency, edited by John D. Kelly, Beatrice Jauregui, Sean '
        'T. Mitchell, and Jeremy Walton, 67–83. Chicago: University of '
        'Chicago Press.',
      );
    });

    test('un artículo: el número entre paréntesis, sin «no.»', () {
      final withIssue = source(
        title: 'The Market in Plato’s Republic',
        type: ReferenceType.article,
        people: [person('Weinstein', 'Joshua I.')],
        container: 'Classical Philology',
        volume: '104',
        issue: '4',
        pages: '439-58',
        doi: '10.1086/650405',
        date: PublicationDate.ofYear(2009),
      );

      expect(
        list(withIssue),
        'Weinstein, Joshua I. 2009. “The Market in Plato’s Republic.” '
        'Classical Philology 104 (4): 439–58. https://doi.org/10.1086/650405.',
      );
      expect(
        bibliography(withIssue),
        contains('Classical Philology 104, no. 4 (2009): 439–58.'),
      );
    });

    test(
      'una página web: el año detrás del autor y la fecha entera después',
      () {
        expect(
          list(google),
          'Google. 2018. “Privacy Policy.” Privacy & Terms. May 25, 2018. '
          'https://policies.google.com/privacy.',
        );
        expect(inText(google), '(Google 2018)');
      },
    );
  });

  group('en español', () {
    test('un libro: comillas angulares, la traducción y la edición', () {
      final book = source(
        title: 'Ana Karenina',
        type: ReferenceType.book,
        people: [
          person('Tolstói', 'León'),
          person('Cansinos', 'Rafael', role: ContributorRole.translator),
        ],
        publisher: 'Aguilar',
        place: 'Madrid',
        edition: '2',
        date: PublicationDate.ofYear(1961),
      );

      expect(
        bibliography(book, language: es),
        'Tolstói, León. Ana Karenina. Traducción de Rafael Cansinos. 2.ª ed. '
        'Madrid: Aguilar, 1961.',
      );
      expect(
        note(book, language: es, page: '12'),
        'León Tolstói, Ana Karenina, trad. Rafael Cansinos, 2.ª ed. (Madrid: '
        'Aguilar, 1961), 12.',
      );
      expect(
        list(book, language: es),
        'Tolstói, León. 1961. Ana Karenina. Traducción de Rafael Cansinos. '
        '2.ª ed. Madrid: Aguilar.',
      );
    });

    test('un capítulo: «En», «edición de» y la puntuación afuera', () {
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
        bibliography(chapter, language: es),
        'Fuentes, Carlos. «La novela hispanoamericana». En Historia de la '
        'literatura, edición de Jean Franco, 120–145. México: Fondo de '
        'Cultura Económica, 1969.',
      );
      expect(
        note(chapter, language: es, page: '130'),
        'Carlos Fuentes, «La novela hispanoamericana», en Historia de la '
        'literatura, ed. Jean Franco (México: Fondo de Cultura Económica, '
        '1969), 130.',
      );
      expect(
        shortNote(chapter, language: es, page: '130'),
        'Fuentes, «La novela hispanoamericana», 130.',
      );
    });

    test('un artículo: «núm.» y el volumen', () {
      final article = source(
        title: 'Redes de citación',
        type: ReferenceType.article,
        people: [person('Ruiz', 'Ana')],
        container: 'Revista de Datos',
        volume: '8',
        issue: '3',
        pages: '207-17',
      );

      expect(
        bibliography(article, language: es),
        'Ruiz, Ana. «Redes de citación». Revista de Datos 8, núm. 3 (2019): '
        '207–17.',
      );
      expect(
        list(article, language: es),
        'Ruiz, Ana. 2019. «Redes de citación». Revista de Datos 8 (3): '
        '207–17.',
      );
    });

    test('una tesis', () {
      final thesis = source(
        title: 'Redes de citación',
        type: ReferenceType.thesis,
        people: [person('Cabrera', 'Elena')],
        publisher: 'Universidad de Chile',
        date: PublicationDate.ofYear(2020),
      );

      expect(
        bibliography(thesis, language: es),
        'Cabrera, Elena. «Redes de citación». Tesis, Universidad de Chile, '
        '2020.',
      );
      expect(
        note(thesis, language: es, page: '45'),
        'Elena Cabrera, «Redes de citación» (tesis, Universidad de Chile, '
        '2020), 45.',
      );
      expect(
        list(thesis, language: es),
        'Cabrera, Elena. 2020. «Redes de citación». Tesis, Universidad de '
        'Chile.',
      );
    });

    test('un documental: por su director, con «dir.»', () {
      final film = source(
        title: 'La ciudad fantasma',
        type: ReferenceType.documentary,
        people: [person('Ruiz', 'Ana', role: ContributorRole.director)],
        publisher: 'Producciones Sur',
        place: 'Buenos Aires',
        date: PublicationDate.ofYear(2015),
      );

      expect(
        bibliography(film, language: es),
        'Ruiz, Ana, dir. La ciudad fantasma. Buenos Aires: Producciones Sur, '
        '2015.',
      );
      expect(
        note(film, language: es),
        'Ana Ruiz, dir., La ciudad fantasma (Buenos Aires: Producciones Sur, '
        '2015).',
      );
      expect(shortNote(film, language: es), 'Ruiz, La ciudad fantasma.');
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
        bibliography(letter, language: es),
        'Colón, Cristóbal. «Carta a Luis de Santángel». Archivo General de '
        'Indias, 1493.',
      );
      expect(
        note(letter, language: es),
        'Cristóbal Colón, «Carta a Luis de Santángel», Archivo General de '
        'Indias, 1493.',
      );
      // «de» no queda colgando al final del título abreviado.
      expect(shortNote(letter, language: es), 'Colón, «Carta a Luis».');
    });

    test('un video de YouTube: «Video de YouTube» y el canal entero', () {
      final video = source(
        title: 'La torre más alta',
        kind: SourceKind.youtube,
        authorName: 'Kurzgesagt – In a Nutshell',
        date: PublicationDate.ofDay(2020, 3, 5),
        url: 'https://www.youtube.com/watch?v=abc123',
      );

      expect(
        bibliography(video, language: es),
        'Kurzgesagt – In a Nutshell. «La torre más alta». Video de YouTube. 5 '
        'de marzo de 2020. https://www.youtube.com/watch?v=abc123.',
      );
      expect(
        bibliography(video),
        'Kurzgesagt – In a Nutshell. “La torre más alta.” YouTube video. March '
        '5, 2020. https://www.youtube.com/watch?v=abc123.',
      );
      expect(
        note(video, language: es),
        'Kurzgesagt – In a Nutshell, «La torre más alta», Video de YouTube, '
        '5 de marzo de 2020, https://www.youtube.com/watch?v=abc123.',
      );
    });

    test(
      'dos autores: «y», con la coma de la estructura solo en la entrada',
      () {
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
          bibliography(book, language: es),
          'García Márquez, Gabriel, y Plinio Apuleyo Mendoza. El olor de la '
          'guayaba. Oveja Negra, 1982.',
        );
        expect(
          note(book, language: es),
          'Gabriel García Márquez y Plinio Apuleyo Mendoza, El olor de la '
          'guayaba (Oveja Negra, 1982).',
        );
        expect(inText(book, language: es), '(García Márquez y Mendoza 1982)');
      },
    );

    test('tres autores: sin coma antes de «y»; «e» delante de una «i»', () {
      final three = source(
        type: ReferenceType.book,
        people: [
          person('Vargas Llosa', 'Mario'),
          person('García Márquez', 'Gabriel'),
          person('Cortázar', 'Julio'),
        ],
        publisher: 'Editorial',
      );
      final two = source(
        type: ReferenceType.book,
        people: [person('Paz', 'Octavio'), person('López', 'Irene')],
        publisher: 'Editorial',
      );

      expect(
        bibliography(three, language: es),
        startsWith(
          'Vargas Llosa, Mario, Gabriel García Márquez y Julio Cortázar. ',
        ),
      );
      expect(
        bibliography(two, language: es),
        startsWith('Paz, Octavio, e Irene López. '),
      );
    });
  });

  group('las notas', () {
    test('sin pasaje, la nota cita la obra entera', () {
      expect(
        note(swingTime),
        'Zadie Smith, Swing Time (New York: Penguin Press, 2016).',
      );
      expect(shortNote(swingTime), 'Smith, Swing Time.');
    });

    test('el pasaje puede ser una página, un rango o un minuto', () {
      String at(CitationLocator locator) => make(
        notes,
        CitationForm.note,
        swingTime,
        locator: locator,
      ).toPlainText();

      expect(at(const CitationLocator.page('12')), endsWith('2016), 12.'));
      expect(
        at(const CitationLocator.page('12-14')),
        endsWith('2016), 12–14.'),
      );
      expect(
        at(const CitationLocator.time('0:14:35')),
        endsWith('2016), 0:14:35.'),
      );
    });

    test('un artículo sin pasaje cita sus páginas', () {
      expect(
        note(weinstein),
        'Joshua I. Weinstein, “The Market in Plato’s Republic,” Classical '
        'Philology 104 (2009): 439–58, https://doi.org/10.1086/650405.',
      );
    });

    test('hasta tres autores, todos; con cuatro, el primero y «et al.»', () {
      CitationSource authors(int count) => source(
        title: 'Un libro',
        type: ReferenceType.book,
        people: [
          for (var i = 1; i <= count; i++) person('Apellido$i', 'Nombre$i'),
        ],
        publisher: 'Editorial',
      );

      expect(
        note(authors(3)),
        startsWith('Nombre1 Apellido1, Nombre2 Apellido2, and Nombre3 '),
      );
      expect(
        note(authors(4)),
        startsWith('Nombre1 Apellido1 et al., Un libro'),
      );
      expect(shortNote(authors(3)), startsWith('Apellido1, Apellido2, and '));
      expect(shortNote(authors(4)), startsWith('Apellido1 et al., Un libro'));
    });

    test('un libro compilado se cita por sus editores: «ed.» y «eds.»', () {
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

      expect(bibliography(one), startsWith('Franco, Jean, ed. Antología.'));
      expect(
        bibliography(two),
        startsWith('Franco, Jean, and Octavio Paz, eds. Antología.'),
      );
      expect(note(one), startsWith('Jean Franco, ed., Antología ('));
      expect(note(two), startsWith('Jean Franco and Octavio Paz, eds., '));
    });

    test(
      'una traducción: «trans.» en la nota y «Translated by» en la entrada',
      () {
        final book = source(
          title: 'Anna Karenina',
          type: ReferenceType.book,
          people: [
            person('Tolstoy', 'Leo'),
            person('Pevear', 'Richard', role: ContributorRole.translator),
            person('Volokhonsky', 'Larissa', role: ContributorRole.translator),
          ],
          publisher: 'Penguin',
          place: 'New York',
          date: PublicationDate.ofYear(2004),
        );

        expect(
          bibliography(book),
          'Tolstoy, Leo. Anna Karenina. Translated by Richard Pevear and '
          'Larissa Volokhonsky. New York: Penguin, 2004.',
        );
        expect(
          note(book),
          'Leo Tolstoy, Anna Karenina, trans. Richard Pevear and Larissa '
          'Volokhonsky (New York: Penguin, 2004).',
        );
      },
    );

    test('un diario o una revista sin volumen: la fecha entera', () {
      final paper = source(
        title: 'Un artículo de diario',
        type: ReferenceType.article,
        people: [person('Ruiz', 'Ana')],
        container: 'El Diario',
        pages: '34-35',
        date: PublicationDate.ofDay(2020, 3, 5),
      );

      expect(
        bibliography(paper),
        'Ruiz, Ana. “Un artículo de diario.” El Diario, March 5, 2020, 34–35.',
      );
      expect(
        list(paper),
        'Ruiz, Ana. 2020. “Un artículo de diario.” El Diario, March 5, 2020, '
        '34–35.',
      );
      expect(
        note(paper, page: '34'),
        'Ana Ruiz, “Un artículo de diario,” El Diario, March 5, 2020, 34.',
      );
    });

    test('una obra con dirección y sin fecha de publicación: «accessed»', () {
      final page = source(
        title: 'About Yale',
        type: ReferenceType.website,
        people: [institution('Yale University')],
        date: const PublicationDate.unknown(),
        url: 'https://www.yale.edu/about-yale',
        capturedAt: DateTime(2026, 9, 5),
      );
      final loaded = source(
        title: 'About Yale',
        type: ReferenceType.website,
        people: [institution('Yale University')],
        url: 'https://www.yale.edu/about-yale',
        accessedAt: DateTime(2026, 3, 15),
      );

      expect(
        bibliography(page),
        'Yale University. “About Yale.” [missing: year]. Accessed September 5, '
        '2026. https://www.yale.edu/about-yale.',
      );
      expect(
        note(page),
        'Yale University, “About Yale,” [missing: year], accessed September 5, '
        '2026, https://www.yale.edu/about-yale.',
      );
      // Si alguien cargó la fecha de consulta, también se escribe con fecha.
      expect(
        bibliography(loaded),
        contains('Accessed March 15, 2026. https://www.yale.edu'),
      );
      expect(
        bibliography(loaded, language: es),
        contains('Consultado el 15 de marzo de 2026.'),
      );
    });

    test('una fecha de mes: «March 2020»; de año: «2020»', () {
      String site(PublicationDate date, {CitationLanguage? language}) =>
          bibliography(
            source(
              type: ReferenceType.website,
              people: [institution('OMS')],
              date: date,
              url: 'https://x.org',
            ),
            language: language ?? CitationLanguage.en,
          );

      expect(site(PublicationDate.ofYear(2020)), contains('” 2020. https'));
      expect(
        site(PublicationDate.ofMonth(2020, 3)),
        contains('” March 2020. https'),
      );
      expect(
        site(PublicationDate.ofMonth(2020, 3), language: es),
        contains('». marzo de 2020. https'),
      );
    });
  });

  group('la nota corta', () {
    String short(String title, {CitationLanguage? language}) => shortNote(
      source(
        title: title,
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
      ),
      language: language ?? CitationLanguage.en,
    );

    test('lo que está antes de los dos puntos', () {
      expect(
        short('Anna Karenina: A Novel in Eight Parts'),
        'García, Anna Karenina.',
      );
    });

    test('cuatro palabras como mucho', () {
      expect(
        short('One Two Three Four Five Six'),
        'García, One Two Three Four.',
      );
      expect(short('One Two Three Four'), 'García, One Two Three Four.');
    });

    test('en inglés sin «A», «An» ni «The»; en español, con el artículo', () {
      expect(short('The Great Gatsby'), 'García, Great Gatsby.');
      expect(short('A Curious Mind'), 'García, Curious Mind.');
      expect(short('El olor de la guayaba', language: es), 'García, El olor.');
    });

    test('no queda una preposición colgando al cortar', () {
      expect(short('Carta a Luis de Santángel'), 'García, Carta a Luis.');
      expect(short('The Rise of the West'), 'García, Rise of the West.');
    });

    test('un título de una sola palabra queda entero', () {
      expect(short('Beloved'), 'García, Beloved.');
      expect(short('The'), 'García, The.');
    });

    test('la cursiva de un libro y las comillas de un artículo', () {
      final book = make(
        notes,
        CitationForm.shortNote,
        swingTime,
        locator: const CitationLocator.page('3'),
      );
      final article = make(
        notes,
        CitationForm.shortNote,
        weinstein,
        locator: const CitationLocator.page('3'),
      );

      expect(book.toMarkdown(), 'Smith, *Swing Time*, 3.');
      expect(
        article.toMarkdown(),
        'Weinstein, “Market in Plato’s Republic,” 3.',
      );
    });

    test('un título que termina en «?» no lleva coma', () {
      final article = source(
        title: 'Is Literature Dead?',
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
      );

      expect(shortNote(article, page: '4'), 'García, “Is Literature Dead?” 4.');
    });
  });

  group('la cita en el texto de autor-fecha', () {
    test('un autor, dos, tres y más', () {
      CitationSource authors(int count) => source(
        type: ReferenceType.book,
        people: [
          for (var i = 1; i <= count; i++) person('Apellido$i', 'Nombre'),
        ],
      );

      expect(inText(authors(1)), '(Apellido1 2019)');
      expect(inText(authors(2)), '(Apellido1 and Apellido2 2019)');
      expect(inText(authors(3)), '(Apellido1, Apellido2, and Apellido3 2019)');
      expect(inText(authors(4)), '(Apellido1 et al. 2019)');
      expect(
        inText(authors(3), language: es),
        '(Apellido1, Apellido2 y Apellido3 2019)',
      );
    });

    test('una institución va entera', () {
      expect(inText(google), '(Google 2018)');
    });

    test('con la página, el rango o el minuto', () {
      expect(
        inText(swingTime, locator: const CitationLocator.page('12')),
        '(Smith 2016, 12)',
      );
      expect(
        inText(swingTime, locator: const CitationLocator.page('12-14')),
        '(Smith 2016, 12–14)',
      );
      expect(
        inText(swingTime, locator: const CitationLocator.time('0:14:35')),
        '(Smith 2016, 0:14:35)',
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

      expect(inText(undated), '(Jackson n.d.)');
      expect(inText(undated, language: es), '(Jackson s. f.)');
      expect(inText(unknown), '(Jackson [missing: year])');
      expect(make(authorDate, CitationForm.inText, unknown).gaps, [
        CitationGap.year,
      ]);
    });

    test('sin autor, el hueco', () {
      final citation = make(
        authorDate,
        CitationForm.inText,
        source(type: ReferenceType.book),
      );

      expect(citation.toPlainText(), '([missing: author] 2019)');
      expect(citation.gaps, [CitationGap.author]);
    });
  });

  group('lo que falta se marca, no se inventa ni se omite', () {
    test('un año que nadie cargó es un hueco; «sin fecha» es otra cosa', () {
      final unknown = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        date: const PublicationDate.unknown(),
      );
      final undated = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        date: const PublicationDate.undated(),
      );

      expect(
        bibliography(unknown, language: es),
        'García, Ana. Un título. Editorial, [falta: año].',
      );
      expect(
        list(unknown, language: es),
        'García, Ana. [falta: año]. Un título. Editorial.',
      );
      expect(bibliography(undated), 'García, Ana. Un título. Editorial, n.d.');
      expect(
        list(undated, language: es),
        'García, Ana. s. f. Un título. Editorial.',
      );
      expect(make(notes, CitationForm.reference, unknown).gaps, [
        CitationGap.year,
      ]);
    });

    test('sin autor, en la entrada, la nota y la nota corta', () {
      final book = source(type: ReferenceType.book, publisher: 'Editorial');

      expect(
        bibliography(book, language: es),
        '[falta: autor]. Un título. Editorial, 2019.',
      );
      expect(
        note(book, language: es),
        '[falta: autor], Un título (Editorial, 2019).',
      );
      expect(shortNote(book, language: es), '[falta: autor], Un título.');
      expect(make(notes, CitationForm.note, book).gaps, [CitationGap.author]);
    });

    test('sin título', () {
      final book = source(
        title: '  ',
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(
        bibliography(book, language: es),
        'García, Ana. [falta: título]. Editorial, 2019.',
      );
      expect(
        note(book, language: es),
        'Ana García, [falta: título] (Editorial, 2019).',
      );
      expect(make(notes, CitationForm.reference, book).gaps, [
        CitationGap.title,
      ]);
    });

    test('un libro sin editorial', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
      );

      expect(
        bibliography(book, language: es),
        'García, Ana. Un título. [falta: editorial], 2019.',
      );
      expect(
        list(book, language: es),
        'García, Ana. 2019. Un título. [falta: editorial].',
      );
      expect(
        note(book, language: es),
        'Ana García, Un título ([falta: editorial], 2019).',
      );
    });

    test('un capítulo sin el libro que lo contiene', () {
      final chapter = source(
        type: ReferenceType.chapter,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(
        bibliography(chapter, language: es),
        'García, Ana. «Un título». En [falta: publicado en]. Editorial, 2019.',
      );
      expect(make(notes, CitationForm.note, chapter).gaps, [
        CitationGap.container,
      ]);
    });

    test('un artículo sin revista', () {
      final article = source(
        type: ReferenceType.article,
        people: [person('García', 'Ana')],
        volume: '8',
      );

      expect(
        bibliography(article, language: es),
        'García, Ana. «Un título». [falta: publicado en] 8 (2019).',
      );
      expect(make(notes, CitationForm.reference, article).gaps, [
        CitationGap.container,
      ]);
    });

    test('una tesis sin universidad', () {
      final thesis = source(
        type: ReferenceType.thesis,
        people: [person('García', 'Ana')],
      );

      expect(
        bibliography(thesis, language: es),
        'García, Ana. «Un título». Tesis, [falta: editorial], 2019.',
      );
      expect(
        note(thesis, language: es),
        'Ana García, «Un título» (tesis, [falta: editorial], 2019).',
      );
    });

    test('una página web sin enlace', () {
      final page = source(
        type: ReferenceType.website,
        people: [institution('OMS')],
      );

      expect(
        bibliography(page, language: es),
        'OMS. «Un título». 2019. [falta: enlace].',
      );
      expect(
        note(page, language: es),
        'OMS, «Un título», 2019, [falta: enlace].',
      );
      expect(make(notes, CitationForm.reference, page).gaps, [
        CitationGap.link,
      ]);
    });

    test('sin tipo de obra: la forma general y el hueco', () {
      final citation = source(
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(
        bibliography(citation, language: es),
        'García, Ana. Un título [falta: tipo de obra]. Editorial, 2019.',
      );
      expect(
        note(citation, language: es),
        'Ana García, Un título [falta: tipo de obra] (Editorial, 2019).',
      );
      expect(make(notes, CitationForm.reference, citation).gaps, [
        CitationGap.type,
      ]);
    });

    test('lo opcional que falta no se marca: la ciudad y el volumen', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
      );

      expect(make(notes, CitationForm.reference, book).hasGaps, isFalse);
      expect(make(notes, CitationForm.note, book).hasGaps, isFalse);
      expect(make(authorDate, CitationForm.reference, book).hasGaps, isFalse);
    });
  });

  group('los autores', () {
    test('más de diez: los siete primeros y «et al.»', () {
      List<Contributor> authors(int count) => [
        for (var i = 1; i <= count; i++) person('Apellido$i', 'Nombre$i'),
      ];

      final ten = bibliography(
        source(
          type: ReferenceType.book,
          people: authors(10),
          publisher: 'Editorial',
        ),
      );
      final eleven = bibliography(
        source(
          type: ReferenceType.book,
          people: authors(11),
          publisher: 'Editorial',
        ),
      );

      expect(ten, contains('Nombre9 Apellido9, and Nombre10 Apellido10. '));
      expect(
        eleven,
        startsWith(
          'Apellido1, Nombre1, Nombre2 Apellido2, Nombre3 Apellido3, Nombre4 '
          'Apellido4, Nombre5 Apellido5, Nombre6 Apellido6, Nombre7 '
          'Apellido7, et al. ',
        ),
      );
      expect(eleven, isNot(contains('Apellido8')));
    });

    test('un sufijo va después de una coma en la entrada', () {
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

      expect(
        bibliography(book),
        startsWith('King, Martin Luther, Jr. Un título.'),
      );
      expect(note(book), startsWith('Martin Luther King Jr., Un título'));
    });

    test('sin personas, el autor de la captura va entero', () {
      final page = source(
        type: ReferenceType.website,
        authorName: 'Ana García Pérez',
        url: 'https://x.org',
      );

      expect(bibliography(page), startsWith('Ana García Pérez. “Un título.”'));
      expect(note(page), startsWith('Ana García Pérez, “Un título,”'));
    });
  });

  group('la edición y las páginas', () {
    test('la edición y el volumen, en oraciones de la entrada', () {
      final book = source(
        type: ReferenceType.book,
        people: [person('García', 'Ana')],
        publisher: 'Editorial',
        place: 'Lima',
        edition: '3',
        volume: '2',
      );

      expect(
        bibliography(book),
        'García, Ana. Un título. 3rd ed. Vol. 2. Lima: Editorial, 2019.',
      );
      expect(
        note(book),
        'Ana García, Un título, 3rd ed., vol. 2 (Lima: Editorial, 2019).',
      );
    });

    test('las páginas van con raya y sin «pp.», y se escriben completas', () {
      final chapter = source(
        type: ReferenceType.chapter,
        people: [person('García', 'Ana')],
        container: 'Libro',
        publisher: 'Editorial',
        pages: '207-217',
      );

      expect(
        bibliography(chapter),
        contains('Libro, 207–217. Editorial, 2019.'),
      );
    });
  });

  group('todos los tipos', () {
    CitationSource complete(ReferenceType? type) => source(
      type: type,
      people: [
        person(
          'García',
          'Ana',
          role: type == ReferenceType.documentary
              ? ContributorRole.director
              : ContributorRole.author,
        ),
      ],
      publisher: 'Editorial',
      container: 'Contenedor',
      volume: '1',
      url: 'https://x.org/a',
      capturedAt: DateTime(2026, 9, 5),
    );

    test('cada uno da todas sus formas con su título, sin fallar', () {
      for (final type in [...ReferenceType.values, null]) {
        for (final language in CitationLanguage.values) {
          for (final style in [notes, authorDate]) {
            for (final form in style.forms) {
              final text = make(
                style,
                form,
                complete(type),
                language: language,
                locator: const CitationLocator.page('12'),
              ).toPlainText();
              final reason = '$type $language ${style.id} $form';

              expect(text, contains('García'), reason: reason);
              expect(text, isNot(contains('..')), reason: reason);
              expect(text, isNot(contains('  ')), reason: reason);
              expect(text, isNot(contains(',,')), reason: reason);
              if (form != CitationForm.inText) {
                expect(text, contains('Un título'), reason: reason);
                expect(text, endsWith('.'), reason: reason);
              }
            }
          }
        }
      }
    });

    test('una fuente completa de cada tipo no tiene huecos', () {
      final sources = <ReferenceType, CitationSource>{
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

      expect(sources.keys, unorderedEquals(ReferenceType.values));
      for (final entry in sources.entries) {
        for (final style in [notes, authorDate]) {
          for (final form in style.forms) {
            expect(
              make(style, form, entry.value).hasGaps,
              isFalse,
              reason: '${entry.key.name} ${style.id} $form',
            );
          }
        }
      }
    });
  });
}
