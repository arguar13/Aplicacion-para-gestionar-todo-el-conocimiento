import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
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

  group('capas de color para estudiar (F36)', () {
    const green = Color(0xFFC8F2C2);
    const pink = Color(0xFFFFB3D9);

    /// Cada tramo con su texto y su fondo, en orden.
    List<(String, Color?)> pieces(TextSpan span) => [
      for (final s in span.children!.cast<TextSpan>())
        (s.text!, s.style?.backgroundColor),
    ];

    test('una oración se pinta debajo de un resaltado y una palabra clave '
        'encima, sin perder ni repetir texto', () {
      const raw = 'Antes la revolución industrial empezó. Después.';
      final rendered = RenderedMarkdown.plain(raw);
      final theme = ThemeData.light();
      final sentence = (6, raw.indexOf(' Después'));
      final word = (raw.indexOf('revolución'), raw.indexOf(' industrial'));
      final highlight = (raw.indexOf('revolución'), raw.indexOf(' empezó'));

      final span = rendered.buildSpans(
        theme,
        [highlight],
        paints: [
          PaintedRange(
            word.$1,
            word.$2,
            background: pink,
            foreground: Colors.black87,
            bold: true,
            aboveHighlights: true,
          ),
          PaintedRange(sentence.$1, sentence.$2, background: green),
        ],
      );

      final tertiary = theme.colorScheme.tertiaryContainer;
      expect(pieces(span), [
        ('Antes ', null),
        ('la ', green),
        ('revolución', pink),
        (' industrial', tertiary),
        (' empezó.', green),
        (' Después.', null),
      ]);
      final keyword = span.children!.cast<TextSpan>().firstWhere(
        (s) => s.text == 'revolución',
      );
      expect(keyword.style!.fontWeight, FontWeight.bold);
      expect(keyword.style!.color, Colors.black87);
    });

    test('lo que suena va encima de todo', () {
      const raw = 'Una oración entera.';
      final rendered = RenderedMarkdown.plain(raw);

      final span = rendered.buildSpans(
        ThemeData.light(),
        const [],
        activeRange: (4, 11),
        paints: const [
          PaintedRange(0, 19, background: green),
          PaintedRange(4, 11, background: pink, aboveHighlights: true),
        ],
      );

      expect(pieces(span), [
        ('Una ', green),
        ('oración', RenderedMarkdown.playingColor),
        (' entera.', green),
      ]);
    });

    test('dos capas seguidas no se mezclan, y dos que se pisan dejan la de '
        'más arriba', () {
      const raw = 'Uno. Dos. Tres.';
      final rendered = RenderedMarkdown.plain(raw);

      final span = rendered.buildSpans(
        ThemeData.light(),
        const [],
        paints: const [
          PaintedRange(0, 4, background: green),
          PaintedRange(4, 9, background: green),
          PaintedRange(5, 15, background: pink),
        ],
      );

      expect(pieces(span), [
        ('Uno.', green),
        (' ', green),
        ('Dos.', pink),
        (' Tres.', pink),
      ]);
    });

    test('un resaltado que pisa a otro ya no se pierde: se ven los dos', () {
      const raw = 'abcdefghij';
      final rendered = RenderedMarkdown.plain(raw);
      final theme = ThemeData.light();

      final span = rendered.buildSpans(theme, const [(0, 5), (3, 8)]);

      final painted = [
        for (final (text, color) in pieces(span))
          if (color == theme.colorScheme.tertiaryContainer) text,
      ];
      expect(painted.join(), 'abcdefgh');
      expect(pieces(span).last, ('ij', null));
    });

    test('sobre Markdown, la capa cae en lo que se ve, con los mismos '
        'segmentos', () {
      const raw = 'Hola **mundo** feliz.';
      final rendered = RenderedMarkdown.parse(raw);

      final span = rendered.buildSpans(
        ThemeData.light(),
        const [],
        paints: const [PaintedRange(0, 21, background: green)],
      );

      expect(pieces(span), [
        ('Hola ', green),
        ('mundo', green),
        (' feliz.', green),
      ]);
      expect(
        span.children!.cast<TextSpan>()[1].style!.fontWeight,
        FontWeight.bold,
      );
    });

    test('una capa que termina justo donde empieza la negrita no deja '
        'tramos vacíos', () {
      final rendered = RenderedMarkdown.parse('Hola **mundo** feliz.');

      final span = rendered.buildSpans(
        ThemeData.light(),
        const [],
        paints: const [PaintedRange(0, 5, background: green)],
      );

      expect(pieces(span), [
        ('Hola ', green),
        ('mundo', null),
        (' feliz.', null),
      ]);
    });

    test('rawToRender da lo mismo que antes en cada posición, también dentro '
        'del marcado', () {
      const raw = '# Título\n\n- uno **dos** [tres](x) `cua`\n\n> cita';
      final rendered = RenderedMarkdown.parse(raw);
      final display = rendered.displayText;

      final positions = [
        for (var i = 0; i <= raw.length + 2; i++) rendered.rawToRender(i),
      ];

      // Nunca retrocede, nunca se sale, y lo que se ve en un tramo sin
      // marcado es el mismo carácter del crudo.
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThanOrEqualTo(positions[i - 1]));
      }
      expect(positions.last, display.length);
      final dos = raw.indexOf('dos');
      expect(display[rendered.rawToRender(dos)], 'd');
      expect(rendered.rawToRender(0), 0);
      expect(rendered.rawToRender(raw.indexOf('**')), display.indexOf('dos'));
    });
  });

  group('subrayados a mano, con su color y su estilo (F38)', () {
    const orange = Color(0xFFFFCC8A);
    const violet = Color(0xFFDCC8FF);
    const green = Color(0xFFC8F2C2);
    const pink = Color(0xFFFFB3D9);
    final theme = ThemeData.light();

    /// Cada tramo con su texto, su fondo, el color de su línea y la letra.
    List<(String, Color?, Color?, bool)> pieces(TextSpan span) => [
      for (final s in span.children!.cast<TextSpan>())
        (
          s.text!,
          s.style?.backgroundColor,
          s.style?.decoration == TextDecoration.underline
              ? s.style?.decorationColor
              : null,
          s.style?.fontWeight == FontWeight.bold,
        ),
    ];

    test('de fondo se pinta el fondo, y sin línea', () {
      final rendered = RenderedMarkdown.plain('uno dos tres');

      final span = rendered.buildSpans(
        theme,
        const [],
        marks: const [HandMark(4, 7, color: orange)],
      );

      expect(pieces(span), [
        ('uno ', null, null, false),
        ('dos', orange, null, false),
        (' tres', null, null, false),
      ]);
    });

    test('subrayado se pinta una línea gruesa del color, y sin fondo', () {
      final rendered = RenderedMarkdown.plain('uno dos tres');

      final span = rendered.buildSpans(
        theme,
        const [],
        marks: const [
          HandMark(4, 7, color: violet, style: HighlightStyle.underline),
        ],
      );

      expect(pieces(span), [
        ('uno ', null, null, false),
        ('dos', null, violet, false),
        (' tres', null, null, false),
      ]);
      final line = span.children!.cast<TextSpan>()[1].style!;
      expect(line.decorationThickness, greaterThanOrEqualTo(2));
    });

    test('de abajo hacia arriba: la oración, lo que subrayó la persona, la '
        'palabra clave', () {
      final rendered = RenderedMarkdown.plain('uno dos tres cuatro');

      final span = rendered.buildSpans(
        theme,
        const [],
        paints: const [
          PaintedRange(0, 19, background: green),
          PaintedRange(8, 12, background: pink, aboveHighlights: true),
        ],
        marks: const [HandMark(4, 14, color: orange)],
      );

      expect(pieces(span).map((p) => (p.$1, p.$2)), [
        ('uno ', green),
        ('dos ', orange),
        ('tres', pink),
        (' c', orange),
        ('uatro', green),
      ]);
    });

    test('la oración no tapa el subrayado, ni el subrayado a la oración: '
        'el fondo de arriba gana y la línea se suma', () {
      final rendered = RenderedMarkdown.plain('uno dos tres');

      final span = rendered.buildSpans(
        theme,
        const [],
        paints: const [PaintedRange(0, 12, background: green)],
        marks: const [
          HandMark(4, 7, color: violet, style: HighlightStyle.underline),
        ],
      );

      expect(pieces(span), [
        ('uno ', green, null, false),
        ('dos', green, violet, false),
        (' tres', green, null, false),
      ]);
    });

    test('lo que suena en voz alta va por encima de todo', () {
      final rendered = RenderedMarkdown.plain('uno dos tres');

      final span = rendered.buildSpans(
        theme,
        const [],
        marks: const [HandMark(0, 12, color: orange)],
        activeRange: (4, 7),
      );

      expect(pieces(span).map((p) => (p.$1, p.$2)), [
        ('uno ', orange),
        ('dos', RenderedMarkdown.playingColor),
        (' tres', orange),
      ]);
    });

    test('lo marcado un momento al saltar a un fragmento va encima de los '
        'subrayados', () {
      final rendered = RenderedMarkdown.plain('uno dos tres');

      final span = rendered.buildSpans(
        theme,
        const [(4, 7)],
        marks: const [HandMark(0, 12, color: orange)],
      );

      expect(pieces(span).map((p) => (p.$1, p.$2)), [
        ('uno ', orange),
        ('dos', theme.colorScheme.tertiaryContainer),
        (' tres', orange),
      ]);
    });

    test('sobre Markdown cae en lo que se ve, y no pisa la negrita', () {
      final rendered = RenderedMarkdown.parse('Hola **mundo** feliz.');

      final span = rendered.buildSpans(
        theme,
        const [],
        marks: const [HandMark(7, 12, color: orange)],
      );

      expect(pieces(span), [
        ('Hola ', null, null, false),
        ('mundo', orange, null, true),
        (' feliz.', null, null, false),
      ]);
    });

    group('la letra se lee también con un tema oscuro (F39)', () {
      final dark = ThemeData.dark();

      Color? letter(TextSpan span, String text) => span.children!
          .cast<TextSpan>()
          .firstWhere((s) => s.text == text)
          .style
          ?.color;

      test('un subrayado de fondo lleva letra oscura, como un resaltador '
          'sobre papel; uno de línea y el texto de al lado, la del tema', () {
        final rendered = RenderedMarkdown.plain('uno dos tres');

        final span = rendered.buildSpans(
          dark,
          const [],
          marks: const [
            HandMark(0, 3, color: orange),
            HandMark(4, 7, color: violet, style: HighlightStyle.underline),
          ],
        );

        expect(letter(span, 'uno'), Colors.black87);
        expect(letter(span, 'dos'), dark.colorScheme.onSurface);
        expect(letter(span, ' tres'), dark.colorScheme.onSurface);
      });

      test('una coincidencia (el `tertiaryContainer` del tema) lleva la letra '
          'que le va a ese fondo, también sobre un subrayado a mano', () {
        final rendered = RenderedMarkdown.plain('uno dos tres');

        final span = rendered.buildSpans(
          dark,
          [(0, 3), (4, 7)],
          marks: const [HandMark(4, 7, color: orange)],
        );

        expect(letter(span, 'uno'), dark.colorScheme.onTertiaryContainer);
        expect(letter(span, 'dos'), dark.colorScheme.onTertiaryContainer);
      });
    });
  });
}
