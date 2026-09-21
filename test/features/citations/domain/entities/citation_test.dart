import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';

/// Una cita ya armada (F15): corridas de texto, cursiva y huecos que salen como
/// texto plano o como Markdown.
void main() {
  const gap = GapRun(field: CitationGap.year, text: '[falta: año]');

  group('las corridas', () {
    test('las contiguas del mismo formato se juntan', () {
      final citation = Citation(const [
        PlainRun('García '),
        PlainRun('Márquez'),
        ItalicRun('Cien '),
        ItalicRun('años'),
      ]);

      expect(citation.runs, const [
        PlainRun('García Márquez'),
        ItalicRun('Cien años'),
      ]);
    });

    test('las vacías se descartan', () {
      final citation = Citation(const [
        PlainRun(''),
        ItalicRun('x'),
        PlainRun(''),
      ]);

      expect(citation.runs, const [ItalicRun('x')]);
    });

    test('una cursiva entre dos textos no se junta con ninguno', () {
      final citation = Citation(const [
        PlainRun('a'),
        ItalicRun('b'),
        PlainRun('c'),
      ]);

      expect(citation.runs, hasLength(3));
    });

    test('un hueco no se junta con el texto de al lado', () {
      final citation = Citation(const [PlainRun('('), gap, PlainRun(')')]);

      expect(citation.runs, hasLength(3));
    });

    test('las corridas no se pueden cambiar desde afuera', () {
      final citation = Citation(const [PlainRun('a')]);

      expect(
        () => citation.runs.add(const PlainRun('b')),
        throwsUnsupportedError,
      );
    });
  });

  group('texto plano', () {
    test('junta todo, sin marcas de cursiva', () {
      final citation = Citation(const [
        PlainRun('García Márquez, G. (1967). '),
        ItalicRun('Cien años de soledad'),
        PlainRun('. Sudamericana.'),
      ]);

      expect(
        citation.toPlainText(),
        'García Márquez, G. (1967). Cien años de soledad. Sudamericana.',
      );
    });

    test('escribe los huecos tal cual', () {
      final citation = Citation(const [PlainRun('('), gap, PlainRun(')')]);

      expect(citation.toPlainText(), '([falta: año])');
    });

    test('la cita vacía es vacía', () {
      expect(const Citation.empty().isEmpty, isTrue);
      expect(const Citation.empty().toPlainText(), isEmpty);
    });
  });

  group('Markdown', () {
    test('la cursiva va entre asteriscos', () {
      final citation = Citation(const [
        PlainRun('Autor. '),
        ItalicRun('Un título'),
        PlainRun('.'),
      ]);

      expect(citation.toMarkdown(), 'Autor. *Un título*.');
    });

    test('los huecos van con los corchetes escapados: no son un enlace', () {
      final citation = Citation(const [PlainRun('('), gap, PlainRun(')')]);

      expect(citation.toMarkdown(), r'(\[falta: año\])');
    });

    test('lo que el usuario escribió se escapa: un guion bajo no es una '
        'cursiva', () {
      final citation = Citation(const [
        ItalicRun('snake_case *y* [más]'),
        PlainRun(r' a\b `c`'),
      ]);

      expect(citation.toMarkdown(), r'*snake\_case \*y\* \[más\]* a\\b \`c\`');
    });
  });

  group('los huecos', () {
    test('se listan en el orden en que aparecen', () {
      final citation = Citation(const [
        GapRun(field: CitationGap.author, text: '[falta: autor]'),
        PlainRun(' '),
        gap,
      ]);

      expect(citation.gaps, [CitationGap.author, CitationGap.year]);
      expect(citation.hasGaps, isTrue);
    });

    test('una cita completa no tiene', () {
      final citation = Citation(const [PlainRun('todo')]);

      expect(citation.gaps, isEmpty);
      expect(citation.hasGaps, isFalse);
    });
  });

  group('igualdad', () {
    test(
      'dos citas que dicen lo mismo son iguales, aunque se armen distinto',
      () {
        final a = Citation(const [PlainRun('a'), PlainRun('b')]);
        final b = Citation(const [PlainRun('ab')]);

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('la cursiva y el hueco cuentan', () {
      expect(
        Citation(const [PlainRun('x')]),
        isNot(Citation(const [ItalicRun('x')])),
      );
      expect(
        Citation(const [gap]),
        isNot(Citation(const [PlainRun('[falta: año]')])),
      );
    });
  });
}
