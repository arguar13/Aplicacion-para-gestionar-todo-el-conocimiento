import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';

/// Lo que cada pedazo resalta en pantalla: el texto entre sus posiciones.
List<String> _visible(String raw, List<ReadableSegment> segments) => [
  for (final segment in segments) raw.substring(segment.start, segment.end),
];

List<String> _spoken(List<ReadableSegment> segments) => [
  for (final segment in segments) segment.spoken,
];

void main() {
  group('buildReadableSegments (F25)', () {
    test('un pedazo por línea, con sus posiciones exactas en el texto', () {
      const raw = 'Hola mundo.\n\n  Segunda línea  \n\tTercera';

      final segments = buildReadableSegments(raw, sourceKey: 'texto');

      expect(_visible(raw, segments), [
        'Hola mundo.',
        'Segunda línea',
        'Tercera',
      ]);
      expect(segments.map((s) => (s.start, s.end)), [
        (0, 11),
        (15, 28),
        (32, 39),
      ]);
      expect(_spoken(segments), _visible(raw, segments));
      expect(segments.every((s) => s.sourceKey == 'texto'), isTrue);
    });

    test(r'un fin de línea "\r\n" no queda dentro del pedazo', () {
      const raw = 'Uno\r\nDos\r\n';

      final segments = buildReadableSegments(raw, sourceKey: 'k');

      expect(_visible(raw, segments), ['Uno', 'Dos']);
    });

    test('un texto vacío o de puros espacios no tiene nada que leer', () {
      expect(buildReadableSegments('', sourceKey: 'k'), isEmpty);
      expect(buildReadableSegments(' \n\n\t ', sourceKey: 'k'), isEmpty);
    });

    test('una línea larga se lee de a oraciones, en su lugar exacto', () {
      final sentences = [
        for (var i = 0; i < 12; i++) 'Esta es la oración número $i del texto.',
      ];
      final raw = 'Antes.\n${sentences.join(' ')}\nDespués.';

      final segments = buildReadableSegments(raw, sourceKey: 'k');

      expect(_visible(raw, segments), ['Antes.', ...sentences, 'Después.']);
      expect(_spoken(segments), ['Antes.', ...sentences, 'Después.']);
    });

    test('una línea corta con varias oraciones se lee entera', () {
      const raw = 'Una. Dos. Tres.';

      final segments = buildReadableSegments(raw, sourceKey: 'k');

      expect(_visible(raw, segments), [raw]);
    });

    test('una oración larguísima se corta en un espacio, sin partir '
        'palabras', () {
      final raw = List.filled(80, 'palabra').join(' ');

      final segments = buildReadableSegments(raw, sourceKey: 'k');

      expect(segments.length, greaterThan(1));
      for (final segment in segments) {
        final visible = raw.substring(segment.start, segment.end);
        expect(visible.length, lessThanOrEqualTo(280));
        expect(visible.split(' '), everyElement('palabra'));
        expect(segment.spoken, visible);
      }
      // Cubren la línea entera, en orden, sin huecos más que el espacio del
      // corte.
      expect(segments.first.start, 0);
      expect(segments.last.end, raw.length);
      for (var i = 1; i < segments.length; i++) {
        expect(segments[i].start, segments[i - 1].end + 1);
      }
    });

    group('transcripción', () {
      const raw = '[0:14] Hola a todos.\n[0:20]\n[1:02:07] Seguimos.';

      test('la marca de tiempo no se dice, pero sí se resalta con su '
          'renglón', () {
        final segments = buildReadableSegments(
          raw,
          sourceKey: 'k',
          transcript: true,
        );

        expect(_spoken(segments), ['Hola a todos.', 'Seguimos.']);
        expect(_visible(raw, segments), [
          '[0:14] Hola a todos.',
          '[1:02:07] Seguimos.',
        ]);
        expect(segments.last.start, raw.indexOf('[1:02:07]'));
      });

      test('sin `transcript`, la marca se dice como cualquier texto', () {
        final segments = buildReadableSegments(raw, sourceKey: 'k');

        expect(_spoken(segments).first, '[0:14] Hola a todos.');
        expect(segments, hasLength(3));
      });
    });

    group('markdown', () {
      List<String> spokenOf(String raw) =>
          _spoken(buildReadableSegments(raw, sourceKey: 'k', markdown: true));

      test('sin títulos, citas, viñetas ni números de lista', () {
        expect(
          spokenOf(
            '# Título\n'
            '## Subtítulo\n'
            '> Una cita\n'
            '> - Una lista en la cita\n'
            '- Viñeta\n'
            '* Otra\n'
            '1. Primer paso\n'
            '- [x] Tarea hecha',
          ),
          [
            'Título',
            'Subtítulo',
            'Una cita',
            'Una lista en la cita',
            'Viñeta',
            'Otra',
            'Primer paso',
            'Tarea hecha',
          ],
        );
      });

      test('sin las marcas de formato, y los enlaces por su texto', () {
        expect(
          spokenOf(
            '**Negrita**, __otra__, ~~tachado~~ y `código`\n'
            'Ver [el sitio](https://ejemplo.com/a_b) y [[Nota|el alias]] y '
            '[[Otra nota]]\n'
            '*cursiva* y _también_, pero 2 * 3 y nombre_de_archivo\n'
            'Con una imagen ![foto](a.png) y una nota[^1]',
          ),
          [
            'Negrita, otra, tachado y código',
            'Ver el sitio y el alias y Otra nota',
            'cursiva y también, pero 2 * 3 y nombre_de_archivo',
            'Con una imagen y una nota',
          ],
        );
      });

      test('una línea sin nada que decir no es un pedazo', () {
        const raw = 'Antes\n---\n* * *\n![solo una imagen](a.png)\n#\nDespués';

        final segments = buildReadableSegments(
          raw,
          sourceKey: 'k',
          markdown: true,
        );

        expect(_spoken(segments), ['Antes', 'Después']);
        expect(_visible(raw, segments), ['Antes', 'Después']);
      });

      test('una tabla se lee por celdas, sin la línea separadora', () {
        expect(spokenOf('| Nombre | Edad |\n|---|---|\n| Ana | 30 |'), [
          'Nombre, Edad',
          'Ana, 30',
        ]);
      });

      test('dentro de un bloque de código se lee tal cual, sin las cercas', () {
        expect(spokenOf('Antes\n```dart\n# no es título\n```\nDespués'), [
          'Antes',
          '# no es título',
          'Después',
        ]);
      });

      test('las posiciones siguen siendo las del texto con formato', () {
        const raw = 'Intro\n## **Título** grande';

        final segments = buildReadableSegments(
          raw,
          sourceKey: 'k',
          markdown: true,
        );

        expect(segments.last.spoken, 'Título grande');
        expect(
          raw.substring(segments.last.start, segments.last.end),
          '## **Título** grande',
        );
      });
    });

    test('un texto sin formato con solo símbolos tampoco se lee', () {
      expect(buildReadableSegments('---\n• • •\nHola', sourceKey: 'k'), [
        const ReadableSegment(
          sourceKey: 'k',
          start: 10,
          end: 14,
          spoken: 'Hola',
        ),
      ]);
    });
  });

  group('documentFrom (F25)', () {
    test('junta varios textos en orden, cada pedazo con el suyo', () {
      final document = documentFrom('chat:1', 'Chat', [
        (
          sourceKey: 'm1',
          text: 'Pregunta uno',
          markdown: false,
          transcript: false,
        ),
        (
          sourceKey: 'm2',
          text: '**Respuesta**\n\n- con lista',
          markdown: true,
          transcript: false,
        ),
        (
          sourceKey: 'm3',
          text: '[0:01] Dicho',
          markdown: false,
          transcript: true,
        ),
      ]);

      expect(document.id, 'chat:1');
      expect(document.title, 'Chat');
      expect(document.segments.map((s) => (s.sourceKey, s.start, s.end)), [
        ('m1', 0, 12),
        ('m2', 0, 13),
        ('m2', 15, 26),
        ('m3', 0, 12),
      ]);
      expect(document.segments.map((s) => s.spoken), [
        'Pregunta uno',
        'Respuesta',
        'con lista',
        'Dicho',
      ]);
    });

    test('sin partes con texto, el documento queda vacío', () {
      final document = documentFrom('x', 'X', [
        (sourceKey: 'a', text: '  ', markdown: true, transcript: false),
      ]);

      expect(document.isEmpty, isTrue);
    });
  });
}
