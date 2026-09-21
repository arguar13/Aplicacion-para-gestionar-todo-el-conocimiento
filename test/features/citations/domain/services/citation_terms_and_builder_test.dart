import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
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
    });

    test('el mes tiene su nombre', () {
      expect(es.monthName(1), 'enero');
      expect(es.monthName(9), 'septiembre');
      expect(en.monthName(12), 'December');
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
