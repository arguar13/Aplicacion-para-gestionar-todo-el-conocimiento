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
}
