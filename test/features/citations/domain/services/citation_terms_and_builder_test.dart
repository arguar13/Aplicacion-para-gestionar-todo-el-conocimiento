import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_builder.dart';
import 'package:sinapsis/features/citations/domain/services/citation_names.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';

/// Lo que todos los estilos comparten (F15): los términos en español y en
/// inglés, el armador con su puntuación y los nombres.
void main() {
  const es = CitationTerms.es;
  const en = CitationTerms.en;

  group('los términos', () {
    test('cada idioma trae los suyos', () {
      expect(CitationTerms.of(CitationLanguage.es), same(es));
      expect(CitationTerms.of(CitationLanguage.en), same(en));
      expect(es.noDate, 's. f.');
      expect(en.noDate, 'n.d.');
      expect(es.inWord, 'En');
      expect(en.inWord, 'In');
    });

    test('un código desconocido cae en español', () {
      expect(CitationLanguage.fromCode('en'), CitationLanguage.en);
      expect(CitationLanguage.fromCode('es'), CitationLanguage.es);
      expect(CitationLanguage.fromCode('fr'), CitationLanguage.es);
      expect(CitationLanguage.fromCode(null), CitationLanguage.es);
    });

    test('los huecos dicen qué falta en el idioma de la cita', () {
      for (final gap in CitationGap.values) {
        expect(es.gap(gap).field, gap);
        expect(es.gapLabels.containsKey(gap), isTrue, reason: '$gap');
        expect(en.gapLabels.containsKey(gap), isTrue, reason: '$gap');
      }
      expect(es.gap(CitationGap.year).text, '[falta: año]');
      expect(en.gap(CitationGap.year).text, '[missing: year]');
      expect(es.gap(CitationGap.accessed).text, '[falta: fecha de consulta]');
      expect(en.gap(CitationGap.accessed).text, '[missing: access date]');
    });

    test('el mes tiene su nombre', () {
      expect(es.monthName(1), 'enero');
      expect(es.monthName(9), 'septiembre');
      expect(en.monthName(12), 'December');
    });

    test('cada estilo abrevia los meses a su manera: doce en cada lista', () {
      for (final terms in [es, en]) {
        expect(terms.months, hasLength(12));
        expect(terms.monthsShort, hasLength(12));
        expect(terms.monthsIeee, hasLength(12));
      }
      // MLA: «Sept.», «June»; IEEE: «Sep.», «Jun.».
      expect(en.monthsShort[8], 'Sept.');
      expect(en.monthsShort[5], 'June');
      expect(en.monthsIeee[8], 'Sep.');
      expect(en.monthsIeee[5], 'Jun.');
      expect(es.monthsShort[8], 'sept.');
      expect(es.monthsShort[4], 'mayo');
    });

    test('la fecha de MLA: el día antes del mes en los dos idiomas', () {
      expect(en.mlaDate(2020), '2020');
      expect(en.mlaDate(2020, month: 3), 'Mar. 2020');
      expect(en.mlaDate(2020, month: 3, day: 5), '5 Mar. 2020');
      expect(es.mlaDate(2020, month: 9, day: 5), '5 sept. 2020');
    });

    test('la fecha de IEEE: mes y día en inglés, día y mes en español', () {
      expect(en.ieeeDate(2020), '2020');
      expect(en.ieeeDate(2020, month: 3), 'Mar. 2020');
      expect(en.ieeeDate(2020, month: 3, day: 5), 'Mar. 5, 2020');
      expect(es.ieeeDate(2020, month: 3, day: 5), '5 mar. 2020');
    });

    test('la fecha entera de Chicago, hasta donde se sabe', () {
      expect(en.longPartialDate(2020), '2020');
      expect(en.longPartialDate(2020, month: 3), 'March 2020');
      expect(en.longPartialDate(2020, month: 3, day: 5), 'March 5, 2020');
      expect(es.longPartialDate(2020, month: 3), 'marzo de 2020');
      expect(es.longPartialDate(2020, month: 3, day: 5), '5 de marzo de 2020');
    });

    test('cómo se describe un video de una plataforma', () {
      expect(en.videoOn('YouTube'), 'YouTube video');
      expect(es.videoOn('YouTube'), 'Video de YouTube');
    });

    test('el rol abreviado de Chicago es igual en los dos idiomas', () {
      for (final terms in [es, en]) {
        expect(terms.editorAbbr, 'ed.');
        expect(terms.editorsAbbr, 'eds.');
        expect(terms.directorAbbr, 'dir.');
        expect(terms.directorsAbbr, 'dirs.');
      }
    });

    test(
      'las comillas: la puntuación adentro en inglés, afuera en español',
      () {
        expect(en.quoteOpen + en.quoteClose, '“”');
        expect(en.quotePunctuationInside, isTrue);
        expect(es.quoteOpen + es.quoteClose, '«»');
        expect(es.quotePunctuationInside, isFalse);
      },
    );

    test('las palabras de MLA e IEEE', () {
      expect(en.translatedBy, 'translated by');
      expect(es.translatedBy, 'traducción de');
      expect(en.editedBy, 'edited by');
      expect(es.editedBy, 'edición de');
      expect(en.editorsRole, 'editors');
      expect(es.editorsRole, 'eds.');
      expect(en.directorRole, 'director');
      expect(es.directorRole, 'dir.');
      expect(en.numberAbbr, 'no.');
      expect(es.numberAbbr, 'núm.');
      expect(en.accessed, 'Accessed');
      expect(es.accessed, 'Consultado el');
      expect(en.ieeeOnline, '[Online]. Available:');
      expect(es.ieeeOnline, '[En línea]. Disponible en:');
      expect(en.ieeeAccessed, 'Accessed:');
      expect(es.ieeeAccessed, 'Consultado:');
    });

    test('los ordinales', () {
      expect(es.ordinal(2), '2.ª');
      expect(en.ordinal(1), '1st');
      expect(en.ordinal(2), '2nd');
      expect(en.ordinal(3), '3rd');
      expect(en.ordinal(4), '4th');
      expect(en.ordinal(11), '11th');
      expect(en.ordinal(12), '12th');
      expect(en.ordinal(13), '13th');
      expect(en.ordinal(21), '21st');
      expect(en.ordinal(112), '112th');
    });

    test(
      'la fecha de APA: el día antes del mes en español, después en inglés',
      () {
        expect(es.apaDate(2019), '2019');
        expect(es.apaDate(2019, month: 3), '2019, marzo');
        expect(es.apaDate(2019, month: 3, day: 15), '2019, 15 de marzo');
        expect(en.apaDate(2019, month: 3), '2019, March');
        expect(en.apaDate(2019, month: 3, day: 15), '2019, March 15');
      },
    );

    test('la fecha de APA con la letra del año', () {
      expect(en.apaDate(2019, suffix: 'a'), '2019a');
      expect(es.apaDate(2019, month: 3, suffix: 'b'), '2019b, marzo');
      expect(
        en.apaDate(2019, month: 3, day: 15, suffix: 'a'),
        '2019a, March 15',
      );
      expect(
        es.apaDate(2019, month: 3, day: 15, suffix: 'c'),
        '2019c, 15 de marzo',
      );
    });

    test('cómo se titula la lista de obras', () {
      expect(es.referencesTitle, 'Referencias');
      expect(es.worksCitedTitle, 'Obras citadas');
      expect(es.bibliographyTitle, 'Bibliografía');
      expect(en.referencesTitle, 'References');
      expect(en.worksCitedTitle, 'Works Cited');
      expect(en.bibliographyTitle, 'Bibliography');
    });

    test('la fecha larga y la de consulta', () {
      final date = DateTime(2026, 9, 5);

      expect(es.longDate(es, date), '5 de septiembre de 2026');
      expect(en.longDate(en, date), 'September 5, 2026');
      expect(
        es.retrieved(es, date, 'https://x.org'),
        'Recuperado el 5 de septiembre de 2026, de https://x.org',
      );
      expect(
        en.retrieved(en, date, 'https://x.org'),
        'Retrieved September 5, 2026, from https://x.org',
      );
    });
  });

  group('el armador', () {
    CitationBuilder builder() => CitationBuilder(es);

    test('el punto cierra un elemento, y no se repite', () {
      final b = builder()
        ..plain('García Márquez, G.')
        ..period();

      expect(b.build().toPlainText(), 'García Márquez, G.');
    });

    test('un elemento que termina en ? o ! no lleva otro punto', () {
      final question = builder()
        ..italic('¿Quién?')
        ..period();
      final exclamation = builder()
        ..plain('¡Basta!')
        ..period();

      expect(question.build().toPlainText(), '¿Quién?');
      expect(exclamation.build().toPlainText(), '¡Basta!');
    });

    test('cierra un paréntesis o un hueco con punto', () {
      final closed = builder()
        ..plain('(Ed.)')
        ..period();
      final gapped = builder()
        ..gap(CitationGap.author)
        ..period();

      expect(closed.build().toPlainText(), '(Ed.).');
      expect(gapped.build().toPlainText(), '[falta: autor].');
    });

    test('el punto de una cursiva queda fuera de ella', () {
      final b = builder()
        ..italic('Cien años de soledad')
        ..period();

      expect(b.build().runs, const [
        ItalicRun('Cien años de soledad'),
        PlainRun('.'),
      ]);
    });

    test('sin nada escrito no agrega ni punto ni espacio ni coma', () {
      final b = builder()
        ..period()
        ..space()
        ..comma();

      expect(b.isEmpty, isTrue);
      expect(b.build().isEmpty, isTrue);
    });

    test('el espacio no se duplica', () {
      final b = builder()
        ..plain('a ')
        ..space()
        ..plain('b');

      expect(b.build().toPlainText(), 'a b');
    });

    test('la coma no se duplica', () {
      final b = builder()
        ..plain('a,')
        ..comma()
        ..plain(' b');

      expect(b.build().toPlainText(), 'a, b');
    });

    test('los espacios de los bordes de una cursiva quedan afuera', () {
      final b = builder()..italic('  título  ');

      expect(b.build().runs, const [
        PlainRun('  '),
        ItalicRun('título'),
        PlainRun('  '),
      ]);
    });

    test('una cursiva de solo espacios no se escribe', () {
      final b = builder()..italic('   ');

      expect(b.isEmpty, isTrue);
    });

    test('entre comillas, con la puntuación adentro en inglés', () {
      final period = CitationBuilder(en)
        ..quoted('Random patterns', punctuation: '.');
      final comma = CitationBuilder(en)
        ..quoted('Random patterns', punctuation: ',');

      expect(period.build().toPlainText(), '“Random patterns.”');
      expect(comma.build().toPlainText(), '“Random patterns,”');
    });

    test('entre comillas, con la puntuación afuera en español', () {
      final period = builder()..quoted('Un título', punctuation: '.');
      final comma = builder()..quoted('Un título', punctuation: ',');

      expect(period.build().toPlainText(), '«Un título».');
      expect(comma.build().toPlainText(), '«Un título»,');
    });

    test('un título que ya termina en signo no lleva otro', () {
      for (final mark in ['.', '?', '!']) {
        final english = CitationBuilder(en)
          ..quoted('Why$mark', punctuation: ',');
        final spanish = builder()..quoted('Por qué$mark', punctuation: '.');

        expect(english.build().toPlainText(), '“Why$mark”');
        expect(spanish.build().toPlainText(), '«Por qué$mark»');
      }
    });

    test('sin puntuación, solo las comillas; sin texto, nada', () {
      final quoted = builder()..quoted('  Un título  ');
      final empty = builder()..quoted('   ');

      expect(quoted.build().toPlainText(), '«Un título»');
      expect(empty.isEmpty, isTrue);
    });

    test('el título de una obra: en cursiva o entre comillas, o el hueco', () {
      final italic = CitationBuilder(en)
        ..title('Swing Time', inQuotes: false, punctuation: '.');
      final quoted = CitationBuilder(en)
        ..title('Seeing Red', inQuotes: true, punctuation: ',');
      final empty = CitationBuilder(en)
        ..title('  ', inQuotes: false, punctuation: '.');
      final emptyQuoted = CitationBuilder(en)
        ..title('', inQuotes: true, punctuation: '.');

      expect(italic.build().runs, const [
        ItalicRun('Swing Time'),
        PlainRun('.'),
      ]);
      expect(quoted.build().toPlainText(), '“Seeing Red,”');
      expect(empty.build().toPlainText(), '[missing: title].');
      expect(emptyQuoted.build().gaps, [CitationGap.title]);
    });

    test('el título no repite un signo que ya tiene', () {
      final question = CitationBuilder(en)
        ..title('Who?', inQuotes: false, punctuation: '.');
      final period = CitationBuilder(en)
        ..title('Vol. 2.', inQuotes: false, punctuation: '.');

      expect(question.build().toPlainText(), 'Who?');
      expect(period.build().toPlainText(), 'Vol. 2.');
    });

    test('sin puntuación, el título queda como está', () {
      final b = CitationBuilder(en)..title('Swing Time', inQuotes: false);

      expect(b.build().runs, const [ItalicRun('Swing Time')]);
    });

    test('el tipo de obra que falta va antes de la puntuación', () {
      final b = CitationBuilder(en)
        ..title('Un título', inQuotes: false, punctuation: '.', markType: true);

      expect(b.build().toPlainText(), 'Un título [missing: type of work].');
      expect(b.build().gaps, [CitationGap.type]);
    });

    test('lo entrecomillado es texto sin formato', () {
      final quoted = builder()..quoted('Un título', punctuation: '.');

      expect(quoted.build().runs, const [PlainRun('«Un título».')]);
    });

    test('agrega otra cita entera', () {
      final other = Citation(const [ItalicRun('x')]);
      final b = builder()
        ..plain('a ')
        ..append(other);

      expect(b.build().runs, const [PlainRun('a '), ItalicRun('x')]);
    });
  });

  group('quién va de autor', () {
    const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');
    const rabassa = PersonName(family: 'Rabassa', given: 'Gregory');

    CitationSource source(
      List<Contributor> people, {
      ReferenceType? type,
      String? authorName,
    }) => CitationSource(
      title: 'T',
      reference: ReferenceData(type: type, contributors: people),
      authorName: authorName,
    );

    test('las autoras, en su orden', () {
      final lead = leadPeopleOf(
        source([
          const Contributor(name: garcia),
          const Contributor(name: rabassa, role: ContributorRole.translator),
        ]),
      );

      expect(lead.names, [garcia]);
      expect(lead.role, ContributorRole.author);
    });

    test('un documental se cita por su director', () {
      final lead = leadPeopleOf(
        source([
          const Contributor(name: garcia),
          const Contributor(name: rabassa, role: ContributorRole.director),
        ], type: ReferenceType.documentary),
      );

      expect(lead.names, [rabassa]);
      expect(lead.role, ContributorRole.director);
    });

    test('sin autores, los editores', () {
      final lead = leadPeopleOf(
        source([const Contributor(name: garcia, role: ContributorRole.editor)]),
      );

      expect(lead.names, [garcia]);
      expect(lead.role, ContributorRole.editor);
    });

    test('un capítulo no se cita por los editores del libro', () {
      final lead = leadPeopleOf(
        source([
          const Contributor(name: garcia, role: ContributorRole.editor),
        ], type: ReferenceType.chapter),
      );

      expect(lead.isEmpty, isTrue);
    });

    test('sin personas, el autor tal como se capturó, ENTERO', () {
      final lead = leadPeopleOf(
        source(const [], authorName: 'Kurzgesagt – In a Nutshell'),
      );

      expect(lead.names.single.family, 'Kurzgesagt – In a Nutshell');
      expect(lead.names.single.isInstitution, isTrue);
      expect(surnameInitials(lead.names.single), 'Kurzgesagt – In a Nutshell');
    });

    test('sin nada, vacío', () {
      expect(leadPeopleOf(source(const [])).isEmpty, isTrue);
      expect(leadPeopleOf(source(const [], authorName: '  ')).isEmpty, isTrue);
    });
  });

  group('los nombres', () {
    test('apellido e iniciales', () {
      expect(
        surnameInitials(
          const PersonName(family: 'García Márquez', given: 'Gabriel José'),
        ),
        'García Márquez, G. J.',
      );
      expect(
        surnameInitials(
          const PersonName(
            family: 'King',
            given: 'Martin Luther',
            suffix: 'Jr.',
          ),
        ),
        'King, M. L., Jr.',
      );
    });

    test('una institución o un nombre de una palabra va entero', () {
      expect(
        surnameInitials(
          const PersonName.institution('Organización Mundial de la Salud'),
        ),
        'Organización Mundial de la Salud',
      );
      expect(surnameInitials(const PersonName(family: 'Platón')), 'Platón');
    });

    test('iniciales y apellido', () {
      expect(
        initialsSurname(const PersonName(family: 'Subotnik', given: 'Rena F.')),
        'R. F. Subotnik',
      );
      expect(initialsSurname(const PersonName(family: 'Platón')), 'Platón');
    });
  });

  group('unir una lista de nombres', () {
    const names = ['A, A.', 'B, B.', 'C, C.'];

    test('en español, sin coma antes de «y»', () {
      expect(joinList(['A, A.'], es, joiner: 'y'), 'A, A.');
      expect(
        joinList(names.take(2).toList(), es, joiner: 'y'),
        'A, A. y B, B.',
      );
      expect(joinList(names, es, joiner: 'y'), 'A, A., B, B. y C, C.');
    });

    test('en inglés, con coma antes de «&», también con dos', () {
      expect(
        joinList(names.take(2).toList(), en, joiner: '&'),
        'A, A., & B, B.',
      );
      expect(joinList(names, en, joiner: '&'), 'A, A., B, B., & C, C.');
    });

    test('vacía es vacía', () {
      expect(joinList(const [], es, joiner: 'y'), isEmpty);
    });

    test('sin coma para dos —IEEE—, con coma desde tres', () {
      expect(
        joinList(
          names.take(2).toList(),
          en,
          joiner: 'and',
          commaForPair: false,
        ),
        'A, A. and B, B.',
      );
      expect(
        joinList(names, en, joiner: 'and', commaForPair: false),
        'A, A., B, B., and C, C.',
      );
    });
  });

  group('«y» o «e»', () {
    test('«e» delante de un nombre que suena a «i»', () {
      expect(conjunctionBefore('y', 'Iglesias, M.'), 'e');
      expect(conjunctionBefore('y', 'Ibáñez'), 'e');
      expect(conjunctionBefore('y', 'Íñiguez, J.'), 'e');
      expect(conjunctionBefore('y', 'Hidalgo'), 'e');
    });

    test('«y» si la «i» suena a consonante', () {
      expect(conjunctionBefore('y', 'Hierro'), 'y');
      expect(conjunctionBefore('y', 'Hiato'), 'y');
    });

    test('«y» delante de cualquier otra letra', () {
      expect(conjunctionBefore('y', 'García'), 'y');
      expect(conjunctionBefore('y', 'Yáñez'), 'y');
    });

    test('«y» delante de una inicial', () {
      expect(conjunctionBefore('y', 'I. Iglesias'), 'y');
    });

    test('otra conjunción no cambia', () {
      expect(conjunctionBefore('&', 'Iglesias'), '&');
      expect(conjunctionBefore('and', 'Iglesias'), 'and');
    });

    test('se aplica al unir una lista', () {
      expect(
        joinList(['García, G.', 'Iglesias, M.'], es, joiner: 'y'),
        'García, G. e Iglesias, M.',
      );
    });
  });

  group('el nombre invertido', () {
    test('apellido y nombre entero, con el sufijo después de una coma', () {
      expect(
        invertedName(
          const PersonName(family: 'García Márquez', given: 'Gabriel José'),
        ),
        'García Márquez, Gabriel José',
      );
      expect(
        invertedName(
          const PersonName(
            family: 'King',
            given: 'Martin Luther',
            suffix: 'Jr.',
          ),
        ),
        'King, Martin Luther, Jr.',
      );
    });

    test('una institución o un nombre de una palabra va como está', () {
      expect(
        invertedName(const PersonName.institution('Organización Mundial')),
        'Organización Mundial',
      );
      expect(invertedName(const PersonName(family: 'Platón')), 'Platón');
    });
  });

  group('el título abreviado', () {
    test('lo que está antes de los dos puntos', () {
      expect(shortTitle('Seeing Red: Mao Fetishism'), 'Seeing Red');
    });

    test('cuatro palabras como mucho, sin dejar una colgando', () {
      expect(shortTitle('One Two Three Four Five'), 'One Two Three Four');
      expect(shortTitle('Carta a Luis de Santángel'), 'Carta a Luis');
      expect(shortTitle('Una historia de la lectura'), 'Una historia');
      expect(shortTitle('One Two Three'), 'One Two Three');
    });

    test('sin «A», «An» ni «The» del principio, si se pide', () {
      expect(shortTitle('The Great Gatsby', dropArticle: true), 'Great Gatsby');
      expect(shortTitle('An Essay', dropArticle: true), 'Essay');
      expect(shortTitle('The Great Gatsby'), 'The Great Gatsby');
      expect(shortTitle('The', dropArticle: true), 'The');
    });

    test('una coma que quedaría al final se quita', () {
      expect(
        shortTitle('Culture, Media, Language, Power'),
        'Culture, Media, Language, Power',
      );
      expect(shortTitle('Uno dos tres cuatro, cinco'), 'Uno dos tres cuatro');
    });
  });

  group('la obra de la web y la fecha de consulta', () {
    CitationSource web({
      String? url,
      SourceKind? kind,
      PublicationDate date = const PublicationDate.unknown(),
      DateTime? accessedAt,
      DateTime? capturedAt,
      String? doi,
    }) => CitationSource(
      title: 'T',
      reference: ReferenceData(accessedAt: accessedAt, doi: doi),
      date: date,
      url: url,
      kind: kind,
      capturedAt: capturedAt,
    );

    test(
      'una obra es de la web si es un video de plataforma o tiene dirección',
      () {
        expect(isOnlineWork(web(url: 'https://x.org')), isTrue);
        expect(isOnlineWork(web(kind: SourceKind.youtube)), isTrue);
        expect(isOnlineWork(web()), isFalse);
        expect(isOnlineWork(web(url: '')), isFalse);
      },
    );

    test(
      'la fecha de consulta: la cargada, o la de captura sin fecha publicada',
      () {
        final loaded = DateTime(2026, 3, 15);
        final captured = DateTime(2026, 9, 5);

        expect(
          accessDateOf(web(url: 'https://x.org', accessedAt: loaded)),
          loaded,
        );
        expect(
          accessDateOf(
            web(url: 'https://x.org', accessedAt: loaded, capturedAt: captured),
          ),
          loaded,
        );
        expect(
          accessDateOf(web(url: 'https://x.org', capturedAt: captured)),
          captured,
        );
        expect(
          accessDateOf(
            web(
              url: 'https://x.org',
              capturedAt: captured,
              date: const PublicationDate.undated(),
            ),
          ),
          captured,
        );
      },
    );

    test('con fecha de publicación, la de captura no cuenta', () {
      expect(
        accessDateOf(
          web(
            url: 'https://x.org',
            capturedAt: DateTime(2026, 9, 5),
            date: PublicationDate.ofYear(2020),
          ),
        ),
        isNull,
      );
    });

    test('sin dirección o con DOI no hay fecha de consulta', () {
      expect(accessDateOf(web(accessedAt: DateTime(2026, 3, 15))), isNull);
      expect(
        accessDateOf(
          web(
            url: 'https://x.org',
            doi: '10.1000/xyz',
            accessedAt: DateTime(2026, 3, 15),
          ),
        ),
        isNull,
      );
    });
  });

  group('los apellidos dentro del texto', () {
    const names = [
      PersonName(family: 'Salas', given: 'Julia'),
      PersonName(family: 'Iglesias', given: 'María'),
      PersonName(family: 'Ruiz', given: 'Carlos'),
    ];

    test('uno, dos con la conjunción, tres o más con «et al.»', () {
      expect(inTextSurnames([names[0]], en, joiner: '&'), 'Salas');
      expect(
        inTextSurnames([names[0], names[2]], en, joiner: '&'),
        'Salas & Ruiz',
      );
      expect(
        inTextSurnames([names[0], names[2]], es, joiner: 'y'),
        'Salas y Ruiz',
      );
      expect(inTextSurnames(names, en, joiner: '&'), 'Salas et al.');
    });

    test('«e» delante de un apellido que empieza con «i»', () {
      expect(
        inTextSurnames([names[0], names[1]], es, joiner: 'y'),
        'Salas e Iglesias',
      );
    });

    test('una institución va entera', () {
      expect(
        inTextSurnames(
          const [PersonName.institution('Organización Mundial de la Salud')],
          es,
          joiner: 'y',
        ),
        'Organización Mundial de la Salud',
      );
    });
  });

  group('la edición, las páginas y el pasaje', () {
    test('un número se vuelve ordinal; un texto que dice «ed.» se deja', () {
      expect(editionText('2', es), '2.ª ed.');
      expect(editionText('2', en), '2nd ed.');
      expect(editionText('Rev. ed.', en), 'Rev. ed.');
      expect(editionText('2nd edition', en), '2nd edition');
      expect(editionText('3.ª edición', es), '3.ª edición');
      expect(editionText('Revised', en), 'Revised ed.');
    });

    test('sin edición, nada', () {
      expect(editionText(null, en), isNull);
      expect(editionText('  ', en), isNull);
    });

    test('las páginas: «pp.» para un rango, «p.» para una', () {
      expect(pagesWithTerm('45-67', en), 'pp. 45–67');
      expect(pagesWithTerm('12', es), 'p. 12');
      expect(pagesWithTerm('12, 15', en), 'pp. 12, 15');
      expect(pagesWithTerm(null, en), isNull);
    });

    test('el pasaje: página, rango o instante sin abreviatura', () {
      expect(locatorWithTerm(const CitationLocator.page('12'), es), 'p. 12');
      expect(
        locatorWithTerm(const CitationLocator.page('12-14'), en),
        'pp. 12–14',
      );
      expect(
        locatorWithTerm(const CitationLocator.time('0:14:35'), en),
        '0:14:35',
      );
    });

    test('la primera letra en mayúscula, y el resto como está', () {
      expect(capitalized('translated by X'), 'Translated by X');
      expect(capitalized('vol. 2'), 'Vol. 2');
      expect(capitalized('2nd ed.'), '2nd ed.');
      expect(capitalized(''), isEmpty);
    });
  });

  group('las páginas', () {
    test('un rango de números lleva raya', () {
      expect(pageRange('45-67'), '45–67');
      expect(pageRange(' 45 - 67 '), '45–67');
      expect(pageRange('S12-S15'), 'S12–S15');
    });

    test('lo que no es un rango se deja', () {
      expect(pageRange('e1234'), 'e1234');
      expect(pageRange(' 12 '), '12');
      expect(pageRange('12, 15, 18'), '12, 15, 18');
    });

    test('cuándo son varias', () {
      expect(isPageSpan('45-67'), isTrue);
      expect(isPageSpan('45–67'), isTrue);
      expect(isPageSpan('12, 15'), isTrue);
      expect(isPageSpan('12'), isFalse);
    });
  });
}
