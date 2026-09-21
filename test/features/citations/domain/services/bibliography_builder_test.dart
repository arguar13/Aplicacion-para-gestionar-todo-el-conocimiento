import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/chicago_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/ieee_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/mla9_style.dart';

/// La bibliografía de un conjunto de fuentes (F15): el orden de cada estilo,
/// la letra que distingue las obras del mismo autor y del mismo año, la
/// numeración de IEEE y los formatos de salida.
void main() {
  const apa = Apa7Style();
  const mla = Mla9Style();
  const ieee = IeeeStyle();
  const chicagoNotes = ChicagoStyle.notes();
  const chicagoAuthorDate = ChicagoStyle.authorDate();

  Contributor person(
    String family,
    String given, {
    ContributorRole role = ContributorRole.author,
  }) => Contributor(
    name: PersonName(family: family, given: given),
    role: role,
  );

  /// Un libro con [people], de [year] —`null` es una fecha desconocida— y
  /// título [title].
  BibliographySource book(
    String id, {
    List<Contributor> people = const [],
    int? year = 2019,
    String title = 'Un título',
    PublicationDate? date,
  }) => BibliographySource(
    itemId: id,
    source: CitationSource(
      title: title,
      reference: ReferenceData(
        type: ReferenceType.book,
        contributors: people,
        publisher: 'Editorial',
      ),
      date:
          date ??
          (year == null
              ? const PublicationDate.unknown()
              : PublicationDate.ofYear(year)),
    ),
  );

  List<String> order(Bibliography bibliography) => [
    for (final entry in bibliography.entries) entry.itemId,
  ];

  Bibliography build(
    List<BibliographySource> sources, {
    ReferenceStyle? style,
    CitationLanguage language = CitationLanguage.en,
  }) => buildBibliography(sources, style: style ?? apa, language: language);

  group('el orden', () {
    test('alfabético por apellido, sin distinguir mayúsculas ni acentos', () {
      final sources = [
        book('zuniga', people: [person('Zúñiga', 'Ana')]),
        book('garcia', people: [person('García', 'Ana')]),
        book('alvarez', people: [person('Álvarez', 'Ana')]),
        book('borges', people: [person('borges', 'Jorge')]),
      ];

      expect(order(build(sources)), ['alvarez', 'borges', 'garcia', 'zuniga']);
    });

    test('la «ñ» va entre la «n» y la «o», como en el alfabeto', () {
      final sources = [
        for (final family in ['Nuzman', 'Nuria', 'Nuño', 'Núñez', 'Nunes'])
          book(family, people: [person(family, 'Ana')]),
      ];

      expect(order(build(sources)), [
        'Nunes',
        'Núñez',
        'Nuño',
        'Nuria',
        'Nuzman',
      ]);
    });

    test('a igual apellido, por nombre', () {
      final sources = [
        book('luis', people: [person('García', 'Luis')]),
        book('ana', people: [person('García', 'Ana')]),
      ];

      expect(order(build(sources)), ['ana', 'luis']);
    });

    test('una obra con menos autores va antes que otra que empieza igual', () {
      final sources = [
        book('dos', people: [person('Smith', 'J.'), person('Jones', 'K.')]),
        book('uno', people: [person('Smith', 'J.')]),
        book('tres', people: [person('Smith', 'J.'), person('Adams', 'L.')]),
      ];

      expect(order(build(sources)), ['uno', 'tres', 'dos']);
    });

    test('un autor y un editor con el mismo nombre no se confunden', () {
      final sources = [
        book(
          'editor',
          people: [person('Franco', 'J.', role: ContributorRole.editor)],
        ),
        book('autor', people: [person('Franco', 'J.')]),
      ];
      final result = build(sources, style: mla);

      expect(order(result), ['autor', 'editor']);
    });

    test(
      'una obra sin autor va al final, por título y sin contar el artículo',
      () {
        final sources = [
          book('sin-b', title: 'Los vientos'),
          book('con', people: [person('Zapata', 'Ana')]),
          book('sin-a', title: 'La aurora'),
          book('sin-c', title: 'Un zorro'),
        ];

        expect(order(build(sources)), ['con', 'sin-a', 'sin-b', 'sin-c']);
      },
    );

    test('las obras de un mismo autor: por año en autor-fecha', () {
      final sources = [
        book('b', people: [person('García', 'Ana')], year: 2021, title: 'A'),
        book('a', people: [person('García', 'Ana')], year: 2015, title: 'Z'),
        book(
          'sin-fecha',
          people: [person('García', 'Ana')],
          date: const PublicationDate.undated(),
          title: 'M',
        ),
        book(
          'desconocido',
          people: [person('García', 'Ana')],
          year: null,
          title: 'B',
        ),
      ];

      for (final style in [apa, chicagoAuthorDate]) {
        expect(order(build(sources, style: style)), [
          'sin-fecha',
          'a',
          'b',
          'desconocido',
        ], reason: style.id);
      }
    });

    test('las obras de un mismo autor: por título en los demás estilos', () {
      final sources = [
        book('b', people: [person('García', 'Ana')], year: 2015, title: 'Beta'),
        book('a', people: [person('García', 'Ana')], year: 2021, title: 'Alfa'),
      ];

      for (final style in [mla, chicagoNotes, ieee]) {
        expect(order(build(sources, style: style)), [
          'a',
          'b',
        ], reason: style.id);
      }
    });

    test('dos obras iguales quedan siempre en el mismo orden', () {
      final sources = [
        book('y', people: [person('García', 'Ana')]),
        book('x', people: [person('García', 'Ana')]),
      ];

      expect(order(build(sources)), order(build(sources.reversed.toList())));
    });

    test('cada fuente entra una vez, aunque esté repetida', () {
      final sources = [
        book('a', people: [person('García', 'Ana')]),
        book('a', people: [person('García', 'Ana')]),
        book('b', people: [person('Pérez', 'Luis')]),
      ];

      expect(order(build(sources)), ['a', 'b']);
    });

    test('una lista vacía da una bibliografía vacía', () {
      final result = build(const []);

      expect(result.isEmpty, isTrue);
      expect(result.length, 0);
      expect(result.hasGaps, isFalse);
      expect(result.toPlainText(), isEmpty);
      expect(result.toMarkdown(), isEmpty);
      expect(result.title, 'References');
    });
  });

  group('la letra del año', () {
    Iterable<String?> suffixes(Bibliography bibliography) => [
      for (final entry in bibliography.entries) entry.yearSuffix,
    ];

    test(
      'dos obras del mismo autor y del mismo año: «a» y «b», por título',
      () {
        final sources = [
          book(
            'segunda',
            people: [person('García', 'Ana')],
            title: 'Zorros y otros',
          ),
          book('primera', people: [person('García', 'Ana')], title: 'Águilas'),
        ];
        final result = build(sources);

        expect(order(result), ['primera', 'segunda']);
        expect(suffixes(result), ['a', 'b']);
        expect(
          result.entries.first.citation.toPlainText(),
          contains('(2019a).'),
        );
        expect(
          result.entries.last.citation.toPlainText(),
          contains('(2019b).'),
        );
      },
    );

    test('también en Chicago autor-fecha, y con «n.d.» no', () {
      final sources = [
        book('b', people: [person('Smith', 'Zadie')], year: 2016, title: 'B'),
        book('a', people: [person('Smith', 'Zadie')], year: 2016, title: 'A'),
      ];
      final result = build(sources, style: chicagoAuthorDate);

      expect(suffixes(result), ['a', 'b']);
      expect(
        result.entries.first.citation.toPlainText(),
        startsWith('Smith, Zadie. 2016a. A.'),
      );
    });

    test('otro año, otros autores o un año desconocido: sin letra', () {
      final sources = [
        book('otro-anio', people: [person('García', 'Ana')], year: 2020),
        book('mismo', people: [person('García', 'Ana')]),
        book(
          'con-otro',
          people: [person('García', 'Ana'), person('Pérez', 'Luis')],
        ),
        book('sin-a', people: [person('Ruiz', 'Eva')], year: null),
        book(
          'sin-b',
          people: [person('Ruiz', 'Eva')],
          year: null,
          title: 'Dos',
        ),
        book(
          'nd-a',
          people: [person('Soto', 'Ana')],
          date: const PublicationDate.undated(),
        ),
        book(
          'nd-b',
          people: [person('Soto', 'Ana')],
          date: const PublicationDate.undated(),
          title: 'Dos',
        ),
      ];

      expect(suffixes(build(sources)), everyElement(isNull));
    });

    test('MLA, IEEE y Chicago notas no distinguen con letras', () {
      final sources = [
        book('b', people: [person('García', 'Ana')], title: 'B'),
        book('a', people: [person('García', 'Ana')], title: 'A'),
      ];

      for (final style in [mla, ieee, chicagoNotes]) {
        expect(
          suffixes(build(sources, style: style)),
          everyElement(isNull),
          reason: style.id,
        );
      }
    });

    test('pasadas veintiséis, «aa», «ab»', () {
      final sources = [
        for (var i = 0; i < 28; i++)
          book(
            'obra-${i.toString().padLeft(2, '0')}',
            people: [person('García', 'Ana')],
            title: 'Título ${i.toString().padLeft(2, '0')}',
          ),
      ];
      final letters = suffixes(build(sources)).toList();

      expect(letters.take(3), ['a', 'b', 'c']);
      expect(letters[25], 'z');
      expect(letters[26], 'aa');
      expect(letters[27], 'ab');
      expect(letters.toSet(), hasLength(28));
    });

    test('la cita en el texto lleva la misma letra que la entrada', () {
      final sources = [
        book('b', people: [person('Smith', 'Zadie')], title: 'B'),
        book('a', people: [person('Smith', 'Zadie')], title: 'A'),
      ];

      for (final (style, expected) in [
        (apa, ['(Smith, 2019a)', '(Smith, 2019b)']),
        (chicagoAuthorDate, ['(Smith 2019a)', '(Smith 2019b)']),
      ]) {
        final result = build(sources, style: style);

        expect(
          [
            for (final entry in result.entries)
              style
                  .format(
                    CitationForm.inText,
                    sources.firstWhere((s) => s.itemId == entry.itemId).source,
                    CitationContext(
                      language: CitationLanguage.en,
                      yearSuffix: entry.yearSuffix,
                    ),
                  )
                  .toPlainText(),
          ],
          expected,
          reason: style.id,
        );
      }
    });
  });

  group('la numeración de IEEE', () {
    test('cada entrada lleva su número, en el orden en que se muestra', () {
      final sources = [
        book('z', people: [person('Zapata', 'Ana')]),
        book('a', people: [person('Álvarez', 'Ana')]),
        book('m', people: [person('Mora', 'Ana')]),
      ];
      final result = build(sources, style: ieee);

      expect(order(result), ['a', 'm', 'z']);
      expect([for (final e in result.entries) e.number], [1, 2, 3]);
      expect([
        for (final e in result.entries) e.citation.toPlainText()[0],
      ], everyElement('['));
      expect(result.entries[1].citation.toPlainText(), startsWith('[2] '));
    });

    test('los otros estilos no numeran', () {
      final sources = [
        book('a', people: [person('García', 'Ana')]),
      ];

      for (final style in [apa, mla, chicagoNotes, chicagoAuthorDate]) {
        final result = build(sources, style: style);

        expect(result.entries.single.number, isNull, reason: style.id);
      }
    });
  });

  group('el título de la lista', () {
    test('según el estilo y el idioma', () {
      final sources = [
        book('a', people: [person('García', 'Ana')]),
      ];

      String title(ReferenceStyle style, CitationLanguage language) =>
          build(sources, style: style, language: language).title;

      expect(title(apa, CitationLanguage.es), 'Referencias');
      expect(title(apa, CitationLanguage.en), 'References');
      expect(title(mla, CitationLanguage.es), 'Obras citadas');
      expect(title(mla, CitationLanguage.en), 'Works Cited');
      expect(title(chicagoNotes, CitationLanguage.es), 'Bibliografía');
      expect(title(chicagoNotes, CitationLanguage.en), 'Bibliography');
      expect(title(chicagoAuthorDate, CitationLanguage.es), 'Referencias');
      expect(title(ieee, CitationLanguage.en), 'References');
    });

    test('lo dice la bibliografía, con su estilo y su idioma', () {
      final result = build(
        [
          book('a', people: [person('García', 'Ana')]),
        ],
        style: kReferenceStyles.byId('mla9'),
        language: CitationLanguage.es,
      );

      expect(result.styleId, 'mla9');
      expect(result.language, CitationLanguage.es);
      expect(result.title, 'Obras citadas');
    });
  });

  group('los formatos de salida', () {
    final sources = [
      book(
        'a',
        people: [person('Álvarez', 'Ana')],
        title: 'Cien años',
        year: 1967,
      ),
      book('b', people: [person('Borges', 'Jorge')], title: 'El Aleph'),
      book('c', year: null, title: 'Sin autor'),
    ];

    test('texto plano: una entrada por línea, sin formato', () {
      final result = build(sources, language: CitationLanguage.es);

      expect(
        result.toPlainText(),
        'Álvarez, A. (1967). Cien años. Editorial.\n'
        'Borges, J. (2019). El Aleph. Editorial.\n'
        '[falta: autor]. ([falta: año]). Sin autor. Editorial.',
      );
    });

    test('Markdown: un párrafo por entrada, con las cursivas', () {
      final result = build(sources, language: CitationLanguage.es);

      expect(
        result.toMarkdown(),
        'Álvarez, A. (1967). *Cien años*. Editorial.\n\n'
        'Borges, J. (2019). *El Aleph*. Editorial.\n\n'
        r'\[falta: autor\]. (\[falta: año\]). *Sin autor*. Editorial.',
      );
    });

    test('los huecos se cuentan', () {
      final result = build(sources);

      expect(result.length, 3);
      expect(result.hasGaps, isTrue);
      expect(result.entriesWithGaps, 1);
      expect(result.entries.last.citation.gaps, [
        CitationGap.author,
        CitationGap.year,
      ]);
    });

    test('una bibliografía completa no tiene huecos', () {
      final result = build(sources.take(2).toList());

      expect(result.hasGaps, isFalse);
      expect(result.entriesWithGaps, 0);
    });

    test('las entradas no se pueden cambiar desde afuera', () {
      final result = build(sources);

      expect(result.entries.removeLast, throwsUnsupportedError);
    });

    test('IEEE en Markdown escapa los corchetes de su número', () {
      final result = build(sources.take(1).toList(), style: ieee);

      expect(result.toMarkdown(), startsWith(r'\[1\] A. Álvarez, '));
      expect(result.toPlainText(), startsWith('[1] A. Álvarez, '));
    });
  });
}
