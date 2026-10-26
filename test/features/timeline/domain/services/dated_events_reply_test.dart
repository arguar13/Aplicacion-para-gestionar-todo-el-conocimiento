import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_events_reply.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';

/// Leer lo que contesta el modelo, sin creerle nada que el texto no diga
/// (F40).
void main() {
  HistoricalDate year(int n, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: n,
        precision: DatePrecision.year,
        isBce: bce,
        isCirca: circa,
      );

  const darwin =
      'Charles Darwin fue un naturalista inglés. '
      'En 1859 publicó El origen de las especies. '
      'Murió en 1882 en Down House.';

  DatedTextPart partOf(String text, {bool markdown = false}) =>
      selectDatedParts(text, maxChars: 3000, markdown: markdown).single;

  /// Lee [reply] contra el pedido armado con [text].
  List<DatedEventDraft> read(
    String reply, {
    String text = darwin,
    bool markdown = false,
  }) => parseDatedEventsReply(reply, partOf(text, markdown: markdown));

  group('una línea buena', () {
    test('da el hecho con su cita ubicada en el texto entero', () {
      final drafts = read(
        'HECHO: 1859 | - | Publica El origen de las especies | '
        'En 1859 publicó El origen de las especies.',
      );

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.date, year(1859));
      expect(draft.endDate, isNull);
      expect(draft.title, 'Publica El origen de las especies');
      expect(draft.excerpt, 'En 1859 publicó El origen de las especies.');
      expect(draft.start, darwin.indexOf('En 1859'));
      expect(darwin.substring(draft.start, draft.end), draft.excerpt);
    });

    test('varios hechos, en el orden en que el modelo los dio', () {
      final drafts = read(
        'HECHO: 1882 | - | Muere Darwin | Murió en 1882 en Down House.\n'
        'HECHO: 1859 | - | Publica su libro | En 1859 publicó El origen',
      );
      expect(drafts.map((d) => d.date), [year(1882), year(1859)]);
    });

    test('con un fin en su campo', () {
      final drafts = read(
        'HECHO: 1914 | 1918 | Primera Guerra Mundial | '
        'La guerra duró de 1914 a 1918.',
        text: 'Hubo una guerra. La guerra duró de 1914 a 1918.',
      );
      expect(drafts.single.date, year(1914));
      expect(drafts.single.endDate, year(1918));
    });

    test('con el rango entero en el campo de la fecha', () {
      final drafts = read(
        'HECHO: 1914..1918 | - | Primera Guerra Mundial | '
        'La guerra duró de 1914 a 1918.',
        text: 'La guerra duró de 1914 a 1918.',
      );
      expect(drafts.single.date, year(1914));
      expect(drafts.single.endDate, year(1918));
    });

    test('el fin que viene de otra expresión de la cita', () {
      final drafts = read(
        'HECHO: 1914 | 1918 | La guerra | '
        'estalló en 1914 y terminó en 1918',
        text: 'La guerra: estalló en 1914 y terminó en 1918.',
      );
      expect(drafts.single.endDate, year(1918));
    });

    test('la precisión de la fecha es la que dice la cita', () {
      const text = 'Darwin nació el 12 de febrero de 1809 en Shrewsbury.';
      final day = read(
        'HECHO: 1809-02-12 | - | Nace Darwin | '
        'Darwin nació el 12 de febrero de 1809 en Shrewsbury.',
        text: text,
      );
      expect(day.single.date.precision, DatePrecision.day);
      expect(day.single.date.month, 2);
      expect(day.single.date.day, 12);
    });

    test('siglos, décadas y a.C.', () {
      expect(
        read(
          'HECHO: s. XIX | - | La era victoriana | '
          'Todo ocurrió en el siglo XIX.',
          text: 'Todo ocurrió en el siglo XIX.',
        ),
        hasLength(1),
      );
      expect(
        read(
          'HECHO: década 1920 | - | Los locos años | Fue la década de 1920.',
          text: 'Fue la década de 1920.',
        ).single.date.precision,
        DatePrecision.decade,
      );
      expect(
        read(
          'HECHO: 44 a.C. | - | Muere César | '
          'César murió en el 44 a.C. en Roma.',
          text: 'César murió en el 44 a.C. en Roma.',
        ).single.date,
        year(44, bce: true),
      );
    });

    test('«circa» en la fecha o en el texto no se cuenta como diferencia', () {
      const text = 'Se fundó hacia 1500 en el norte.';
      expect(
        read(
          'HECHO: c. 1500 | - | Fundación | Se fundó hacia 1500 en el norte.',
          text: text,
        ),
        hasLength(1),
      );
      expect(
        read(
          'HECHO: 1500 | - | Fundación | Se fundó hacia 1500 en el norte.',
          text: text,
        ),
        hasLength(1),
      );
      expect(
        read(
          'HECHO: c. 1500 | - | Fundación | Se fundó en 1500 en el norte.',
          text: 'Se fundó en 1500 en el norte.',
        ),
        hasLength(1),
      );
    });
  });

  group('cómo se lee la línea', () {
    const line = 'En 1859 publicó El origen de las especies.';
    String ok(String prefix) => '$prefix 1859 | - | Publica su libro | $line';

    test('el rótulo en minúscula, con viñeta, con número o con negrita', () {
      for (final reply in [
        ok('hecho:'),
        ok('Hecho:'),
        ok('HECHO :'),
        '- ${ok('HECHO:')}',
        '* ${ok('HECHO:')}',
        '• ${ok('HECHO:')}',
        '1. ${ok('HECHO:')}',
        '2) ${ok('HECHO:')}',
        '   ${ok('HECHO:')}',
        '**HECHO:** 1859 | - | Publica su libro | $line',
        '**HECHO**: 1859 | - | Publica su libro | $line',
        '__HECHO:__ 1859 | - | Publica su libro | $line',
        '${ok('HECHO:')}\r',
      ]) {
        expect(read(reply), hasLength(1), reason: reply);
      }
    });

    test('las líneas que no son un hecho se ignoran sin romper las demás', () {
      final drafts = read(
        'Acá van los hechos que encontré:\n'
        '\n'
        'HECHO: 1859 | - | Publica su libro | $line\n'
        'HECHO: basura\n'
        'otra cosa | con barras | pero | sin rótulo\n'
        'HECHO: 1882 | - | Muere Darwin | Murió en 1882 en Down House.\n'
        'Espero que sirva.',
      );
      expect(drafts.map((d) => d.date), [year(1859), year(1882)]);
    });

    test('una respuesta vacía o sin hechos no da nada', () {
      expect(read(''), isEmpty);
      expect(read('   \n  '), isEmpty);
      expect(read('No hay hechos fechados.'), isEmpty);
      expect(read('NINGUNO'), isEmpty);
    });

    test('una línea con menos de cuatro campos se descarta', () {
      expect(read('HECHO: 1859'), isEmpty);
      expect(read('HECHO: 1859 | - | Publica su libro'), isEmpty);
      expect(read('HECHO: 1859 | Publica su libro | $line'), isEmpty);
      expect(read('HECHO:'), isEmpty);
      expect(read('HECHO: | | |'), isEmpty);
    });

    test('la cita puede tener barras: es el resto de la línea', () {
      const text = 'Se dijo | en 1859 | que ocurrió.';
      final drafts = read(
        'HECHO: 1859 | - | Se dice | Se dijo | en 1859 | que ocurrió.',
        text: text,
      );
      expect(drafts.single.excerpt, text);
    });
  });

  group('el fin', () {
    const text = 'La guerra duró de 1914 a 1918 y dejó huellas.';
    const quote = 'La guerra duró de 1914 a 1918';
    String withEnd(String end) => 'HECHO: 1914 | $end | La guerra | $quote';

    test('«no hay fin» se escribe de varias maneras', () {
      for (final end in [
        '-',
        '--',
        '—',
        '–',
        '',
        'ninguno',
        'Ninguna',
        'no',
        'none',
        'N/A',
        'null',
      ]) {
        final drafts = read(withEnd(end), text: text);
        expect(drafts, hasLength(1), reason: '«$end»');
        expect(drafts.single.endDate, isNull, reason: '«$end»');
      }
    });

    test('un fin que no se lee descarta la línea', () {
      expect(read(withEnd('abc'), text: text), isEmpty);
      expect(read(withEnd('1918-13'), text: text), isEmpty);
      expect(read(withEnd('12 de noviembre'), text: text), isEmpty);
    });

    test(
      'un fin igual al inicio descarta la línea aunque el texto lo repita',
      () {
        const repeated = 'Fue en 1914 y otra vez en 1914, dicen.';
        expect(
          read(
            'HECHO: 1914 | 1914 | Algo | Fue en 1914 y otra vez en 1914',
            text: repeated,
          ),
          isEmpty,
        );
      },
    );

    test(
      'el rango en la fecha y además un fin del texto descarta la línea',
      () {
        const spread = 'De 1914 a 1918, y luego hasta 1920, hubo problemas.';
        expect(
          read(
            'HECHO: 1914..1918 | 1920 | Algo | '
            'De 1914 a 1918, y luego hasta 1920',
            text: spread,
          ),
          isEmpty,
        );
        expect(
          read(
            'HECHO: 1914 | 1920 | Algo | '
            'De 1914 a 1918, y luego hasta 1920',
            text: spread,
          ),
          hasLength(1),
        );
      },
    );

    test('un fin anterior o igual al inicio descarta la línea', () {
      expect(read(withEnd('1913'), text: text), isEmpty);
      expect(read(withEnd('1914'), text: text), isEmpty);
    });

    test('un fin que es a su vez un rango descarta la línea', () {
      expect(read(withEnd('1918..1920'), text: text), isEmpty);
    });

    test('el rango en la fecha y además un fin descarta la línea', () {
      expect(
        read('HECHO: 1914..1918 | 1920 | La guerra | $quote', text: text),
        isEmpty,
      );
    });

    test('un fin que el texto no dice descarta la línea', () {
      expect(
        read(
          'HECHO: 1914 | 1918 | La guerra | Estalló en 1914.',
          text: 'Estalló en 1914. Terminó en 1918.',
        ),
        isEmpty,
      );
    });

    test('el fin sin la expresión de inicio en la cita no vale', () {
      expect(
        read('HECHO: 1913 | 1918 | La guerra | $quote', text: text),
        isEmpty,
      );
    });
  });

  group('nada se inventa: la fecha', () {
    test('una fecha distinta de la que escribe la cita se descarta', () {
      expect(
        read('HECHO: 1860 | - | Publica su libro | En 1859 publicó El origen.'),
        isEmpty,
      );
      expect(
        read(
          'HECHO: 1859 | - | Publica su libro | Murió en 1882 en Down House.',
        ),
        isEmpty,
      );
    });

    test('una fecha con otra precisión que la del texto se descarta', () {
      const text = 'Darwin nació el 12 de febrero de 1809 en Shrewsbury.';
      const quote = 'Darwin nació el 12 de febrero de 1809';
      expect(read('HECHO: 1809 | - | Nace | $quote', text: text), isEmpty);
      expect(read('HECHO: 1809-02 | - | Nace | $quote', text: text), isEmpty);
      expect(
        read('HECHO: 1809-02-13 | - | Nace | $quote', text: text),
        isEmpty,
      );
      expect(
        read('HECHO: 1809-02-12 | - | Nace | $quote', text: text),
        hasLength(1),
      );
    });

    test('un siglo no se vuelve un año, ni un año un siglo', () {
      const text = 'Todo ocurrió en el siglo XIX.';
      expect(
        read(
          'HECHO: 1801 | - | Todo | Todo ocurrió en el siglo XIX.',
          text: text,
        ),
        isEmpty,
      );
      expect(
        read(
          'HECHO: s. XVIII | - | Todo | Todo ocurrió en el siglo XIX.',
          text: text,
        ),
        isEmpty,
      );
      expect(
        read(
          'HECHO: s. XIX | - | Todo | Todo ocurrió en el siglo XIX.',
          text: text,
        ),
        hasLength(1),
      );
    });

    test('la era también tiene que coincidir', () {
      const text = 'César murió en el 44 a.C. en Roma.';
      const quote = 'César murió en el 44 a.C. en Roma.';
      expect(
        read('HECHO: 44 d.C. | - | Muere César | $quote', text: text),
        isEmpty,
      );
      expect(
        read('HECHO: 44 a.C. | - | Muere César | $quote', text: text),
        hasLength(1),
      );
    });

    test('una fecha que no se puede leer se descarta', () {
      for (final date in [
        '12 de febrero de 1809',
        '1809-13-01',
        '1809-02-30',
        '-43',
        '0',
        'mil ochocientos',
        '',
        'XIX',
      ]) {
        expect(
          read('HECHO: $date | - | Algo | En 1859 publicó El origen.'),
          isEmpty,
          reason: '«$date»',
        );
      }
    });

    test('una cita sin fecha toma la del pasaje que la contiene', () {
      const text = 'Darwin zarpó en el Beagle. Fue en 1831 y duró cinco años.';
      const quote = 'Darwin zarpó en el Beagle.';
      expect(
        read('HECHO: 1831 | - | Zarpa el Beagle | $quote', text: text),
        hasLength(1),
      );
      expect(
        read('HECHO: 1832 | - | Zarpa el Beagle | $quote', text: text),
        isEmpty,
      );
    });

    test('con una fecha en la cita, no sirve la de otra parte del pasaje', () {
      const text = 'Darwin zarpó en 1831. En 1836 volvió a Inglaterra.';
      expect(
        read(
          'HECHO: 1831 | - | Vuelve | En 1836 volvió a Inglaterra.',
          text: text,
        ),
        isEmpty,
      );
    });

    test('dos fechas en la cita: vale cualquiera de las dos', () {
      const text = 'Nació en 1809 y murió en 1882 en su casa.';
      const quote = 'Nació en 1809 y murió en 1882';
      expect(read('HECHO: 1809 | - | Nace | $quote', text: text), hasLength(1));
      expect(
        read('HECHO: 1882 | - | Muere | $quote', text: text),
        hasLength(1),
      );
      expect(read('HECHO: 1850 | - | Otra | $quote', text: text), isEmpty);
    });
  });

  group('nada se inventa: la cita', () {
    test('una cita que no está en el texto se descarta', () {
      expect(
        read('HECHO: 1859 | - | Publica su libro | En 1859 escribió un libro.'),
        isEmpty,
      );
      expect(
        read(
          'HECHO: 1859 | - | Publica su libro | En 1859, publicó El origen.',
        ),
        isEmpty,
      );
      expect(
        read('HECHO: 1859 | - | Publica su libro | en 1859 publicó el origen'),
        isEmpty,
      );
    });

    test('las comillas que envuelven la cita se quitan', () {
      for (final quote in [
        '"En 1859 publicó El origen"',
        '«En 1859 publicó El origen»',
        '“En 1859 publicó El origen”',
        "'En 1859 publicó El origen'",
      ]) {
        final drafts = read('HECHO: 1859 | - | Publica su libro | $quote');
        expect(drafts, hasLength(1), reason: quote);
        expect(drafts.single.excerpt, 'En 1859 publicó El origen');
      }
    });

    test('los puntos suspensivos de los bordes se quitan', () {
      for (final quote in [
        '...En 1859 publicó El origen...',
        '… En 1859 publicó El origen …',
        '"...En 1859 publicó El origen..."',
      ]) {
        final drafts = read('HECHO: 1859 | - | Publica su libro | $quote');
        expect(drafts, hasLength(1), reason: quote);
        expect(drafts.single.excerpt, 'En 1859 publicó El origen');
      }
    });

    test('espacios y saltos de línea distintos en la cita no importan', () {
      const text = 'Darwin escribió\nque en 1859   publicó\nsu gran libro.';
      final drafts = read(
        'HECHO: 1859 | - | Publica | que en 1859 publicó su gran libro',
        text: text,
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.excerpt, 'que en 1859   publicó\nsu gran libro');
      expect(
        text.substring(drafts.single.start, drafts.single.end),
        drafts.single.excerpt,
      );
    });

    test('una cita demasiado corta no ubica nada', () {
      expect(read('HECHO: 1859 | - | Algo | 1859'), isEmpty);
      expect(read('HECHO: 1859 | - | Algo | En 1859'), hasLength(1));
      expect(read('HECHO: 1859 | - | Algo | en 18'), isEmpty);
      expect(read('HECHO: 1859 | - | Algo |    '), isEmpty);
      expect(read('HECHO: 1859 | - | Algo | ""'), isEmpty);
    });

    test('una cita de justo el mínimo de caracteres alcanza', () {
      expect(
        read(
          'HECHO: 1492 | - | Llega Colón | En 149',
          text: 'En 1492 llegó Colón.',
        ),
        hasLength(1),
      );
      expect(
        read(
          'HECHO: 1492 | - | Llega Colón | En 14',
          text: 'En 1492 llegó Colón.',
        ),
        isEmpty,
      );
    });

    test('la cita se busca en todos los pasajes, y da el lugar del texto', () {
      final text = [
        'Intro. Pasó en 1789 la toma de la Bastilla en París.',
        'Relleno ' * 40,
        'Intro. Pasó en 1815 la batalla de Waterloo en Bélgica.',
      ].join('\n\n');
      final part = partOf(text);
      expect(part.passages, hasLength(2));

      final drafts = parseDatedEventsReply(
        'HECHO: 1815 | - | Waterloo | Pasó en 1815 la batalla de Waterloo\n'
        'HECHO: 1789 | - | Bastilla | Pasó en 1789 la toma de la Bastilla',
        part,
      );

      expect(drafts, hasLength(2));
      expect(drafts[0].start, text.indexOf('Pasó en 1815'));
      expect(drafts[1].start, text.indexOf('Pasó en 1789'));
      for (final d in drafts) {
        expect(text.substring(d.start, d.end), d.excerpt);
      }
    });

    test('en un texto con Markdown, la cita sin las marcas se ubica igual', () {
      const text = 'Darwin **publicó** en **1859** su libro más célebre.';
      final drafts = read(
        'HECHO: 1859 | - | Publica | '
        'Darwin publicó en 1859 su libro más célebre',
        text: text,
        markdown: true,
      );
      expect(drafts, hasLength(1));
      expect(
        drafts.single.excerpt,
        'Darwin **publicó** en **1859** su libro más célebre',
      );
      expect(drafts.single.start, 0);
    });

    test('la marca de énfasis entre las palabras de la cita se salta', () {
      const text = 'Antes de todo, `en` _1859_ publicó el libro grande.';
      final drafts = read(
        'HECHO: 1859 | - | Publica | en 1859 publicó el libro grande',
        text: text,
        markdown: true,
      );
      expect(drafts.single.excerpt, 'en` _1859_ publicó el libro grande');
    });

    test('una cita con marcas que tampoco está sin ellas se descarta', () {
      const text = 'Darwin **publicó** en **1859** su libro más célebre.';
      expect(
        read(
          'HECHO: 1859 | - | Publica | Darwin dio a luz en 1859',
          text: text,
        ),
        isEmpty,
      );
    });
  });

  group('el título', () {
    String titled(String title) =>
        'HECHO: 1859 | - | $title | En 1859 publicó El origen';

    test('sin comillas, negritas ni punto final', () {
      for (final (raw, clean) in [
        ('"Publica su libro"', 'Publica su libro'),
        ('«Publica su libro»', 'Publica su libro'),
        ('**Publica su libro**', 'Publica su libro'),
        ('_Publica su libro_', 'Publica su libro'),
        ('  Publica   su\tlibro.  ', 'Publica su libro'),
        ('Publica su libro;', 'Publica su libro'),
        ('Publica su libro:', 'Publica su libro'),
        ('Publica su libro...', 'Publica su libro'),
      ]) {
        expect(read(titled(raw)).single.title, clean, reason: raw);
      }
    });

    test('un título vacío descarta la línea', () {
      expect(read(titled('')), isEmpty);
      expect(read(titled('   ')), isEmpty);
      expect(read(titled('""')), isEmpty);
      expect(read(titled('**')), isEmpty);
      expect(read(titled('.')), isEmpty);
    });

    test('hasta el largo máximo queda tal cual', () {
      const exact =
          'abcdefg abcdefg abcdefg abcdefg abcdefg abcdefg abcdefg '
          'abcdefg abcdefg abcdefgh';
      expect(exact.length, kMaxDatedEventTitleChars);
      expect(read(titled(exact)).single.title, exact);
    });

    test('uno más largo se corta en una palabra y termina en «…»', () {
      const long =
          'Publica un libro que cambió para siempre la biología '
          'moderna y la manera de entender la vida';
      expect(long.length, greaterThan(kMaxDatedEventTitleChars));
      final title = read(titled(long)).single.title;

      expect(title.length, lessThanOrEqualTo(kMaxDatedEventTitleChars));
      expect(title, endsWith('…'));
      // Corta en un espacio: lo que queda son palabras enteras.
      final body = title.substring(0, title.length - 1);
      expect(long, startsWith(body));
      expect(long[body.length], ' ');
    });

    test('al cortar no queda una coma ni un guion colgando', () {
      final long = '${'a' * 70}, ${'b' * 30}';
      final title = read(titled(long)).single.title;
      expect(title, '${'a' * 70}…');
    });

    test('una palabra larguísima se corta donde se pueda', () {
      final title = read(titled('x' * 200)).single.title;
      expect(title.length, kMaxDatedEventTitleChars);
      expect(title, '${'x' * (kMaxDatedEventTitleChars - 1)}…');
    });

    test('un espacio muy al principio no deja un título diminuto', () {
      final title = read(titled('ab ${'x' * 200}')).single.title;
      expect(title.length, kMaxDatedEventTitleChars);
    });
  });

  group('repetidos', () {
    const quote = 'En 1859 publicó El origen de las especies';
    const one = 'HECHO: 1859 | - | Publica su libro | $quote';

    test('la misma línea dos veces es un solo hecho', () {
      expect(read('$one\n$one'), hasLength(1));
    });

    test(
      'la misma fecha y la misma cita con otro título es el mismo hecho',
      () {
        final drafts = read(
          '$one\nHECHO: 1859 | - | Sale El origen de las especies | $quote',
        );
        expect(drafts, hasLength(1));
        expect(drafts.single.title, 'Publica su libro');
      },
    );

    test('la misma fecha con la cita de otro lugar son dos hechos', () {
      const text = 'En 1859 publicó su libro. Más adelante, en 1859 viajó.';
      final drafts = read(
        'HECHO: 1859 | - | Publica | En 1859 publicó su libro\n'
        'HECHO: 1859 | - | Viaja | en 1859 viajó',
        text: text,
      );
      expect(drafts, hasLength(2));
    });

    test(
      'la misma fecha con citas que empiezan o terminan igual son otros',
      () {
        const text = 'En 1859 publicó su libro más célebre.';
        // Empiezan en el mismo lugar y terminan en otro.
        expect(
          read(
            'HECHO: 1859 | - | Uno | En 1859 publicó\n'
            'HECHO: 1859 | - | Dos | En 1859 publicó su libro',
            text: text,
          ),
          hasLength(2),
        );
        // Empiezan en otro lugar y terminan en el mismo.
        expect(
          read(
            'HECHO: 1859 | - | Uno | En 1859 publicó su libro\n'
            'HECHO: 1859 | - | Dos | 1859 publicó su libro',
            text: text,
          ),
          hasLength(2),
        );
      },
    );

    test('otra fecha con la misma cita es otro hecho', () {
      const text = 'Nació en 1809 y murió en 1882 en su casa.';
      final drafts = read(
        'HECHO: 1809 | - | Nace | Nació en 1809 y murió en 1882\n'
        'HECHO: 1882 | - | Muere | Nació en 1809 y murió en 1882',
        text: text,
      );
      expect(drafts, hasLength(2));
    });

    test('el mismo inicio con y sin fin son dos hechos', () {
      const text = 'La guerra duró de 1914 a 1918 y dejó huellas.';
      const q = 'La guerra duró de 1914 a 1918';
      final drafts = read(
        'HECHO: 1914 | - | Estalla | $q\nHECHO: 1914 | 1918 | La guerra | $q',
        text: text,
      );
      expect(drafts, hasLength(2));
    });

    test('con otro fin son dos hechos', () {
      const text = 'De 1914 a 1918, y luego hasta 1920, hubo problemas.';
      final drafts = read(
        'HECHO: 1914 | 1918 | Uno | De 1914 a 1918, y luego hasta 1920\n'
        'HECHO: 1914 | 1920 | Otro | De 1914 a 1918, y luego hasta 1920',
        text: text,
      );
      expect(drafts, hasLength(2));
    });
  });

  group('el pedido', () {
    test('numera los pasajes y los pone cada uno en un renglón', () {
      final text = [
        'Intro.   Pasó en 1789\nla toma de la Bastilla.',
        'Relleno ' * 40,
        'Intro. Pasó en 1815 la batalla de Waterloo.',
      ].join('\n\n');
      final part = partOf(text);

      expect(
        buildDatedEventsPrompt(part),
        'Fragmentos del documento:\n'
        '[1] Intro. Pasó en 1789 la toma de la Bastilla.\n'
        '[2] Intro. Pasó en 1815 la batalla de Waterloo.',
      );
    });

    test('el tope de la respuesta crece con los pasajes y tiene límites', () {
      expect(datedEventsReplyTokens(1), 128);
      expect(datedEventsReplyTokens(5), 5 * 72 + 48);
      expect(datedEventsReplyTokens(7), 7 * 72 + 48);
      expect(datedEventsReplyTokens(40), 40 * 72 + 48);
      expect(datedEventsReplyTokens(1000), 4096);
      expect(datedEventsReplyTokens(5), lessThan(datedEventsReplyTokens(6)));
    });

    test('el mínimo y el máximo de la cita y el título son los pedidos', () {
      expect(kMaxDatedEventTitleChars, 80);
      expect(kMinDatedEventQuoteChars, 6);
    });
  });
}
