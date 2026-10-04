import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

void main() {
  group('tal cual, sin interpretar (F22)', () {
    test(
      'lo que parece marcado se ve como está, con las mismas posiciones',
      () {
        const raw = '# 3 cuotas de var_uno_dos y **no** es negrita';
        final rendered = RenderedMarkdown.plain(raw);

        expect(rendered.displayText, raw);
        expect(rendered.renderToRaw(10), 10);
        expect(rendered.rawToRender(10), 10);
        expect(rendered.renderToRaw(raw.length, isEnd: true), raw.length);
      },
    );

    test('vacío', () {
      expect(RenderedMarkdown.plain('').displayText, '');
    });
  });

  group('lo que no es énfasis se ve tal cual (F22)', () {
    test('un guion bajo adentro de una palabra', () {
      expect(
        RenderedMarkdown.parse('la variable var_uno_dos').displayText,
        'la variable var_uno_dos',
      );
    });

    test('asteriscos con espacios alrededor', () {
      expect(
        RenderedMarkdown.parse('2 * 3 * 4 = 24').displayText,
        '2 * 3 * 4 = 24',
      );
    });

    test('el énfasis de verdad sigue funcionando', () {
      expect(
        RenderedMarkdown.parse('una _idea_ y **otra** y *más*').displayText,
        'una idea y otra y más',
      );
    });
  });

  group('texto sin marcado', () {
    test('queda exactamente igual', () {
      final rendered = RenderedMarkdown.parse('Un párrafo cualquiera.');

      expect(rendered.displayText, 'Un párrafo cualquiera.');
    });
  });

  group('negrita y cursiva', () {
    test('**negrita** se ve sin los asteriscos', () {
      final rendered = RenderedMarkdown.parse('Hola **mundo** feliz');

      expect(rendered.displayText, 'Hola mundo feliz');
    });

    test('*cursiva* también pierde sus asteriscos', () {
      final rendered = RenderedMarkdown.parse('Un *énfasis* simple');

      expect(rendered.displayText, 'Un énfasis simple');
    });

    test('_cursiva_ con guion bajo funciona igual', () {
      final rendered = RenderedMarkdown.parse('Un _énfasis_ simple');

      expect(rendered.displayText, 'Un énfasis simple');
    });

    test('varias marcas en la misma línea, todas se resuelven', () {
      final rendered = RenderedMarkdown.parse('**Uno** y *dos* y _tres_');

      expect(rendered.displayText, 'Uno y dos y tres');
    });
  });

  group('títulos', () {
    test('# quita el numeral y el espacio', () {
      final rendered = RenderedMarkdown.parse('# Un título\nY el cuerpo');

      expect(rendered.displayText, 'Un título\nY el cuerpo');
    });

    test('##  y ### también, hasta tres niveles', () {
      expect(RenderedMarkdown.parse('## Subtítulo').displayText, 'Subtítulo');
      expect(
        RenderedMarkdown.parse('### Menor todavía').displayText,
        'Menor todavía',
      );
    });
  });

  group('viñetas', () {
    test('- y * se convierten en •, mismo largo que el original', () {
      final rendered = RenderedMarkdown.parse('- uno\n* dos');

      expect(rendered.displayText, '• uno\n• dos');
    });

    test('una lista numerada no se toca: ya se ve bien tal cual', () {
      final rendered = RenderedMarkdown.parse('1. primero\n2. segundo');

      expect(rendered.displayText, '1. primero\n2. segundo');
    });
  });

  group('citas', () {
    test('> se quita, dejando el texto de la cita', () {
      final rendered = RenderedMarkdown.parse('> lo que alguien dijo');

      expect(rendered.displayText, 'lo que alguien dijo');
    });
  });

  group('enlaces [[ ]]', () {
    test('pierde los corchetes dobles, queda solo el título', () {
      final rendered = RenderedMarkdown.parse(
        'Esto viene del [[Colonialismo Británico]] de la época.',
      );

      expect(
        rendered.displayText,
        'Esto viene del Colonialismo Británico de la época.',
      );
    });

    test('varios enlaces en la misma línea, todos se resuelven', () {
      final rendered = RenderedMarkdown.parse(
        '[[Uno]] y [[Dos]] están relacionados',
      );

      expect(rendered.displayText, 'Uno y Dos están relacionados');
    });

    test('no se confunde con énfasis: el asterisco no entra adentro', () {
      final rendered = RenderedMarkdown.parse('Ver [[Tema *importante*]]');

      // El contenido entre corchetes se toma tal cual, sin además
      // interpretar el `*` que tiene adentro como cursiva: un enlace es
      // una sola unidad, no una mezcla de marcados.
      expect(rendered.displayText, 'Ver Tema *importante*');
    });

    test('buildSpans arma un span tocable con el título completo, y '
        'tocarlo avisa con ese mismo título', () {
      final rendered = RenderedMarkdown.parse(
        'Ver [[Colonialismo Británico]] acá',
      );
      final theme = ThemeData.light();
      String? tapped;

      final span = rendered.buildSpans(
        theme,
        const [],
        onLinkTap: (title) => tapped = title,
      );

      final linkSpan = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.text == 'Colonialismo Británico',
      );
      (linkSpan.recognizer! as TapGestureRecognizer).onTap!();

      expect(tapped, 'Colonialismo Británico');
    });

    test('sin onLinkTap, el span no lleva ningún recognizer', () {
      final rendered = RenderedMarkdown.parse('Ver [[Algo]] acá');
      final theme = ThemeData.light();

      final span = rendered.buildSpans(theme, const []);

      final linkSpan = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.text == 'Algo',
      );
      expect(linkSpan.recognizer, isNull);
    });

    test('un resaltado que cae encima de un enlace no le hace perder el '
        'toque: la parte resaltada también avisa el título completo', () {
      const raw = 'Ver [[Colonialismo Británico]] acá';
      final rendered = RenderedMarkdown.parse(raw);
      final theme = ThemeData.light();
      String? tapped;

      // "Colonial" dentro del título, en el renderizado: empieza en 4
      // (después de "Ver ") y dura 8 caracteres.
      final span = rendered.buildSpans(theme, [
        (rendered.renderToRaw(4), rendered.renderToRaw(12)),
      ], onLinkTap: (title) => tapped = title);

      final highlighted = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.style?.backgroundColor != null,
      );
      (highlighted.recognizer! as TapGestureRecognizer).onTap!();

      expect(tapped, 'Colonialismo Británico');
    });
  });

  group('separador de páginas', () {
    test('una línea de guiones no se altera, solo cambia de estilo', () {
      final rendered = RenderedMarkdown.parse(
        'Página uno\n\n---\n\nPágina dos',
      );

      expect(rendered.displayText, 'Página uno\n\n---\n\nPágina dos');
    });
  });

  group('ida y vuelta de posiciones', () {
    test('una posición del texto renderizado vuelve al lugar correcto del '
        'crudo', () {
      // "Hola **mundo** feliz" -> "Hola mundo feliz": "mundo" empieza en 5
      // en el renderizado y en 8 en el crudo (después de "Hola **").
      const raw = 'Hola **mundo** feliz';
      final rendered = RenderedMarkdown.parse(raw);

      final rawStart = rendered.renderToRaw(5);
      final rawEnd = rendered.renderToRaw(10, isEnd: true);

      expect(raw.substring(rawStart, rawEnd), 'mundo');
    });

    test('una posición del contenido crudo llega al lugar correcto del '
        'renderizado', () {
      const raw = 'Hola **mundo** feliz';
      final rendered = RenderedMarkdown.parse(raw);

      // "mundo" en el crudo va de 7 a 12 (después de "Hola **").
      final renderStart = rendered.rawToRender(7);
      final renderEnd = rendered.rawToRender(12);

      expect(rendered.displayText.substring(renderStart, renderEnd), 'mundo');
    });

    test('un resaltado guardado sobre texto plano se traduce sin cambios '
        'cuando no hay marcado alrededor', () {
      const raw = 'Un párrafo sin ningún formato especial.';
      final rendered = RenderedMarkdown.parse(raw);

      expect(rendered.rawToRender(3), 3);
      expect(rendered.renderToRaw(3), 3);
    });
  });

  group('buildSpans', () {
    test('concatenar el texto de los spans reconstruye el texto '
        'renderizado', () {
      final rendered = RenderedMarkdown.parse(
        '# Título\n\nUn párrafo con **negrita** y una lista:\n'
        '- uno\n- dos\n\n> una cita\n\n---\n\nMás texto.',
      );

      final theme = ThemeData.light();
      final span = rendered.buildSpans(theme, const []);
      final joined = span.children!
          .map((s) => (s as TextSpan).text ?? '')
          .join();

      expect(joined, rendered.displayText);
    });

    test('un resaltado pinta exactamente el fragmento pedido, aunque '
        'incluya texto en negrita', () {
      const raw = 'Antes **negrita** después';
      final rendered = RenderedMarkdown.parse(raw);
      // "negrita" en el crudo: de 8 a 15 (después de "Antes **").
      final theme = ThemeData.light();

      final span = rendered.buildSpans(theme, [(8, 15)]);
      final highlighted = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.style?.backgroundColor != null,
      );

      expect(highlighted.text, 'negrita');
    });

    test('sin resaltados, no hay ningún span con fondo', () {
      final rendered = RenderedMarkdown.parse('Texto **con formato**');
      final theme = ThemeData.light();

      final span = rendered.buildSpans(theme, const []);

      final anyHighlighted = span.children!.cast<TextSpan>().any(
        (s) => s.style?.backgroundColor != null,
      );
      expect(anyHighlighted, isFalse);
    });
  });

  group('enlaces e imágenes de una página web (F30)', () {
    /// Que cada tramo visible sea el mismo pedazo del crudo: es lo que
    /// mantiene los resaltados en su lugar.
    void expectSlicesOfRaw(String raw) {
      final rendered = RenderedMarkdown.parse(raw);
      final display = rendered.displayText;
      for (var i = 0; i < display.length; i++) {
        final r = rendered.renderToRaw(i);
        expect(raw[r], display[i], reason: 'posición $i de "$display"');
        expect(rendered.rawToRender(r), i);
      }
    }

    test('la captura de Wikipedia: una imagen enlazada no deja nada crudo', () {
      const raw =
          '[![](https://upload.wikimedia.org/a/Coliseo.jpg)]'
          '(https://es.wikipedia.org/wiki/Archivo:Coliseo.jpg)\n\n'
          'El Coliseo es un anfiteatro.';
      final rendered = RenderedMarkdown.parse(raw);

      expect(rendered.displayText.trim(), 'El Coliseo es un anfiteatro.');
    });

    test('un enlace se lee como su texto', () {
      const raw =
          'Fundada por [Rómulo](https://es.wikipedia.org/wiki/R%C3%B3mulo) '
          'en el 753.';
      expect(
        RenderedMarkdown.parse(raw).displayText,
        'Fundada por Rómulo en el 753.',
      );
      expectSlicesOfRaw(raw);
    });

    test('una dirección entre <> o con paréntesis balanceados', () {
      expect(
        RenderedMarkdown.parse(
          'ver [Roma](<https://x.org/a b>) y '
          '[Foro](https://x.org/Foro_(Roma)).',
        ).displayText,
        'ver Roma y Foro.',
      );
    });

    test('la nota al pie de Wikipedia, [[1]](…), se ve como [1]', () {
      const raw =
          'Un dato.[[1]](https://es.wikipedia.org/wiki/Roma#cite_note-1)';
      expect(RenderedMarkdown.parse(raw).displayText, 'Un dato.[1]');
      expectSlicesOfRaw(raw);
    });

    test(
      'un [ suelto antes de un enlace no abre un [[Título]] (Wikipedia)',
      () {
        const raw =
            'César [[Tito](https://x.org/Tito), hijo], *el pueblo.* '
            '<sup>[[3]](#cite_note-3)</sup>';
        final rendered = RenderedMarkdown.parse(raw);

        expect(rendered.displayText, 'César [Tito, hijo], el pueblo. [3]');
        expectSlicesOfRaw(raw);
      },
    );

    test('una imagen se lee como su texto alternativo, en cursiva', () {
      const raw = 'Mirá ![El Coliseo de noche](https://x.org/c.jpg) acá.';
      final rendered = RenderedMarkdown.parse(raw);

      expect(rendered.displayText, 'Mirá El Coliseo de noche acá.');
      expectSlicesOfRaw(raw);
      final span = rendered.buildSpans(ThemeData.light(), const []);
      final alt = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.text == 'El Coliseo de noche',
      );
      expect(alt.style?.fontStyle, FontStyle.italic);
    });

    test('el enlace no es tocable como un [[Título]]', () {
      final span = RenderedMarkdown.parse(
        '[Rómulo](https://x.org/r)',
      ).buildSpans(ThemeData.light(), const [], onLinkTap: (_) {});

      expect(span.children!.cast<TextSpan>().single.recognizer, isNull);
    });

    test('el énfasis alrededor de un enlace se aplica a su texto', () {
      const raw = 'Ver **[el Foro](https://x.org/f)** hoy';
      expect(RenderedMarkdown.parse(raw).displayText, 'Ver el Foro hoy');
      expectSlicesOfRaw(raw);
    });

    test('el HTML en línea de htmlToMarkdown pierde sus etiquetas', () {
      const raw =
          '10<sup>6</sup> y H<sub>2</sub>O, '
          '<a href="https://x.org/[1">ver [1</a> y '
          '<img src="https://x.org/a.png" alt="un mapa">.';
      final rendered = RenderedMarkdown.parse(raw);

      expect(rendered.displayText, '106 y H2O, ver [1 y un mapa.');
      expectSlicesOfRaw(raw);
    });

    test('el código en línea se ve sin sus comillas y sin interpretar', () {
      const raw = 'Usá `a_*b*_c` o `` `x` ``.';
      expect(RenderedMarkdown.parse(raw).displayText, 'Usá a_*b*_c o `x`.');
      expectSlicesOfRaw(raw);
    });

    test('el separador * * * de htmlToMarkdown es un separador', () {
      final span = RenderedMarkdown.parse(
        'uno\n\n* * *\n\ndos',
      ).buildSpans(ThemeData.light(), const []);
      final rule = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.text == '* * *',
      );
      expect(rule.style?.letterSpacing, 2);
    });

    test('un resaltado sobre el texto de un enlace cae en su lugar', () {
      const raw = 'Ver [el Foro](https://x.org/f) hoy';
      final rendered = RenderedMarkdown.parse(raw);
      final start = rendered.renderToRaw(4);
      final end = rendered.renderToRaw(11, isEnd: true);

      expect(raw.substring(start, end), 'el Foro');
    });
  });

  group('excerpt (F30)', () {
    test('Markdown: el comienzo sin marcado, cortado con …', () {
      final raw =
          '[![](https://x.org/a.jpg)](https://x.org/b)\n\n'
          '# Roma\n\nFundada por [Rómulo](https://x.org/r). ${'Texto ' * 80}';
      final excerpt = RenderedMarkdown.excerpt(
        raw,
        markdown: true,
        maxChars: 40,
      );

      expect(excerpt, startsWith('Roma\n\nFundada por Rómulo. Texto'));
      expect(excerpt, endsWith('…'));
      expect(excerpt.length, 41);
    });

    test('sin Markdown, tal cual', () {
      expect(RenderedMarkdown.excerpt('a **b**', markdown: false), 'a **b**');
    });

    test('un libro entero no se lee entero', () {
      final raw = '${'Una línea de un libro largo.\n' * 200000}fin';
      final watch = Stopwatch()..start();
      final excerpt = RenderedMarkdown.excerpt(raw, markdown: true);
      watch.stop();

      expect(excerpt, startsWith('Una línea'));
      expect(watch.elapsedMilliseconds, lessThan(200));
    });
  });
}
