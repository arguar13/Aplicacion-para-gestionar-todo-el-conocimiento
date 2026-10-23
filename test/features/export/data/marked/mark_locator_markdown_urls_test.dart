import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/export/data/marked/mark_locator.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';

/// `locateMarks` con `markdownUrls` (F38, página web y EPUB): el texto
/// extraído es Markdown con las direcciones de sus enlaces y sus imágenes, y
/// el archivo las tiene en un atributo, no en el texto.
void main() {
  const extracted =
      'Intro.\n\n'
      'La **revolución** [vida cotidiana](http://x.org/a) cambió todo.\n\n'
      '![una foto](data:image/png;base64,AAAA)\n\n'
      'Fin del texto.';
  const haystack =
      'Intro.\nLa revolución vida cotidiana cambió todo.\nFin del texto.';

  DocumentMark markOf(String excerpt, {int occurrence = 0}) {
    var start = -1;
    for (var i = 0; i <= occurrence; i++) {
      start = extracted.indexOf(excerpt, start + 1);
    }
    return DocumentMark(
      start: start,
      end: start + excerpt.length,
      excerpt: excerpt,
      color: 0xFFFFF59D,
    );
  }

  String? picked(MarkSpan? span) =>
      span == null ? null : haystack.substring(span.start, span.end);

  test('un tramo que cruza un enlace se encuentra: la dirección no cuenta', () {
    final spans = locateMarks(
      haystack: haystack,
      extracted: extracted,
      marks: [
        markOf('La **revolución** [vida cotidiana](http://x.org/a) cambió'),
      ],
      markdownUrls: true,
    );

    expect(picked(spans.single), 'La revolución vida cotidiana cambió');
  });

  test('sin markdownUrls, ese mismo tramo no se encuentra', () {
    final spans = locateMarks(
      haystack: haystack,
      extracted: extracted,
      marks: [
        markOf('La **revolución** [vida cotidiana](http://x.org/a) cambió'),
      ],
    );

    expect(spans.single, isNull);
  });

  test('una imagen entera no cuenta, ni su texto alternativo ni su '
      'dirección: lo que le sigue se ubica igual, con su contexto', () {
    final spans = locateMarks(
      haystack: haystack,
      extracted: extracted,
      marks: [markOf('Fin del texto.')],
      markdownUrls: true,
    );

    expect(picked(spans.single), 'Fin del texto');
  });

  test('un texto alternativo que el archivo no tiene no hace fallar un '
      'tramo que lo rodea', () {
    final spans = locateMarks(
      haystack: haystack,
      extracted: extracted,
      marks: [
        markOf('cambió todo.\n\n![una foto](data:image/png;base64,AAAA)'),
      ],
      markdownUrls: true,
    );

    expect(picked(spans.single), 'cambió todo');
  });

  test('las repeticiones se distinguen por el lugar, con enlaces de por '
      'medio', () {
    const text = '[a](http://u/1) Dicho. [b](http://u/2) Dicho.';
    const page = 'a Dicho. b Dicho.';
    final second = text.lastIndexOf('Dicho.');
    final spans = locateMarks(
      haystack: page,
      extracted: text,
      marks: [
        DocumentMark(
          start: second,
          end: second + 6,
          excerpt: 'Dicho.',
          color: 0xFF000000,
        ),
      ],
      markdownUrls: true,
    );

    expect(spans.single!.start, page.lastIndexOf('Dicho'));
  });

  test('el contexto de antes no incluye la dirección del enlace: una '
      'dirección que dice lo mismo que el tramo no corre la cuenta', () {
    const text = 'Uno. [ver](http://uno.org) Uno. Uno.';
    const page = 'Uno. ver Uno. Uno.';
    final second = text.indexOf('Uno.', 10);
    final spans = locateMarks(
      haystack: page,
      extracted: text,
      marks: [
        DocumentMark(
          start: second,
          end: second + 4,
          excerpt: 'Uno.',
          color: 0xFF000000,
        ),
      ],
      markdownUrls: true,
    );

    // La segunda «Uno», que está después del enlace, y no la tercera.
    expect(spans.single!.start, page.indexOf('Uno', 5));
  });

  test('la letra que sigue pegada a la dirección sí cuenta', () {
    const text = '[a](http://u.org)seguido x. seguido';
    const page = 'aseguido x. seguido';
    final second = text.lastIndexOf('seguido');
    final spans = locateMarks(
      haystack: page,
      extracted: text,
      marks: [
        DocumentMark(
          start: second,
          end: second + 7,
          excerpt: 'seguido',
          color: 0xFF000000,
        ),
      ],
      markdownUrls: true,
    );

    expect(spans.single!.start, page.lastIndexOf('seguido'));
  });
}
