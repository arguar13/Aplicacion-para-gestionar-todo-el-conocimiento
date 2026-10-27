import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';

/// Cuántos caracteres tiene, como mucho, una página de la sección «Texto» de un
/// documento procesado (F41, decisión B).
///
/// Medido con un libro sintético de 3 millones de caracteres (flutter test en
/// la PC, la base en su propio hilo, como en la app; el teléfono es varias
/// veces más lento):
///
/// | guardado          | guardar | corregir 1 letra | leer 1 página | buscar |
/// |-------------------|--------:|-----------------:|--------------:|-------:|
/// | una sola fila     |  170 ms |           280 ms |         50 ms |   2 ms |
/// | páginas de 2.000  |  340 ms |             8 ms |          9 ms |   3 ms |
/// | páginas de 8.000  |  151 ms |             8 ms |          4 ms |   2 ms |
/// | páginas de 32.000 |  124 ms |            11 ms |          2 ms |   2 ms |
///
/// En una sola fila, cada corrección reindexa el libro entero y abrir una
/// página trae el libro entero a la interfaz. Con páginas de 8.000, el libro
/// son 390 filas: guardarlo cuesta lo mismo que una fila, y corregir o leer
/// cuesta lo que mide una página, no el libro. Más chicas no ganan nada y
/// multiplican las filas; más grandes vuelven a acercarse a la fila única.
const kProcessedTextPageChars = 8000;

/// Desde cuántos caracteres el trabajo sobre un texto se hace en otro hilo
/// (`compute`), y no en el de la interfaz: el mismo umbral desde el que un
/// texto largo se lee por páginas (F39, `1d4cf338`). Por debajo, abrir un hilo
/// cuesta más que el trabajo.
const kProcessedInlineChars = 60000;

/// Un tramo del texto de una fuente que se excluye al paginar: lo que ya
/// ocupa una página que la persona editó.
typedef ProcessedRange = ({int start, int end});

/// Las páginas de [text] (F41): cortes de hasta [kProcessedTextPageChars]
/// caracteres donde menos rompen (`splitIntoParts`), sin los tramos de
/// [excluded] —ordenados y sin solaparse—.
///
/// Sin [excluded], las páginas una detrás de la otra son [text] entero, sin
/// perder ni repetir nada. Con [excluded], son exactamente el resto: se pagina
/// el texto entero y de cada página se saca lo que cae en un tramo excluido.
/// Así una página que no toca ningún tramo es la MISMA que sin excluir nada, y
/// «Actualizar» sobre un texto que no cambió —excluyendo las páginas que la
/// persona editó, que coinciden con páginas de antes— deja todas las demás
/// como estaban.
List<TextPart> processedTextPages(
  String text, {
  List<ProcessedRange> excluded = const [],
}) {
  final pages = splitIntoParts(text, maxChars: kProcessedTextPageChars);
  if (excluded.isEmpty) return pages;
  final kept = <TextPart>[];
  var next = 0;
  for (final page in pages) {
    // Los tramos que terminan antes de esta página ya no tocan ninguna.
    while (next < excluded.length && excluded[next].end <= page.start) {
      next++;
    }
    var from = page.start;
    for (var i = next; i < excluded.length; i++) {
      final range = excluded[i];
      if (range.start >= page.end) break;
      if (range.start > from) {
        kept.add(
          TextPart(start: from, text: text.substring(from, range.start)),
        );
      }
      if (range.end > from) from = range.end;
    }
    if (from == page.start) {
      kept.add(page);
    } else if (from < page.end) {
      kept.add(TextPart(start: from, text: text.substring(from, page.end)));
    }
  }
  return kept;
}

/// Cuántas palabras tiene [text]: los tramos separados por espacios.
int processedWordCount(String text) {
  var words = 0;
  var inWord = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final space =
        unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;
    if (space) {
      inWord = false;
    } else if (!inWord) {
      inWord = true;
      words++;
    }
  }
  return words;
}

/// Quién corre el trabajo pesado: [runProcessedWork], o el doble de una prueba.
typedef ProcessedWorker =
    Future<R> Function<Q, R>(
      ComputeCallback<Q, R> work,
      Q message, {
      required int size,
    });

/// Corre [work] sobre [message]: en otro hilo si [size] —cuántos caracteres de
/// texto mueve— pasa de [kProcessedInlineChars], y en este si no. Es lo que
/// hace que procesar un libro no frene la interfaz y procesar un artículo no
/// pague un hilo.
Future<R> runProcessedWork<Q, R>(
  ComputeCallback<Q, R> work,
  Q message, {
  required int size,
}) async {
  if (size <= kProcessedInlineChars) return work(message);
  return compute(work, message);
}
