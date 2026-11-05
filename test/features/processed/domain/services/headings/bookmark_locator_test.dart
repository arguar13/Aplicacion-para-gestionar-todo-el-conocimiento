import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/bookmark_locator.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Los marcadores de un PDF ubicados en su texto procesado (F46, decisión
/// B): el título escrito como renglones enteros, en su página si se sabe
/// dónde cae cada una, y si no entre sus vecinos, sin que el índice del
/// propio libro se lleve ninguno.
void main() {
  const body = 'Un párrafo del cuerpo del libro, con lo que cuenta.';

  /// Lo que cubre el lugar de cada marcador, o `null`.
  List<String?> foundIn(
    String text,
    List<PdfBookmark> bookmarks, {
    int? pageCount,
  }) {
    final slices = pageCount == null
        ? null
        : pdfPageSlicesBySeparator(text, pageCount);
    return locateBookmarks(text, bookmarks, pageSlices: slices)
        .map(
          (place) =>
              place == null ? null : text.substring(place.start, place.end),
        )
        .toList();
  }

  PdfBookmark mark(String title, [int? page]) =>
      PdfBookmark(title: title, depth: 1, page: page);

  /// Un PDF de [pages] páginas, unidas como las une la extracción.
  String pdf(List<String> pages) => pages.join(pdfPageSeparator);

  test('cada marcador, en su página: el índice del libro, en otra, no lo '
      'confunde', () {
    final text = pdf([
      'Índice\nIntroducción\nEl origen',
      'Introducción\n$body',
      'El origen\n$body',
    ]);
    final places = locateBookmarks(text, [
      mark('Introducción', 2),
      mark('El origen', 3),
    ], pageSlices: pdfPageSlicesBySeparator(text, 3));
    expect(places[0]!.start, text.indexOf('Introducción\n$body'));
    expect(places[1]!.start, text.indexOf('El origen\n$body'));
  });

  test('se compara sin mayúsculas, acentos ni puntuación, y un título puede '
      'ocupar varios renglones', () {
    final text = pdf(['CAPITULO 1\nEL ORIGEN\n$body']);
    expect(foundIn(text, [mark('Capítulo 1: El origen', 1)], pageCount: 1), [
      'CAPITULO 1\nEL ORIGEN',
    ]);
  });

  test(
    'hasta tres renglones: un párrafo que empieza igual no es el título',
    () {
      final text = pdf(['Uno\ndos\ntres\ncuatro\n$body']);
      expect(foundIn(text, [mark('Uno dos tres', 1)], pageCount: 1), [
        'Uno\ndos\ntres',
      ]);
      expect(foundIn(text, [mark('Uno dos tres cuatro', 1)], pageCount: 1), [
        null,
      ]);
    },
  );

  test('una mención en medio de un párrafo, o un renglón del índice con su '
      'página, no cuentan', () {
    final text = pdf([
      'Como se ve en El origen, todo empieza ahí.',
      'El origen ........ 4',
    ]);
    expect(foundIn(text, [mark('El origen', 1)], pageCount: 2), [null]);
    expect(foundIn(text, [mark('El origen', 2)], pageCount: 2), [null]);
  });

  test('lo que no está en su página no se ubica: queda con su página y sin '
      'lugar', () {
    final text = pdf(['El origen\n$body', body]);
    expect(foundIn(text, [mark('El origen', 2)], pageCount: 2), [null]);
  });

  test('sin una raya por página, cada uno en el último lugar antes del que '
      'sigue: el índice del libro, adelante, no se lleva ninguno', () {
    const text =
        'Índice\n\nIntroducción\n\nEl origen\n\nLa caída\n\n'
        'Introducción\n\n$body\n\nEl origen\n\n$body\n\nLa caída\n\n$body';
    final places = locateBookmarks(text, [
      mark('Introducción', 2),
      mark('El origen', 3),
      mark('La caída', 4),
    ]);
    expect(places[0]!.start, text.indexOf('Introducción\n\n$body'));
    expect(places[1]!.start, text.indexOf('El origen\n\n$body'));
    expect(places[2]!.start, text.indexOf('La caída\n\n$body'));
  });

  test('sin una raya por página, los títulos repetidos caen cada uno en su '
      'capítulo', () {
    const text =
        'Uno\n\n$body\n\nEjercicios\n\n$body\n\n'
        'Dos\n\n$body\n\nEjercicios\n\n$body';
    final places = locateBookmarks(text, [
      mark('Uno'),
      mark('Ejercicios'),
      mark('Dos'),
      mark('Ejercicios'),
    ]);
    final first = text.indexOf('Ejercicios');
    expect(places[1]!.start, first);
    expect(places[3]!.start, text.indexOf('Ejercicios', first + 1));
    expect(places[2]!.start, text.indexOf('Dos'));
  });

  test('un marcador sin página se busca entre los vecinos que sí se '
      'ubicaron en la suya', () {
    final text = pdf([
      'Prólogo\n$body',
      'Primera parte\n$body\nUn interludio\n$body',
      'Segunda parte\n$body',
    ]);
    expect(
      foundIn(text, [
        mark('Primera parte', 2),
        mark('Un interludio'),
        mark('Segunda parte', 3),
      ], pageCount: 3),
      ['Primera parte', 'Un interludio', 'Segunda parte'],
    );
  });

  test('una página fuera del PDF, o una cuenta de páginas que no da, se '
      'buscan entre vecinos', () {
    final text = pdf(['Uno\n$body', 'Dos\n$body']);
    expect(foundIn(text, [mark('Uno', 9), mark('Dos', 2)], pageCount: 2), [
      'Uno',
      'Dos',
    ]);
    // Tres páginas que el texto no tiene: sin tramos, entre vecinos.
    expect(foundIn(text, [mark('Uno', 1), mark('Dos', 2)], pageCount: 3), [
      'Uno',
      'Dos',
    ]);
  });

  test('sin marcadores, o un título sin palabras, nada', () {
    expect(locateBookmarks('Texto', const []), isEmpty);
    expect(locateBookmarks('—\n\nTexto', [mark('—')]), [null]);
  });
}
