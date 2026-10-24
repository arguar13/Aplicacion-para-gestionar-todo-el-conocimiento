import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_alignment.dart';
import 'package:sinapsis/features/viewer/domain/services/archived_page_study.dart';

void main() {
  const colors = (
    summary: 0xFFC8F2C2,
    synthesis: 0xFFBDE6FF,
    keyword: 0xFFFFB3D9,
  );

  ({Document page, ArchivedPageAlignment alignment}) open(
    String body, {
    required String content,
  }) {
    final shown = showArchivedPage(
      '<html><head></head><body>$body</body></html>',
      study: (content: content, colors: colors),
    );
    return (page: html_parser.parse(shown.html), alignment: shown.alignment!);
  }

  StudyMark mark(String content, String text, StudyMarkKind kind) {
    final start = content.indexOf(text);
    return StudyMark(
      id: '${kind.name}-$start',
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + text.length,
    );
  }

  /// Lo que se le pide pintar a la página, como el texto de la página que
  /// queda en cada tramo.
  Map<String, List<String>> painted(
    ArchivedPageAlignment alignment,
    List<StudyMark> marks,
  ) {
    final script = archivedPageStudyScript(alignment, marks);
    final layers =
        jsonDecode(RegExp(r'study\((.*)\);$').firstMatch(script)!.group(1)!)
            as Map<String, dynamic>;
    return {
      for (final MapEntry(:key, :value) in layers.entries)
        key: [
          for (final range in value as List<dynamic>)
            alignment.pageText.substring(
              (range as List<dynamic>)[0] as int,
              range[1] as int,
            ),
        ],
    };
  }

  group(
    'lo estudiado, pintado sobre la página mientras está abierta (F39)',
    () {
      test('una oración que cruza etiquetas y tiene las marcas del Markdown '
          'se pinta entera, con el punto; el menú no', () {
        const content = 'Intro.\n\nLa **revolución** industrial cambió todo.';
        final (:page, :alignment) = open(
          '<nav>Menú</nav><p>Intro.</p>'
          '<p>La <b>revolución</b> industrial cambió todo.</p>',
          content: content,
        );

        expect(
          painted(alignment, [
            mark(
              content,
              'La **revolución** industrial cambió todo.',
              StudyMarkKind.summary,
            ),
          ]),
          {
            'summary': ['La revolución industrial cambió todo.'],
            'synthesis': <String>[],
            'keyword': <String>[],
          },
        );
      });

      test('cada capa en lo suyo: una oración del resumen y de la síntesis va '
          'en las dos, y una palabra clave en cualquier oración, resaltada o '
          'no', () {
        const content = 'Una sola idea. Otra cosa distinta acá.';
        final (:page, :alignment) = open(
          '<p>Una sola idea. Otra cosa distinta acá.</p>',
          content: content,
        );

        expect(
          painted(alignment, [
            mark(content, 'Una sola idea.', StudyMarkKind.summary),
            mark(content, 'Una sola idea.', StudyMarkKind.synthesis),
            mark(content, 'idea', StudyMarkKind.keyword),
            mark(content, 'distinta', StudyMarkKind.keyword),
          ]),
          {
            'summary': ['Una sola idea.'],
            'synthesis': ['Una sola idea.'],
            'keyword': ['idea', 'distinta'],
          },
        );
      });

      test('la dirección de un enlace del Markdown no está en la página, y no '
          'impide pintar la oración', () {
        const content = 'Mirá [el sitio](https://x.org/a) hoy.';
        final (:page, :alignment) = open(
          '<p>Mirá <a href="https://x.org/a">el sitio</a> hoy.</p>',
          content: content,
        );

        expect(
          painted(alignment, [
            mark(content, content, StudyMarkKind.summary),
          ])['summary'],
          ['Mirá el sitio hoy.'],
        );
      });

      test('el texto repetido —el título arriba, en el menú— va donde está el '
          'artículo', () {
        const content =
            'Primero esto que es bastante largo. Después lo otro, que también.';
        final (:page, :alignment) = open(
          '<header>Después lo otro, que también.</header> '
          '<p>Primero esto que es bastante largo. Después lo otro, que '
          'también.</p>',
          content: content,
        );

        final script = archivedPageStudyScript(alignment, [
          mark(content, 'Después lo otro, que también.', StudyMarkKind.summary),
        ]);
        final layers =
            jsonDecode(RegExp(r'study\((.*)\);$').firstMatch(script)!.group(1)!)
                as Map<String, dynamic>;
        final range =
            (layers['summary'] as List<dynamic>).single as List<dynamic>;
        final start = range[0] as int;
        expect(start, greaterThan(alignment.pageText.indexOf('Primero')));
      });

      test('una nota al pie en medio de la oración la parte en dos: se pinta '
          'a cada lado, y la nota no', () {
        const content = 'La revolución industrial cambió todo el mundo.';
        final (:page, :alignment) = open(
          '<p>La revolución industrial<sup>[12]</sup> cambió todo el '
          'mundo.</p>',
          content: content,
        );

        expect(
          painted(alignment, [
            mark(content, content, StudyMarkKind.summary),
          ])['summary'],
          ['La revolución industrial', 'cambió todo el mundo.'],
        );
      });

      test('una que la página no tiene no se pinta, y las demás sí', () {
        const content =
            'Una frase ausente sobre volcanes islandeses activos.\n\n'
            'Otra frase presente acerca de mariposas tropicales.';
        final (:page, :alignment) = open(
          '<p>Otra frase presente acerca de mariposas tropicales.</p>',
          content: content,
        );

        expect(
          painted(alignment, [
            mark(
              content,
              'Una frase ausente sobre volcanes islandeses activos.',
              StudyMarkKind.summary,
            ),
            mark(
              content,
              'Otra frase presente acerca de mariposas tropicales.',
              StudyMarkKind.summary,
            ),
          ])['summary'],
          ['Otra frase presente acerca de mariposas tropicales.'],
        );
      });

      test('la copia no lleva nada pintado adentro: se ve como el original, '
          'sin un <mark> por palabra', () {
        const content = 'La revolución industrial.';
        final (:page, :alignment) = open(
          '<p>La revolución industrial.</p>',
          content: content,
        );

        expect(page.querySelectorAll('mark'), isEmpty);
        expect(page.querySelector('p')!.text, 'La revolución industrial.');
      });
    },
  );

  group('tocar la página, eligiendo a mano (F39)', () {
    const content = 'Intro.\n\nLa **revolución** industrial cambió todo.';
    final (:page, :alignment) = open(
      '<nav>Menú</nav><p>Intro.</p>'
      '<p>La <b>revolución</b> industrial cambió todo.</p>',
      content: content,
    );
    int at(String text) => alignment.pageText.indexOf(text);

    test('cualquier palabra lleva a su lugar en el texto extraído, esté o no '
        'en una oración resaltada', () {
      expect(
        archivedPageTappedOffset(alignment, '${at('revolución') + 2}'),
        content.indexOf('revolución') + 2,
      );
      expect(
        archivedPageTappedOffset(alignment, '${at('cambió')}'),
        content.indexOf('cambió'),
      );
    });

    test('justo después de la última letra de una palabra, es esa palabra', () {
      expect(
        archivedPageTappedOffset(alignment, '${at(' industrial')}'),
        content.indexOf('revolución') + 'revolución'.length - 1,
      );
    });

    test('lo que no es del artículo —el menú—, lo que no está junto a una '
        'letra —pasando el punto final— o no se entiende no lleva a nada', () {
      expect(archivedPageTappedOffset(alignment, '${at('Menú')}'), isNull);
      expect(
        archivedPageTappedOffset(alignment, '${at('todo.') + 'todo.'.length}'),
        isNull,
      );
      expect(archivedPageTappedOffset(alignment, 'hola'), isNull);
    });
  });

  group('la página se ve como hasta ahora, con un solo programa: el de la '
      'app', () {
    final (:page, :alignment) = open(
      '<script>alert(1)</script> '
      '<noscript><img src="foto.jpg"></noscript> '
      '<a href="javascript:void(0)" onclick="robar()">enlace</a> '
      '<p>Hola.</p>',
      content: 'Hola.',
    );

    test('sin sus programas ni sus atributos on… ni enlaces javascript:', () {
      final scripts = page.querySelectorAll('script');
      expect(scripts.map((s) => s.id), ['sinapsis-study-script']);
      final link = page.querySelector('a')!;
      expect(link.attributes.containsKey('onclick'), isFalse);
      expect(link.attributes.containsKey('href'), isFalse);
    });

    test('lo de <noscript> queda a la vista', () {
      expect(page.querySelector('noscript'), isNull);
      expect(page.querySelector('img')?.attributes['src'], 'foto.jpg');
    });

    test('con los colores de resaltador en su hoja', () {
      final css = page.querySelector('#sinapsis-study')!.text;
      expect(css, contains('#c8f2c2'));
      expect(css, contains('#bde6ff'));
      expect(css, contains('#ffb3d9'));
    });
  });

  test('sin nada estudiado, solo se arreglan las fotos: los programas de la '
      'página no se tocan', () {
    final page = html_parser.parse(
      showableArchivedPage(
        '<html><body><script>x()</script>'
        '<img src="data:image/gif;base64,R0" data-src="real.jpg"></body></html>',
      ),
    );

    expect(page.querySelector('script')?.text, 'x()');
    expect(page.querySelector('img')?.attributes['src'], 'real.jpg');
    expect(page.querySelector('#sinapsis-study'), isNull);
  });

  test('lo que se le pide a la página: qué se prende —cada uno por su '
      'lado (F39)— y si tocar elige', () {
    Map<String, Object?> state(String script) =>
        jsonDecode(RegExp(r'set\((.*)\);$').firstMatch(script)!.group(1)!)
            as Map<String, Object?>;

    expect(
      state(
        archivedPageStateScript(
          summary: false,
          synthesis: true,
          keywords: true,
          picking: false,
        ),
      ),
      {'summary': false, 'synthesis': true, 'keywords': true, 'picking': false},
    );
    expect(
      state(
        archivedPageStateScript(
          summary: true,
          synthesis: true,
          keywords: false,
          picking: true,
        ),
      ),
      {'summary': true, 'synthesis': true, 'keywords': false, 'picking': true},
    );
  });
}
