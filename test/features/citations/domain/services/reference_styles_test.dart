import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';

/// El registro de estilos y lo que todos cumplen (F15): agregar uno es una
/// clase y una línea, y desde ese momento tiene que portarse como los demás.
void main() {
  final styles = kReferenceStyles.styles;

  final source = CitationSource(
    title: 'Un título',
    reference: const ReferenceData(
      type: ReferenceType.book,
      contributors: [
        Contributor(
          name: PersonName(family: 'García', given: 'Ana'),
        ),
      ],
      publisher: 'Editorial',
    ),
    date: PublicationDate.ofYear(2019),
  );

  group('el registro', () {
    test('ofrece los estilos en orden: APA 7, MLA 9, Chicago e IEEE', () {
      expect(
        [for (final style in styles) style.id],
        ['apa7', 'mla9', 'chicago17nb', 'chicago17ad', 'ieee'],
      );
    });

    test('el predeterminado es el primero', () {
      expect(kReferenceStyles.defaultStyle.id, 'apa7');
    });

    test('cada estilo se encuentra por su identificador', () {
      for (final style in styles) {
        expect(kReferenceStyles.byId(style.id), same(style));
        expect(kReferenceStyles.resolve(style.id), same(style));
      }
      expect(kReferenceStyles.byId('otro'), isNull);
      expect(kReferenceStyles.resolve('otro').id, 'apa7');
      expect(kReferenceStyles.resolve(null).id, 'apa7');
    });

    test('los identificadores y los nombres no se repiten', () {
      expect({for (final s in styles) s.id}, hasLength(styles.length));
      expect({for (final s in styles) s.name}, hasLength(styles.length));
    });

    test('solo IEEE numera sus entradas', () {
      expect(
        [
          for (final s in styles)
            if (s.isNumbered) s.id,
        ],
        ['ieee'],
      );
    });
  });

  group('todo estilo', () {
    test('tiene su entrada de bibliografía', () {
      for (final style in styles) {
        expect(style.forms, contains(CitationForm.reference), reason: style.id);
      }
    });

    test('da una cita no vacía en cada forma que dice tener', () {
      for (final style in styles) {
        for (final language in CitationLanguage.values) {
          for (final form in style.forms) {
            final citation = style.format(
              form,
              source,
              CitationContext(language: language),
            );

            expect(
              citation.isEmpty,
              isFalse,
              reason: '${style.id} $form $language',
            );
          }
        }
      }
    });

    test('da la cita vacía en cada forma que no tiene', () {
      for (final style in styles) {
        for (final form in CitationForm.values) {
          if (style.forms.contains(form)) continue;

          expect(
            style.format(form, source, const CitationContext()).isEmpty,
            isTrue,
            reason: '${style.id} $form',
          );
        }
      }
    });

    test('la cita de una fuente completa no tiene huecos', () {
      for (final style in styles) {
        for (final form in style.forms) {
          expect(
            style.format(form, source, const CitationContext()).hasGaps,
            isFalse,
            reason: '${style.id} $form',
          );
        }
      }
    });

    test('lo mismo pedido dos veces da lo mismo: es una función pura', () {
      for (final style in styles) {
        for (final form in style.forms) {
          expect(
            style.format(form, source, const CitationContext()),
            style.format(form, source, const CitationContext()),
            reason: '${style.id} $form',
          );
        }
      }
    });
  });
}
